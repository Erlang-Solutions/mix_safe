defmodule Safe.Shell do
  @moduledoc """
  Executes the SAFE binary via `System.cmd/3`.

  Arguments are passed as a list — no shell string is constructed — so there
  is no risk of command injection from user-controlled data such as the
  project path or config JSON.
  """

  require Logger

  @doc """
  Runs the SAFE binary with the given subcommand, streaming output line-by-line
  to stdout.

  `config_spec` is either `{:config_path, path}` (pass `--config-path <file>`)
  or `{:config_json, json}` (pass `--config-json <inline_json>`).

  Returns `:ok` on exit code 0, or `{:error, {subcommand_atom, exit_code}}`
  for any non-zero exit. Exit code 2 indicates vulnerabilities were found and
  is treated as a distinct (non-fatal) result by the caller.
  """
  def run_safe(subcommand, project_dir, {:config_path, path}) do
    run(subcommand, project_dir, ["--config-path", path])
  end

  def run_safe(subcommand, project_dir, {:config_json, json}) do
    clean_json = String.replace(json, ~r/\r|\n/, "")
    run(subcommand, project_dir, ["--config-json", clean_json])
  end

  defp run(subcommand, project_dir, config_args) do
    binary_path = Safe.Binary.binary_path(project_dir)
    dir = Path.dirname(binary_path)

    Logger.debug("Running: #{binary_path} #{subcommand} in #{dir}")

    {_output, exit_code} =
      System.cmd(
        binary_path,
        [subcommand] ++ config_args ++ ["--project-root", project_dir],
        cd: dir,
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )

    case exit_code do
      0 -> :ok
      code -> {:error, {String.to_atom(subcommand), code}}
    end
  end
end

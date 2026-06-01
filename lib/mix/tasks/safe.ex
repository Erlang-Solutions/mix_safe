defmodule Mix.Tasks.Safe do
  @shortdoc "SAFE security vulnerability scanner"

  @moduledoc """
  Runs SAFE security vulnerability scans on your Elixir/Mix project.

  ## Usage

      mix safe <subcommand> [options]

  ## Subcommands

    * `fingerprint` — run the SAFE fingerprint phase
    * `analyse`     — run the SAFE analysis phase
    * `sca`         — scan dependencies for known vulnerabilities (Supply Chain Analysis)
    * `download`    — download the SAFE binary only
    * `version`     — print plugin and binary versions
    * `help`        — print this help

  ## Examples

      mix safe fingerprint
      mix safe analyse
      mix safe sca
      mix safe sca --lock-file /path/to/mix.lock
      mix safe sca --advisories ./my-advisories/
      mix safe sca --warnings-as-errors
      mix safe download
      mix safe version

  ## Debug logging

  Detailed debug output is written to `_build/safe/safe.log`. The terminal
  shows only info-level messages.

  """

  use Mix.Task

  require Logger

  @version Mix.Project.config()[:version]

  @impl Mix.Task
  def run(args) do
    project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()

    setup_file_logger(project_dir)
    Logger.debug("project_dir=#{project_dir}")

    case args do
      ["sca" | sca_args] -> handle_sca(project_dir, sca_args)
      ["fingerprint" | _] -> handle_fingerprint(project_dir)
      ["analyse" | _] -> handle_analyse(project_dir)
      ["download" | _] -> handle_download(project_dir)
      ["version" | _] -> handle_version(project_dir)
      ["help" | _] -> handle_help()
      [] -> error_and_exit("No subcommand specified. Run `mix safe help` for usage.", 1)
      [other | _] -> error_and_exit("Unrecognised subcommand: #{other}. Run `mix safe help`.", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Subcommand handlers
  # ---------------------------------------------------------------------------

  defp handle_fingerprint(project_dir) do
    Logger.debug("running fingerprint")

    with :ok <- ensure_binary(project_dir),
         {:ok, config_spec} <- resolve_config_for_fingerprint(project_dir) do
      Safe.IO.print_status("* running SAFE fingerprint")

      case Safe.Shell.run_safe("fingerprint", project_dir, config_spec) do
        :ok ->
          Safe.IO.print_status("* SAFE fingerprint complete")

        {:error, {"fingerprint", 2}} ->
          Safe.IO.print_status("* SAFE fingerprint complete - vulnerabilities found.")
          exit_with(2)

        {:error, {"fingerprint", n}} ->
          handle_error({:fingerprint, n})
      end
    else
      {:error, reason} -> handle_error(reason)
    end
  end

  defp handle_analyse(project_dir) do
    Logger.debug("running analyse")

    with :ok <- ensure_binary(project_dir),
         {:ok, config_spec} <- resolve_config_for_analyse(project_dir) do
      Safe.IO.print_status("* running SAFE analysis")

      case Safe.Shell.run_safe("analyse", project_dir, config_spec) do
        :ok ->
          Safe.IO.print_status("* SAFE analysis complete - no vulnerabilities found")

        {:error, {"analyse", 2}} ->
          Safe.IO.print_status("* SAFE analysis complete - vulnerabilities found.")
          exit_with(2)

        {:error, {"analyse", n}} ->
          handle_error({:analyse, n})
      end
    else
      {:error, reason} -> handle_error(reason)
    end
  end

  defp handle_sca(project_dir, args) do
    Logger.debug("running sca")

    case ensure_binary(project_dir) do
      :ok ->
        Safe.IO.print_status("* running SAFE SCA")

        case Safe.Shell.run_safe_sca(project_dir, args) do
          :ok ->
            Safe.IO.print_status("* SAFE SCA complete - no vulnerabilities found")

          {:error, {:sca, 2}} ->
            Safe.IO.print_status("* SAFE SCA complete - vulnerabilities found.")
            exit_with(2)

          {:error, {:sca, 3}} ->
            Safe.IO.print_status("* SAFE SCA - warnings treated as errors.")
            exit_with(3)

          {:error, {:sca, n}} ->
            handle_error({:sca, n})
        end

      {:error, reason} ->
        handle_error(reason)
    end
  end

  defp handle_download(project_dir) do
    Logger.debug("running download")
    Safe.IO.print_status("* checking for SAFE binary")

    case Safe.Binary.ensure_binary_available(project_dir) do
      :ok -> Safe.IO.print_status("* SAFE binary ready")
      {:error, reason} -> handle_error(reason)
    end
  end

  defp handle_version(project_dir) do
    Safe.IO.print_info("* safe-mix-plugin version: #{@version}")
    bin_path = Safe.Binary.binary_path(project_dir)

    if File.exists?(bin_path) do
      dir = Path.dirname(bin_path)

      case System.cmd(bin_path, ["version"],
             cd: dir,
             stderr_to_stdout: true,
             into: IO.stream(:stdio, :line)
           ) do
        {_, 0} -> :ok
        {_, n} -> handle_error({:version_failed, n})
      end
    else
      Safe.IO.print_info("* SAFE binary not yet downloaded")
    end
  end

  defp handle_help do
    __MODULE__ |> Mix.Task.moduledoc() |> Safe.IO.print_info()
  end

  # ---------------------------------------------------------------------------
  # Config resolution
  # ---------------------------------------------------------------------------

  defp resolve_config_for_fingerprint(project_dir) do
    config_path = Safe.Config.config_path(project_dir)

    if File.exists?(config_path) do
      Safe.IO.print_status("* Using config from .safe/config.json")
      {:ok, {:config_path, config_path}}
    else
      safe_fingerprint_no_config(project_dir)
    end
  end

  defp safe_fingerprint_no_config(project_dir) do
    Safe.IO.print_status("* checking your project's structure")

    with {:ok, apps} <- discover_apps(),
         {:ok, config_json} <- Safe.Config.make_config(project_dir) do
      Safe.IO.print_info("* Discovered #{length(apps)} app(s): #{inspect(Enum.map(apps, & &1.name))}")

      Safe.IO.print_info(config_json)

      if Safe.IO.bool_prompt("Would you like to proceed with this configuration?") do
        {:ok, {:config_json, config_json}}
      else
        save_config_and_exit(project_dir, config_json)
      end
    end
  end

  defp save_config_and_exit(project_dir, config_json) do
    case Safe.Config.write_config(project_dir, config_json) do
      :ok ->
        Safe.IO.print_info("Config saved to .safe/config.json. Edit it and re-run `mix safe fingerprint`.")

        exit_with(0)

      {:error, reason} ->
        {:error, {:config_write_error, reason}}
    end
  end

  defp resolve_config_for_analyse(project_dir) do
    config_path = Safe.Config.config_path(project_dir)

    if File.exists?(config_path) do
      Safe.IO.print_info("* Using config from .safe/config.json")
      {:ok, {:config_path, config_path}}
    else
      {:ok, json} = Safe.Config.make_config(project_dir)
      {:ok, {:config_json, json}}
    end
  end

  defp discover_apps do
    if Mix.Project.umbrella?() do
      apps =
        Enum.map(Mix.Project.apps_paths(), fn {name, _path} -> %{name: name} end)

      {:ok, apps}
    else
      app_name = Mix.Project.config()[:app]
      {:ok, [%{name: app_name}]}
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  defp ensure_binary(project_dir) do
    case Safe.Binary.ensure_binary_available(project_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec handle_error(term()) :: no_return()
  defp handle_error(:unsupported_platform) do
    error_and_exit("Unsupported platform. SAFE supports Linux and macOS only.", 1)
  end

  defp handle_error(:unsupported_arch) do
    error_and_exit("Unsupported CPU architecture. SAFE supports x86_64 and ARM64.", 1)
  end

  defp handle_error({:no_checksum_for_platform, platform}) do
    error_and_exit("No checksum available for platform #{platform}", 1)
  end

  defp handle_error(:no_compatible_version) do
    error_and_exit("No compatible SAFE version found (requires ~> 1.5.0)", 1)
  end

  defp handle_error({:locked_version_not_found, version}) do
    error_and_exit(
      "Version #{version} from safe.lock not found in manifest. Delete safe.lock and re-run.",
      1
    )
  end

  defp handle_error({:checksum_mismatch, _}) do
    error_and_exit("Downloaded file is corrupted (checksum mismatch). Please try again.", 1)
  end

  defp handle_error({:download_failed, url, reason}) do
    error_and_exit("Failed to download SAFE from #{url}: #{inspect(reason)}", 1)
  end

  defp handle_error({:http_error, 404}) do
    error_and_exit("SAFE version not found. Check version and try again.", 1)
  end

  defp handle_error({:http_error, code}) do
    error_and_exit("HTTP error #{code} while contacting SAFE release server.", 1)
  end

  defp handle_error({:config_read_error, reason}) do
    error_and_exit("Failed to read .safe/config.json: #{inspect(reason)}", 1)
  end

  defp handle_error({:fingerprint, 2}) do
    error_and_exit("SAFE analysis complete - vulnerabilities found.", 2)
  end

  defp handle_error({:fingerprint, n}) do
    error_and_exit("SAFE fingerprint failed with exit code #{n}.", 1)
  end

  defp handle_error({:analyse, 2}) do
    error_and_exit("SAFE analysis complete - vulnerabilities found.", 2)
  end

  defp handle_error({:analyse, n}) do
    error_and_exit("SAFE analysis failed with exit code #{n}.", 1)
  end

  defp handle_error({:sca, 2}) do
    error_and_exit("SAFE SCA complete - vulnerabilities found.", 2)
  end

  defp handle_error({:sca, 3}) do
    error_and_exit("SAFE SCA - warnings treated as errors.", 3)
  end

  defp handle_error({:sca, n}) do
    error_and_exit("SAFE SCA failed with exit code #{n}.", 1)
  end

  defp handle_error({:version_failed, n}) do
    error_and_exit("SAFE binary `version` command failed with exit code #{n}.", 1)
  end

  defp handle_error(:binary_not_found_after_extract) do
    error_and_exit(
      "SAFE binary not found after extraction. The tarball layout may have changed.",
      1
    )
  end

  defp handle_error({:untar_failed, reason}) do
    error_and_exit("Failed to extract SAFE tarball: #{inspect(reason)}", 1)
  end

  defp handle_error(reason) do
    error_and_exit("Unexpected error: #{inspect(reason)}", 1)
  end

  @spec error_and_exit(String.t(), non_neg_integer()) :: no_return()
  defp error_and_exit(message, code) do
    Safe.IO.print_error(message)
    exit_with(code)
  end

  # ---------------------------------------------------------------------------
  # Logger file setup
  # ---------------------------------------------------------------------------

  defp setup_file_logger(project_dir) do
    log_dir = Path.join([project_dir, "_build", "safe"])
    File.mkdir_p!(log_dir)
    log_file = log_dir |> Path.join("safe.log") |> String.to_charlist()

    case :logger.add_handler(:safe_file_handler, :logger_std_h, %{
           level: :debug,
           config: %{type: :file, file: log_file}
         }) do
      :ok ->
        :ok

      {:error, {:already_exist, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not set up SAFE file logger: #{inspect(reason)}")
    end

    :logger.set_handler_config(:default, :level, :info)
  end

  @spec exit_with(non_neg_integer()) :: no_return()
  defp exit_with(code), do: exit({:shutdown, code})
end

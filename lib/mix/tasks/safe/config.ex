defmodule Safe.Config do
  @moduledoc """
  Generates the SAFE JSON configuration from the Mix project structure.

  Generates `.safe/config.json` for the SAFE scanner.
  """

  require Logger

  @config_version "1.1"
  @config_dir ".safe"
  @config_file "config.json"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns the path to the SAFE config file for the given project."
  def config_path(project_dir) do
    Path.join([project_dir, @config_dir, @config_file])
  end

  @doc """
  Generates the SAFE JSON config string from the live Mix project.

  Returns `{:ok, json_string}`. Does not write to disk.
  """
  def make_config(project_dir) do
    build_config(project_dir, primary_app_name(), get_apps(project_dir))
  end

  @doc false
  def build_config(project_dir, app_name, apps) do
    ebin_paths = Enum.map(apps, &ebin_path(project_dir, &1.name))
    common_path = longest_common_prefix(ebin_paths)

    config = %{
      "output" => ["stdio", "file"],
      "version" => @config_version,
      "project" => %{
        "name" => to_string(app_name),
        "type" => "beam",
        "apps" => Enum.map(apps, &app_entry(project_dir, &1)),
        "paths" => [common_path]
      }
    }

    {:ok, Jason.encode!(config, pretty: true)}
  end

  @doc """
  Reads `.safe/config.json` from the project directory.

  Returns `{:ok, json_string}` or `{:error, {:config_read_error, reason}}`.
  """
  def read_config(project_dir) do
    case File.read(config_path(project_dir)) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:config_read_error, reason}}
    end
  end

  @doc "Writes `json` to `.safe/config.json` in the project directory."
  def write_config(project_dir, json) do
    path = config_path(project_dir)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, json)
    end
  end

  @doc """
  Finds the longest common directory prefix shared by all `paths`.

  Each path is split into segments; shared leading segments are rejoined.
  Returns an empty string when `paths` is empty or no segments are shared.
  """
  def longest_common_prefix([]), do: ""

  def longest_common_prefix([single]), do: single

  def longest_common_prefix(paths) do
    split = Enum.map(paths, &Path.split/1)

    common =
      split
      |> Enum.zip_with(& &1)
      |> Enum.take_while(fn segments -> length(Enum.uniq(segments)) == 1 end)
      |> Enum.map(&hd/1)

    case common do
      [] -> ""
      segments -> Path.join(segments)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_apps(_project_dir) do
    if Mix.Project.umbrella?() do
      Mix.Project.apps_paths()
      |> Enum.map(fn {app_name, _path} ->
        %{name: app_name}
      end)
    else
      app_name = Mix.Project.config()[:app]
      [%{name: app_name}]
    end
  end

  defp primary_app_name do
    Mix.Project.config()[:app]
  end

  defp app_entry(_project_dir, %{name: name}) do
    env = to_string(Mix.env())
    app_name = to_string(name)
    app_file = Path.join(["_build", env, "lib", app_name, "ebin", "#{app_name}.app"])

    %{
      "name" => app_name,
      "app_file" => app_file,
      "additional_includes" => []
    }
  end

  defp ebin_path(project_dir, app_name) do
    env = to_string(Mix.env())
    Path.join([project_dir, "_build", env, "lib", to_string(app_name), "ebin"])
  end
end

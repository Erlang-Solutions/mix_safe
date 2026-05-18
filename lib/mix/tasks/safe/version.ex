defmodule Safe.Version do
  @moduledoc """
  Version resolution and lock file management for the SAFE binary.

  Resolves the SAFE binary version against a semver constraint, reads/writes
  the `safe.lock` file (JSON format).
  """

  @constraint_string "~> 1.5.0"
  @constraint Version.parse_requirement!(@constraint_string)
  @lock_file "safe.lock"

  @doc "Returns the semver constraint used to resolve SAFE binary versions."
  def constraint, do: @constraint

  @doc "Returns the mix_safe plugin version (compiled from mix.exs at build time)."
  def plugin_version do
    Mix.Project.config()[:version]
  end

  @doc "Returns true if the version satisfies the `~> 1.5.0` constraint."
  def compatible?(version_string) do
    case Version.parse(normalize_version(version_string)) do
      {:ok, %Version{pre: [_ | _]}} -> false
      {:ok, v} -> Version.match?(v, @constraint_string)
      _ -> false
    end
  end

  @doc """
  Picks the latest stable version from `versions_map` (a map of version string =>
  platform checksums) that satisfies the constraint. Pre-releases are excluded.
  """
  def resolve_version(versions_map) do
    result =
      versions_map
      |> Map.keys()
      |> Enum.filter(&compatible?/1)
      |> Enum.sort(fn a, b ->
        case {Version.parse(normalize_version(a)), Version.parse(normalize_version(b))} do
          {{:ok, va}, {:ok, vb}} -> Version.compare(va, vb) == :gt
          _ -> false
        end
      end)
      |> List.first()

    case result do
      nil -> {:error, :no_compatible_version}
      v -> {:ok, v}
    end
  end

  @doc """
  Reads the pinned SAFE version from `<project_dir>/safe.lock`.

  Returns `{:ok, version_string}` or `{:error, :not_found}`.
  """
  def read_lock(project_dir) do
    path = lock_path(project_dir)

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"version" => version}} when is_binary(version) ->
            {:ok, version}

          _ ->
            {:error, {:lock_parse_error, path}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:lock_read_error, reason}}
    end
  end

  @doc """
  Writes the pinned SAFE version to `<project_dir>/safe.lock` in JSON format.
  """
  def write_lock(project_dir, version) do
    contents = Jason.encode!(%{"version" => version})

    case File.write(lock_path(project_dir), contents) do
      :ok -> :ok
      {:error, reason} -> {:error, {:lock_write_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp lock_path(project_dir), do: Path.join(project_dir, @lock_file)

  defp normalize_version(v), do: v
end

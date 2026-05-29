defmodule Safe.Binary do
  @moduledoc """
  Manages downloading, verifying, and caching the SAFE binary.

  The binary is stored at `<project_root>/_build/safe/safe`. A SHA-256
  checksum is verified against the manifest before the tarball is extracted.
  """

  require Logger

  @manifest_url "https://safe-releases.s3.eu-central-1.amazonaws.com/versions.json"
  @build_dir "_build/safe"
  @binary_name "safe"
  @checksum_suffix ".sha256"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns the expected path of the SAFE binary for the given project."
  def binary_path(project_dir) do
    Path.join([project_dir, @build_dir, @binary_name])
  end

  @doc """
  Detects the current OS. Returns `{:ok, "linux"}`, `{:ok, "macos"}`, or
  `{:error, :unsupported_platform}`.
  """
  def detect_os do
    case :os.type() do
      {:unix, :linux} -> {:ok, "linux"}
      {:unix, :darwin} -> {:ok, "macos"}
      _ -> {:error, :unsupported_platform}
    end
  end

  @doc """
  Detects the CPU architecture and normalises it to the string used in SAFE
  release filenames. Returns `{:ok, "x86_64"}` on all supported architectures
  (Intel, AMD, ARM64/Apple Silicon), or `{:error, :unsupported_arch}`.

  SAFE ships a universal macOS binary and an x86_64 Linux binary, so all
  common architectures map to "x86_64".
  """
  def detect_arch do
    arch = :system_architecture |> :erlang.system_info() |> to_string()
    normalize_arch(arch)
  end

  @doc "Normalises an architecture string to the value used in SAFE release filenames."
  def normalize_arch(arch) do
    cond do
      String.contains?(arch, "x86_64") -> {:ok, "x86_64"}
      String.contains?(arch, "amd64") -> {:ok, "x86_64"}
      String.contains?(arch, "aarch64") -> {:ok, "x86_64"}
      String.contains?(arch, "arm64") -> {:ok, "x86_64"}
      true -> {:error, :unsupported_arch}
    end
  end

  @doc "Computes a lowercase hex SHA-256 digest of `binary_data`."
  def compute_checksum(binary_data) do
    :sha256
    |> :crypto.hash(binary_data)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Returns true when `actual` and `expected` represent the same checksum.
  Comparison is case-insensitive and trims surrounding whitespace.
  """
  def verify_checksum(actual, expected) do
    String.downcase(String.trim(actual)) ==
      String.downcase(String.trim(expected))
  end

  @doc """
  Ensures the SAFE binary is present at `_build/safe/safe`.

  If the binary already exists, returns `:ok` immediately.
  Otherwise resolves the version (from `safe.lock` or the S3 manifest),
  downloads the tarball, verifies its checksum, extracts it, and writes
  `safe.lock`.
  """
  def ensure_binary_available(project_dir) do
    Application.ensure_all_started(:hackney)
    bin_path = binary_path(project_dir)

    case verify_cached_binary(bin_path) do
      :ok ->
        Logger.debug("SAFE binary already present and verified at #{bin_path}")
        :ok

      :stale ->
        with {:ok, os} <- detect_os(),
             {:ok, arch} <- detect_arch(),
             {:ok, version, versions_map} <- resolve_version(project_dir),
             :ok <- reset_build_dir(project_dir),
             {:ok, tar_path} <- download_binary(version, os, arch, project_dir),
             :ok <- verify_and_extract(tar_path, version, os, arch, versions_map, project_dir),
             :ok <- Safe.Version.write_lock(project_dir, version) do
          Logger.debug("SAFE #{version} installed at #{bin_path}")
          :ok
        end
    end
  end

  defp verify_cached_binary(bin_path) do
    sidecar = bin_path <> @checksum_suffix

    with true <- File.exists?(bin_path),
         true <- File.exists?(sidecar),
         {:ok, data} <- File.read(bin_path),
         {:ok, expected} <- File.read(sidecar),
         true <- verify_checksum(compute_checksum(data), expected) do
      :ok
    else
      _ ->
        if File.exists?(bin_path) do
          Logger.debug("Cached SAFE binary at #{bin_path} failed re-verification; re-downloading")
        end

        :stale
    end
  end

  defp reset_build_dir(project_dir) do
    dir = Path.join(project_dir, @build_dir)
    File.rm_rf!(dir)
    File.mkdir_p(dir)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_version(project_dir) do
    case Safe.Version.read_lock(project_dir) do
      {:ok, version} ->
        Logger.debug("Using pinned SAFE version #{version} from safe.lock")

        with {:ok, body} <- http_get(@manifest_url),
             {:ok, versions_map} <- Jason.decode(body),
             :ok <- validate_locked_version(versions_map, version) do
          {:ok, version, versions_map}
        end

      {:error, reason}
      when reason in [:not_found] or
             (is_tuple(reason) and elem(reason, 0) == :lock_parse_error) ->
        Logger.debug("No valid safe.lock found, fetching manifest from S3")

        with {:ok, body} <- http_get(@manifest_url),
             {:ok, versions_map} <- Jason.decode(body),
             {:ok, version} <- Safe.Version.resolve_version(versions_map) do
          {:ok, version, versions_map}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_locked_version(versions_map, version) do
    if Map.has_key?(versions_map, version) do
      :ok
    else
      {:error, {:locked_version_not_found, version}}
    end
  end

  defp download_binary(version, os, arch, project_dir) do
    filename = "safe-#{version}-#{os}-#{arch}.tar.gz"
    url = "https://safe-releases.s3.eu-central-1.amazonaws.com/#{version}/#{filename}"
    dest_dir = Path.join(project_dir, @build_dir)
    tar_path = Path.join(dest_dir, filename)

    Logger.debug("Downloading SAFE binary from #{url}")
    Safe.IO.print_status("* downloading SAFE #{version}")

    with :ok <- File.mkdir_p(dest_dir),
         {:ok, body} <- http_get(url) do
      case File.write(tar_path, body) do
        :ok -> {:ok, tar_path}
        {:error, reason} -> {:error, {:write_failed, tar_path, reason}}
      end
    else
      {:error, {:http_error, 404}} -> {:error, {:http_error, 404}}
      {:error, reason} -> {:error, {:download_failed, url, reason}}
    end
  end

  defp verify_and_extract(tar_path, version, os, arch, versions_map, project_dir) do
    platform_key = "#{os}-#{arch}"

    with {:ok, tar_data} <- File.read(tar_path),
         {:ok, expected_checksum} <- get_platform_checksum(versions_map, version, platform_key) do
      actual_checksum = compute_checksum(tar_data)
      extract_if_checksum_valid(tar_path, actual_checksum, expected_checksum, project_dir)
    end
  end

  defp extract_if_checksum_valid(tar_path, actual_checksum, expected_checksum, project_dir) do
    if verify_checksum(actual_checksum, expected_checksum) do
      dest_dir = Path.join(project_dir, @build_dir)

      case extract_tar(tar_path, dest_dir) do
        :ok -> finalize_binary(tar_path, project_dir)
        {:error, _} = err -> err
      end
    else
      File.rm(tar_path)
      {:error, {:checksum_mismatch, tar_path}}
    end
  end

  defp finalize_binary(tar_path, project_dir) do
    File.rm(tar_path)
    bin_path = binary_path(project_dir)

    if File.exists?(bin_path) do
      write_binary_checksum(bin_path)
      File.chmod!(bin_path, 0o755)
      :ok
    else
      {:error, :binary_not_found_after_extract}
    end
  end

  defp get_platform_checksum(versions_map, version, platform_key) do
    case get_in(versions_map, [version, platform_key]) do
      nil -> {:error, {:no_checksum_for_platform, platform_key}}
      checksum -> {:ok, checksum}
    end
  end

  defp extract_tar(tar_path, dest_dir) do
    tar_charlist = String.to_charlist(tar_path)
    dest_charlist = String.to_charlist(dest_dir)

    case :erl_tar.extract(tar_charlist, [:compressed, {:cwd, dest_charlist}]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:untar_failed, reason}}
    end
  end

  defp write_binary_checksum(bin_path) do
    digest = bin_path |> File.read!() |> compute_checksum()
    File.write!(bin_path <> @checksum_suffix, digest)
  end

  defp http_get(url) do
    http_client().get(url)
  end

  defp http_client do
    Application.get_env(:mix_safe, :http_client, Safe.HttpClient.Hackney)
  end
end

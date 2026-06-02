defmodule Safe.BinaryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Safe.Binary

  # ---------------------------------------------------------------------------
  # compute_checksum/1
  # ---------------------------------------------------------------------------

  alias Safe.HttpClient.Stub

  describe "compute_checksum/1" do
    test "returns lowercase hex SHA-256 of the input" do
      expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      assert Binary.compute_checksum("") == expected
    end

    test "returns lowercase hex for non-empty input" do
      result = Binary.compute_checksum("hello")
      assert result == String.downcase(result)
      assert String.length(result) == 64
    end
  end

  # ---------------------------------------------------------------------------
  # verify_checksum/2
  # ---------------------------------------------------------------------------

  describe "verify_checksum/2" do
    @checksum "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    test "returns true when checksums match exactly" do
      assert Binary.verify_checksum(@checksum, @checksum)
    end

    test "returns true when actual is uppercase and expected is lowercase" do
      assert Binary.verify_checksum(String.upcase(@checksum), @checksum)
    end

    test "returns true when checksums have surrounding whitespace" do
      assert Binary.verify_checksum("  #{@checksum}  ", "\n#{@checksum}\n")
    end

    test "returns false on mismatch" do
      refute Binary.verify_checksum(@checksum, "deadbeef")
    end
  end

  # ---------------------------------------------------------------------------
  # detect_os/0
  # ---------------------------------------------------------------------------

  describe "detect_os/0" do
    test "returns {:ok, os} where os is linux or macos on supported hosts" do
      case Binary.detect_os() do
        {:ok, os} -> assert os in ["linux", "macos"]
        {:error, :unsupported_platform} -> :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # detect_arch/0 and normalize_arch/1
  # ---------------------------------------------------------------------------

  describe "detect_arch/0" do
    test "returns {:ok, x86_64} or {:error, :unsupported_arch} on this host" do
      case Binary.detect_arch() do
        {:ok, arch} -> assert arch == "x86_64"
        {:error, :unsupported_arch} -> :ok
      end
    end
  end

  describe "normalize_arch/1" do
    test "x86_64 maps to x86_64" do
      assert {:ok, "x86_64"} = Binary.normalize_arch("x86_64-pc-linux-gnu")
    end

    test "amd64 maps to x86_64" do
      assert {:ok, "x86_64"} = Binary.normalize_arch("amd64")
    end

    test "aarch64 maps to x86_64" do
      assert {:ok, "x86_64"} = Binary.normalize_arch("aarch64-apple-darwin")
    end

    test "arm64 maps to x86_64" do
      assert {:ok, "x86_64"} = Binary.normalize_arch("arm64-apple-macosx")
    end

    test "unknown arch returns error" do
      assert {:error, :unsupported_arch} = Binary.normalize_arch("sparc")
    end
  end

  # ---------------------------------------------------------------------------
  # binary_path/1
  # ---------------------------------------------------------------------------

  describe "binary_path/1" do
    test "returns _build/safe/safe under the project dir" do
      assert Binary.binary_path("/my/project") == "/my/project/_build/safe/safe"
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_binary_available/1 (unit — mocked HTTP)
  # ---------------------------------------------------------------------------

  describe "ensure_binary_available/1 (unit)" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "safe_binary_unit_#{:rand.uniform(999_999)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      {:ok, os} = Binary.detect_os()
      {:ok, arch} = Binary.detect_arch()
      {:ok, project_dir: tmp, os: os, arch: arch}
    end

    defp make_tar_gz(tmp_dir) do
      src = Path.join(tmp_dir, "safe_src")
      File.write!(src, "#!/bin/sh\necho stub")
      tar_path = Path.join(tmp_dir, "test.tar.gz")
      :ok = :erl_tar.create(to_charlist(tar_path), [{~c"safe", to_charlist(src)}], [:compressed])
      {:ok, data} = File.read(tar_path)
      {data, Binary.compute_checksum(data)}
    end

    defp download_url(version, os, arch) do
      filename = "safe-#{version}-#{os}-#{arch}.tar.gz"
      "https://safe-releases.s3.eu-central-1.amazonaws.com/#{version}/#{filename}"
    end

    test "binary already exists skips HTTP entirely", %{project_dir: dir} do
      File.mkdir_p!(Path.join(dir, "_build/safe"))
      bin_path = Binary.binary_path(dir)
      data = "stub"
      File.write!(bin_path, data)
      File.write!(bin_path <> ".sha256", Binary.compute_checksum(data))
      assert :ok = Binary.ensure_binary_available(dir)
    end

    test "downloads, verifies, extracts binary from manifest", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      {tar_data, checksum} = make_tar_gz(dir)
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => checksum}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, tar_data}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert :ok = Binary.ensure_binary_available(dir)
      end)

      bin_path = Binary.binary_path(dir)
      assert File.exists?(bin_path)
      {:ok, stat} = File.stat(bin_path)
      assert Bitwise.band(stat.mode, 0o111) > 0
    end

    test "uses pinned version from safe.lock", %{project_dir: dir, os: os, arch: arch} do
      {tar_data, checksum} = make_tar_gz(dir)
      platform_key = "#{os}-#{arch}"
      Safe.Version.write_lock(dir, "1.5.2")
      manifest = Jason.encode!(%{"1.5.2" => %{platform_key => checksum}})
      dl_url = download_url("1.5.2", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, tar_data}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert :ok = Binary.ensure_binary_available(dir)
      end)
    end

    test "invalid lock file falls back to manifest resolution", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      File.write!(Path.join(dir, "safe.lock"), "not json")
      {tar_data, checksum} = make_tar_gz(dir)
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => checksum}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, tar_data}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert :ok = Binary.ensure_binary_available(dir)
      end)
    end

    test "locked version absent from manifest returns error", %{project_dir: dir} do
      Safe.Version.write_lock(dir, "9.9.9")
      manifest = Jason.encode!(%{"1.5.1" => %{}})

      Stub.set(fn _url -> {:ok, manifest} end)

      assert {:error, {:locked_version_not_found, "9.9.9"}} =
               Binary.ensure_binary_available(dir)
    end

    test "manifest HTTP error propagates", %{project_dir: dir} do
      Stub.set(fn _url -> {:error, {:http_error, 503}} end)

      assert {:error, {:http_error, 503}} = Binary.ensure_binary_available(dir)
    end

    test "download 404 returns http error", %{project_dir: dir, os: os, arch: arch} do
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => "somechecksum"}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:error, {:http_error, 404}}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert {:error, {:http_error, 404}} = Binary.ensure_binary_available(dir)
      end)
    end

    test "checksum mismatch deletes tarball and returns error", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      {tar_data, _} = make_tar_gz(dir)
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => "wrongchecksum000"}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, tar_data}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert {:error, {:checksum_mismatch, _}} = Binary.ensure_binary_available(dir)
      end)
    end

    test "no compatible version in manifest returns error", %{project_dir: dir} do
      manifest = Jason.encode!(%{"2.0.0" => %{}, "1.4.0" => %{}})

      Stub.set(fn _url -> {:ok, manifest} end)

      assert {:error, :no_compatible_version} = Binary.ensure_binary_available(dir)
    end

    test "lock_read_error (safe.lock is a directory) propagates from resolve_version", %{
      project_dir: dir
    } do
      File.mkdir_p!(Path.join(dir, "safe.lock"))

      Stub.set(fn _url -> {:ok, "{}"} end)

      assert {:error, {:lock_read_error, _}} = Binary.ensure_binary_available(dir)
    end

    test "non-404 download HTTP error returns download_failed", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => "somechecksum"}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:error, {:http_error, 503}}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert {:error, {:download_failed, _, _}} = Binary.ensure_binary_available(dir)
      end)
    end

    test "request failure (connection error) returns request_failed", %{project_dir: dir} do
      Stub.set(fn _url -> {:error, {:request_failed, :econnrefused}} end)

      assert {:error, {:request_failed, :econnrefused}} =
               Binary.ensure_binary_available(dir)
    end

    test "invalid tar.gz with matching checksum returns untar_failed", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      garbage = "not a valid tar.gz at all"
      checksum = Binary.compute_checksum(garbage)
      platform_key = "#{os}-#{arch}"
      manifest = Jason.encode!(%{"1.5.1" => %{platform_key => checksum}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, garbage}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert {:error, {:untar_failed, _}} = Binary.ensure_binary_available(dir)
      end)
    end

    test "missing platform key in versions_map returns error", %{
      project_dir: dir,
      os: os,
      arch: arch
    } do
      {tar_data, _} = make_tar_gz(dir)
      other_platform = if os == "linux", do: "macos-x86_64", else: "linux-x86_64"
      manifest = Jason.encode!(%{"1.5.1" => %{other_platform => "somehash"}})
      dl_url = download_url("1.5.1", os, arch)

      Stub.set(fn
        ^dl_url -> {:ok, tar_data}
        _url -> {:ok, manifest}
      end)

      capture_io(fn ->
        assert {:error, {:no_checksum_for_platform, _}} =
                 Binary.ensure_binary_available(dir)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_binary_available/1 (integration — hits real S3)
  # ---------------------------------------------------------------------------

  describe "ensure_binary_available/1 (integration)" do
    @describetag :integration

    setup do
      tmp = Path.join(System.tmp_dir!(), "safe_binary_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, project_dir: tmp}
    end

    test "downloads, verifies, and extracts the SAFE binary", %{project_dir: dir} do
      assert :ok = Binary.ensure_binary_available(dir)
      bin_path = Binary.binary_path(dir)
      assert File.exists?(bin_path)
      {:ok, stat} = File.stat(bin_path)
      assert Bitwise.band(stat.mode, 0o111) > 0
    end

    test "returns :ok immediately when binary already exists", %{project_dir: dir} do
      File.mkdir_p!(Path.join(dir, "_build/safe"))
      File.write!(Binary.binary_path(dir), "stub")
      assert :ok = Binary.ensure_binary_available(dir)
    end

    test "locked_version_not_found when safe.lock version absent from manifest", %{
      project_dir: dir
    } do
      Safe.Version.write_lock(dir, "0.0.0-nonexistent")

      assert {:error, {:locked_version_not_found, "0.0.0-nonexistent"}} =
               Binary.ensure_binary_available(dir)
    end
  end
end

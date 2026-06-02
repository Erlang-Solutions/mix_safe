defmodule Safe.VersionTest do
  use ExUnit.Case, async: true

  alias Safe.Version

  # ---------------------------------------------------------------------------
  # constraint/0 and plugin_version/0
  # ---------------------------------------------------------------------------

  describe "constraint/0" do
    test "returns a Version.Requirement" do
      req = Version.constraint()
      assert is_struct(req, Elixir.Version.Requirement)
    end
  end

  describe "plugin_version/0" do
    test "returns a semver string" do
      assert is_binary(Version.plugin_version())
      assert {:ok, _} = Elixir.Version.parse(Version.plugin_version())
    end
  end

  # ---------------------------------------------------------------------------
  # compatible?/1
  # ---------------------------------------------------------------------------

  describe "compatible?/1" do
    test "1.5.0-rc-0 does not satisfy ~> 1.5.0" do
      refute Version.compatible?("1.5.0-rc-0")
    end

    test "1.5.1-rc-0 does not satisfy ~> 1.5.0 (pre-releases excluded)" do
      refute Version.compatible?("1.5.1-rc-0")
    end

    test "1.5.1 satisfies ~> 1.5.0" do
      assert Version.compatible?("1.5.1")
    end

    test "1.5.9 satisfies ~> 1.5.0" do
      assert Version.compatible?("1.5.9")
    end

    test "1.6.0 does not satisfy ~> 1.5.0" do
      refute Version.compatible?("1.6.0")
    end

    test "1.4.9 does not satisfy ~> 1.5.0" do
      refute Version.compatible?("1.4.9")
    end

    test "1.5.0 satisfies ~> 1.5.0" do
      assert Version.compatible?("1.5.0")
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_version/1
  # ---------------------------------------------------------------------------

  describe "resolve_version/1" do
    @versions_map %{
      "1.4.9" => %{"linux-x86_64" => "aaa"},
      "1.5.0-rc-0" => %{"linux-x86_64" => "bbb"},
      "1.5.0" => %{"linux-x86_64" => "ccc"},
      "1.5.1" => %{"linux-x86_64" => "ddd"},
      "1.5.2-rc-0" => %{"linux-x86_64" => "fff"},
      "1.6.0" => %{"linux-x86_64" => "eee"}
    }

    test "picks the latest stable version" do
      assert {:ok, "1.5.1"} = Version.resolve_version(@versions_map)
    end

    test "returns :no_compatible_version when map has no matching entries" do
      assert {:error, :no_compatible_version} =
               Version.resolve_version(%{"1.4.0" => %{}, "1.6.0" => %{}})
    end

    test "returns :no_compatible_version when map is empty" do
      assert {:error, :no_compatible_version} = Version.resolve_version(%{})
    end

    test "ignores versions that do not parse as semver" do
      map = Map.put(@versions_map, "not-a-version", %{})
      assert {:ok, "1.5.1"} = Version.resolve_version(map)
    end
  end

  # ---------------------------------------------------------------------------
  # read_lock/1 and write_lock/2
  # ---------------------------------------------------------------------------

  describe "read_lock/1 and write_lock/2" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "safe_version_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, project_dir: tmp}
    end

    test "round-trips a version string through the lock file", %{project_dir: dir} do
      assert :ok = Version.write_lock(dir, "1.5.0-rc-0")
      assert {:ok, "1.5.0-rc-0"} = Version.read_lock(dir)
    end

    test "returns :not_found when lock file is absent", %{project_dir: dir} do
      assert {:error, :not_found} = Version.read_lock(dir)
    end

    test "lock file is written in JSON format", %{project_dir: dir} do
      Version.write_lock(dir, "1.5.1")
      contents = File.read!(Path.join(dir, "safe.lock"))
      decoded = Jason.decode!(contents)
      assert decoded["version"] == "1.5.1"
    end

    test "read_lock returns lock_parse_error for non-JSON content", %{project_dir: dir} do
      File.write!(Path.join(dir, "safe.lock"), "{safe_version, \"1.5.1\"}.")
      assert {:error, {:lock_parse_error, _}} = Version.read_lock(dir)
    end

    test "read_lock returns lock_read_error for unreadable path", %{project_dir: dir} do
      lock_dir = Path.join(dir, "safe.lock")
      File.mkdir_p!(lock_dir)
      assert {:error, {:lock_read_error, _}} = Version.read_lock(dir)
    end

    test "write_lock returns lock_write_error when path is a directory", %{project_dir: dir} do
      lock_dir = Path.join(dir, "safe.lock")
      File.mkdir_p!(lock_dir)
      assert {:error, {:lock_write_error, _}} = Version.write_lock(dir, "1.5.1")
    end
  end
end

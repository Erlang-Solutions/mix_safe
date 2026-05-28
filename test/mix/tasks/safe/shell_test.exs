defmodule Safe.ShellTest do
  use ExUnit.Case, async: true

  alias Safe.Shell

  # ---------------------------------------------------------------------------
  # Setup: create a stub SAFE binary in a tmp project dir
  # ---------------------------------------------------------------------------

  setup do
    tmp = Path.join(System.tmp_dir!(), "safe_shell_test_#{:rand.uniform(999_999)}")
    build_dir = Path.join(tmp, "_build/safe")
    File.mkdir_p!(build_dir)

    stub_path = Path.join(build_dir, "safe")
    File.write!(stub_path, "#!/bin/sh\nexit 0\n")
    File.chmod!(stub_path, 0o755)

    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, project_dir: tmp, build_dir: build_dir}
  end

  # ---------------------------------------------------------------------------
  # run_safe/3 with {:config_json, json}
  # ---------------------------------------------------------------------------

  describe "run_safe/3 with {:config_json, json}" do
    test "returns :ok when the binary exits 0", %{project_dir: dir} do
      assert :ok = Shell.run_safe("fingerprint", dir, {:config_json, "{}"})
    end

    test "returns {:error, {:fingerprint, 2}} when binary exits 2", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 2\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:fingerprint, 2}} =
               Shell.run_safe("fingerprint", dir, {:config_json, "{}"})
    end

    test "returns {:error, {:analyse, 1}} when binary exits 1", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 1\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:analyse, 1}} = Shell.run_safe("analyse", dir, {:config_json, "{}"})
    end

    test "strips newlines from config JSON before passing to binary", %{project_dir: dir} do
      json_with_newlines = "{\n  \"key\": \"value\"\n}"
      assert :ok = Shell.run_safe("fingerprint", dir, {:config_json, json_with_newlines})
    end
  end

  # ---------------------------------------------------------------------------
  # run_safe_sca/2
  # ---------------------------------------------------------------------------

  describe "run_safe_sca/2" do
    test "returns :ok when binary exits 0", %{project_dir: dir} do
      assert :ok = Shell.run_safe_sca(dir, [])
    end

    test "returns {:error, {:sca, 2}} when binary exits 2", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 2\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:sca, 2}} = Shell.run_safe_sca(dir, [])
    end

    test "returns {:error, {:sca, 3}} when binary exits 3", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 3\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:sca, 3}} = Shell.run_safe_sca(dir, [])
    end

    test "returns {:error, {:sca, 1}} when binary exits 1", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 1\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:sca, 1}} = Shell.run_safe_sca(dir, [])
    end

    test "runs binary with cd set to project_dir", %{project_dir: dir, build_dir: build_dir} do
      pwd_file = Path.join(dir, "pwd_output.txt")

      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\npwd > \"#{pwd_file}\"\nexit 0\n")
      File.chmod!(stub, 0o755)

      assert :ok = Shell.run_safe_sca(dir, [])
      assert {:ok, captured_dir} = File.read(pwd_file)
      {real_dir, 0} = System.cmd("realpath", [dir])
      assert String.trim(captured_dir) == String.trim(real_dir)
    end

    test "forwards extra args verbatim to binary", %{project_dir: dir, build_dir: build_dir} do
      args_file = Path.join(dir, "args_output.txt")

      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\necho \"$@\" > \"#{args_file}\"\nexit 0\n")
      File.chmod!(stub, 0o755)

      assert :ok = Shell.run_safe_sca(dir, ["--lock-file", "mix.lock", "--warnings-as-errors"])
      assert {:ok, captured_args} = File.read(args_file)
      assert String.trim(captured_args) == "sca --lock-file mix.lock --warnings-as-errors"
    end
  end

  # ---------------------------------------------------------------------------
  # run_safe/3 with {:config_path, path}
  # ---------------------------------------------------------------------------

  describe "run_safe/3 with {:config_path, path}" do
    test "returns :ok when the binary exits 0", %{project_dir: dir} do
      assert :ok = Shell.run_safe("fingerprint", dir, {:config_path, "/some/config.json"})
    end

    test "returns {:error, {:analyse, 1}} when binary exits 1", %{
      project_dir: dir,
      build_dir: build_dir
    } do
      stub = Path.join(build_dir, "safe")
      File.write!(stub, "#!/bin/sh\nexit 1\n")
      File.chmod!(stub, 0o755)

      assert {:error, {:analyse, 1}} =
               Shell.run_safe("analyse", dir, {:config_path, "/some/config.json"})
    end
  end
end

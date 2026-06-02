defmodule Safe.ShellTest do
  use ExUnit.Case, async: false

  import Mock

  alias Safe.Shell

  defp stub_exit_code(exit_code) do
    [cmd: fn _exe, _args, _opts -> {"", exit_code} end]
  end

  # ---------------------------------------------------------------------------
  # run_safe/3 with {:config_json, json}
  # ---------------------------------------------------------------------------

  describe "run_safe/3 with {:config_json, json}" do
    test "returns :ok when the binary exits 0" do
      with_mock Safe.Utilities.System, stub_exit_code(0) do
        assert :ok = Shell.run_safe("fingerprint", "/fake/dir", {:config_json, "{}"})
      end
    end

    test "returns {:error, {\"fingerprint\", 2}} when binary exits 2" do
      with_mock Safe.Utilities.System, stub_exit_code(2) do
        assert {:error, {"fingerprint", 2}} =
                 Shell.run_safe("fingerprint", "/fake/dir", {:config_json, "{}"})
      end
    end

    test "returns {:error, {\"analyse\", 1}} when binary exits 1" do
      with_mock Safe.Utilities.System, stub_exit_code(1) do
        assert {:error, {"analyse", 1}} =
                 Shell.run_safe("analyse", "/fake/dir", {:config_json, "{}"})
      end
    end

    test "strips newlines from config JSON before passing to binary" do
      with_mock Safe.Utilities.System,
        cmd: fn _exe, args, _opts ->
          refute Enum.any?(args, &String.contains?(&1, "\n"))
          {"", 0}
        end do
        assert :ok =
                 Shell.run_safe(
                   "fingerprint",
                   "/fake/dir",
                   {:config_json, ~s({\n  "key": "value"\n})}
                 )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # run_safe_sca/2
  # ---------------------------------------------------------------------------

  describe "run_safe_sca/2" do
    test "returns :ok when binary exits 0" do
      with_mock Safe.Utilities.System, stub_exit_code(0) do
        assert :ok = Shell.run_safe_sca("/fake/dir", [])
      end
    end

    test "returns {:error, {:sca, 2}} when binary exits 2" do
      with_mock Safe.Utilities.System, stub_exit_code(2) do
        assert {:error, {:sca, 2}} = Shell.run_safe_sca("/fake/dir", [])
      end
    end

    test "returns {:error, {:sca, 3}} when binary exits 3" do
      with_mock Safe.Utilities.System, stub_exit_code(3) do
        assert {:error, {:sca, 3}} = Shell.run_safe_sca("/fake/dir", [])
      end
    end

    test "returns {:error, {:sca, 1}} when binary exits 1" do
      with_mock Safe.Utilities.System, stub_exit_code(1) do
        assert {:error, {:sca, 1}} = Shell.run_safe_sca("/fake/dir", [])
      end
    end

    test "runs binary with cd set to project_dir" do
      with_mock Safe.Utilities.System,
        cmd: fn _exe, _args, opts ->
          assert opts[:cd] == "/fake/dir"
          {"", 0}
        end do
        assert :ok = Shell.run_safe_sca("/fake/dir", [])
      end
    end

    test "forwards extra args verbatim to binary" do
      with_mock Safe.Utilities.System,
        cmd: fn _exe, args, _opts ->
          assert args == ["sca", "--lock-file", "mix.lock", "--warnings-as-errors"]
          {"", 0}
        end do
        assert :ok =
                 Shell.run_safe_sca("/fake/dir", [
                   "--lock-file",
                   "mix.lock",
                   "--warnings-as-errors"
                 ])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # run_safe/3 with {:config_path, path}
  # ---------------------------------------------------------------------------

  describe "run_safe/3 with {:config_path, path}" do
    test "returns :ok when the binary exits 0" do
      with_mock Safe.Utilities.System, stub_exit_code(0) do
        assert :ok =
                 Shell.run_safe("fingerprint", "/fake/dir", {:config_path, "/some/config.json"})
      end
    end

    test "returns {:error, {\"analyse\", 1}} when binary exits 1" do
      with_mock Safe.Utilities.System, stub_exit_code(1) do
        assert {:error, {"analyse", 1}} =
                 Shell.run_safe("analyse", "/fake/dir", {:config_path, "/some/config.json"})
      end
    end
  end
end

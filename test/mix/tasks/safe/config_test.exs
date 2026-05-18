defmodule Safe.ConfigTest do
  use ExUnit.Case, async: true

  alias Safe.Config

  # ---------------------------------------------------------------------------
  # config_path/1
  # ---------------------------------------------------------------------------

  describe "config_path/1" do
    test "returns .safe/config.json under the project dir" do
      assert Config.config_path("/my/project") == "/my/project/.safe/config.json"
    end
  end

  # ---------------------------------------------------------------------------
  # longest_common_prefix/1
  # ---------------------------------------------------------------------------

  describe "longest_common_prefix/1" do
    test "single path returns the path unchanged" do
      assert Config.longest_common_prefix(["_build/dev/lib/my_app/ebin"]) ==
               "_build/dev/lib/my_app/ebin"
    end

    test "two paths with a common prefix" do
      paths = ["_build/dev/lib/app_a/ebin", "_build/dev/lib/app_b/ebin"]
      assert Config.longest_common_prefix(paths) == "_build/dev/lib"
    end

    test "paths with no common segments return empty string" do
      assert Config.longest_common_prefix(["a/b/c", "x/y/z"]) == ""
    end

    test "identical paths return the full path" do
      path = "_build/dev/lib/my_app/ebin"
      assert Config.longest_common_prefix([path, path]) == path
    end

    test "empty list returns empty string" do
      assert Config.longest_common_prefix([]) == ""
    end

    test "three paths with a common prefix" do
      paths = [
        "_build/dev/lib/app_a/ebin",
        "_build/dev/lib/app_b/ebin",
        "_build/dev/lib/app_c/ebin"
      ]

      assert Config.longest_common_prefix(paths) == "_build/dev/lib"
    end
  end

  # ---------------------------------------------------------------------------
  # write_config/2 and read_config/1
  # ---------------------------------------------------------------------------

  describe "write_config/2 and read_config/1" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "safe_config_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      {:ok, project_dir: tmp}
    end

    test "round-trips JSON through write/read", %{project_dir: dir} do
      json = ~s({"hello": "world"})
      assert :ok = Config.write_config(dir, json)
      assert {:ok, ^json} = Config.read_config(dir)
    end

    test "creates the .safe directory if it does not exist", %{project_dir: dir} do
      refute File.exists?(Path.join(dir, ".safe"))
      Config.write_config(dir, "{}")
      assert File.exists?(Path.join(dir, ".safe/config.json"))
    end

    test "read_config returns error tuple for missing file", %{project_dir: dir} do
      assert {:error, {:config_read_error, :enoent}} = Config.read_config(dir)
    end
  end

  # ---------------------------------------------------------------------------
  # make_config/1 — relies on current Mix project (mix_safe itself)
  # ---------------------------------------------------------------------------

  describe "make_config/1" do
    test "returns valid JSON with expected top-level keys" do
      project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      assert {:ok, json} = Config.make_config(project_dir)
      decoded = Jason.decode!(json)

      assert Map.has_key?(decoded, "output")
      assert Map.has_key?(decoded, "version")
      assert Map.has_key?(decoded, "project")
      assert decoded["version"] == "1.1"
    end

    test "project section contains name, type, apps, and paths" do
      project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      {:ok, json} = Config.make_config(project_dir)
      project = Jason.decode!(json)["project"]

      assert is_binary(project["name"])
      assert project["type"] == "beam"
      assert is_list(project["apps"])
      assert length(project["apps"]) >= 1
      assert is_list(project["paths"])
    end

    test "each app entry has name, app_file, and additional_includes" do
      project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      {:ok, json} = Config.make_config(project_dir)
      [app | _] = Jason.decode!(json)["project"]["apps"]

      assert is_binary(app["name"])
      assert is_binary(app["app_file"])
      assert is_list(app["additional_includes"])
    end

    test "app_file points to the compiled .app file" do
      project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      {:ok, json} = Config.make_config(project_dir)
      [app | _] = Jason.decode!(json)["project"]["apps"]

      assert String.ends_with?(app["app_file"], ".app")
      assert app["app_file"] =~ "_build/"
      assert app["app_file"] =~ "/ebin/"
    end

    test "app_file is a relative path (not absolute)" do
      project_dir = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      {:ok, json} = Config.make_config(project_dir)
      [app | _] = Jason.decode!(json)["project"]["apps"]

      refute String.starts_with?(app["app_file"], "/")
    end
  end

  # ---------------------------------------------------------------------------
  # make_config/1 — umbrella project
  # ---------------------------------------------------------------------------

  describe "make_config/1 (umbrella)" do
    test "lists all umbrella child apps" do
      umbrella_path = Path.expand("fixtures/umbrella")
      apps = [%{name: :foo}, %{name: :bar}]

      {:ok, json} = Config.build_config(umbrella_path, :umbrella, apps)
      decoded = Jason.decode!(json)
      app_entries = decoded["project"]["apps"]
      app_names = Enum.map(app_entries, & &1["name"])

      assert length(app_entries) > 1
      assert "foo" in app_names
      assert "bar" in app_names
    end
  end
end

defmodule Safe.IOTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Safe.IO, as: SafeIO

  # ---------------------------------------------------------------------------
  # bool_prompt/1
  # ---------------------------------------------------------------------------

  describe "bool_prompt/1" do
    test "returns true for 'y' input" do
      parent = self()

      capture_io("y\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, true}
    end

    test "returns true for 'yes' input" do
      parent = self()

      capture_io("yes\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, true}
    end

    test "returns true for uppercase 'Y' input" do
      parent = self()

      capture_io("Y\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, true}
    end

    test "returns true for empty input (Enter = yes)" do
      parent = self()

      capture_io("\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, true}
    end

    test "returns false for 'n' input" do
      parent = self()

      capture_io("n\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, false}
    end

    test "returns false for arbitrary non-yes input" do
      parent = self()

      capture_io("maybe\n", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, false}
    end

    test "prompt text appears in output" do
      output =
        capture_io("n\n", fn ->
          SafeIO.bool_prompt("Continue?")
        end)

      assert output =~ "Continue?"
    end

    test "prompt includes [Y/n] hint" do
      output =
        capture_io("n\n", fn ->
          SafeIO.bool_prompt("Go ahead?")
        end)

      assert output =~ "[Y/n]"
    end

    test "returns false on EOF (empty input stream)" do
      parent = self()

      capture_io("", fn ->
        send(parent, {:result, SafeIO.bool_prompt("Proceed?")})
      end)

      assert_receive {:result, false}
    end
  end

  # ---------------------------------------------------------------------------
  # print_status/1
  # ---------------------------------------------------------------------------

  describe "print_status/1" do
    test "prints the message" do
      output = capture_io(fn -> SafeIO.print_status("all good") end)
      assert output =~ "all good"
    end

    test "wraps output in bold green ANSI codes" do
      output = capture_io(fn -> SafeIO.print_status("msg") end)
      assert output =~ "\e[1;32m"
      assert output =~ "\e[0m"
    end
  end

  # ---------------------------------------------------------------------------
  # print_error/1
  # ---------------------------------------------------------------------------

  describe "print_error/1" do
    test "prints the message" do
      output = capture_io(fn -> SafeIO.print_error("something failed") end)
      assert output =~ "something failed"
    end

    test "wraps output in bold red ANSI codes" do
      output = capture_io(fn -> SafeIO.print_error("oops") end)
      assert output =~ "\e[1;31m"
      assert output =~ "\e[0m"
    end
  end

  # ---------------------------------------------------------------------------
  # print_info/1
  # ---------------------------------------------------------------------------

  describe "print_info/1" do
    test "prints the message without colour codes" do
      output = capture_io(fn -> SafeIO.print_info("plain info") end)
      assert output =~ "plain info"
      refute output =~ "\e["
    end
  end
end

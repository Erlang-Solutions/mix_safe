defmodule Safe.IO do
  @moduledoc """
  Terminal output helpers and interactive prompts for the SAFE Mix task.

  - Status messages in bold green
  - Error messages in bold red
  - Interactive prompts in blue
  """

  @blue "\e[34m"
  @bold_green "\e[1;32m"
  @bold_red "\e[1;31m"
  @reset "\e[0m"

  @doc """
  Prints an interactive yes/no prompt and returns true if the user answers
  "y", "yes", or presses Enter (case-insensitive). Returns false for "n",
  "no", and other non-affirmative input.
  """
  def bool_prompt(message) do
    IO.write("#{@blue}#{message} [Y/n]: #{@reset}")

    case IO.gets("") do
      :eof ->
        false

      {:error, _} ->
        false

      response ->
        response |> String.trim() |> String.downcase() |> then(&(&1 in ["", "y", "yes"]))
    end
  end

  @doc "Prints a bold green status line (e.g. '* running SAFE fingerprint')."
  def print_status(msg) do
    IO.puts("#{@bold_green}#{msg}#{@reset}")
  end

  @doc "Prints a bold red error line."
  def print_error(msg) do
    IO.puts("#{@bold_red}#{msg}#{@reset}")
  end

  @doc "Prints a plain informational line (no colour)."
  def print_info(msg) do
    IO.puts(msg)
  end
end

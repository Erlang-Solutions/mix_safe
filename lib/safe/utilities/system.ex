defmodule Safe.Utilities.System do
  # Extracted so tests can mock this call.
  def cmd(executable, args, opts), do: System.cmd(executable, args, opts)
end

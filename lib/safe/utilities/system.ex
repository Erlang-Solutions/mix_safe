defmodule Safe.Utilities.System do
  # Extracted so tests can mock this call.
  # safe-ignore System.cmd/3
  def cmd(executable, args, opts), do: System.cmd(executable, args, opts)
end

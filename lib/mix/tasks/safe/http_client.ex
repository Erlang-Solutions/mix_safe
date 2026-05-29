defmodule Safe.HttpClient do
  @moduledoc false
  @callback get(url :: String.t()) :: {:ok, binary()} | {:error, term()}
end

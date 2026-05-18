defmodule Safe.HttpClient do
  @callback get(url :: String.t()) :: {:ok, binary()} | {:error, term()}
end

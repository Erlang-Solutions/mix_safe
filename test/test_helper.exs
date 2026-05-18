defmodule Safe.HttpClient.Stub do
  @behaviour Safe.HttpClient

  @impl true
  def get(url) do
    case Process.get(:http_stub) do
      nil -> raise "No HTTP stub set for #{url}"
      fun -> fun.(url)
    end
  end

  def set(fun), do: Process.put(:http_stub, fun)
end

Application.put_env(:mix_safe, :http_client, Safe.HttpClient.Stub)
Logger.configure(level: :warning)
ExUnit.start()
ExUnit.configure(exclude: [:integration])

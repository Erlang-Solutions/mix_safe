defmodule SingleApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :single_app,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:mix_safe, path: "../.."}
    ]
  end
end

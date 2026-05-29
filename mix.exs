defmodule MixSafe.MixProject do
  use Mix.Project

  def project do
    [
      app: :mix_safe,
      version: "1.0.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: "SAFE security vulnerability scanner for Elixir/Mix projects",
      source_url: "https://github.com/erlang-solutions/safe-mix-plugin",
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [
        ignore_modules: [
          Mix.Tasks.Safe
        ],
        summary: [threshold: 0]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp package do
    [
      organization: "esl_security",
      maintainers: ["Erlang Solutions"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/Erlang-Solutions/mix_safe"},
      source_url: "https://github.com/Erlang-Solutions/mix_safe"
    ]
  end

  defp deps do
    [
      {:hackney, "~> 1.20"},
      {:certifi, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3", only: :test},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp dialyzer do
    [plt_add_apps: [:mix], plt_local_path: "priv/plts"]
  end
end

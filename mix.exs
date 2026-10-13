defmodule Inex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jaimeiniesta/inex"

  def project do
    [
      app: :inex,
      version: @version,
      elixir: "~> 1.18",
      name: "Inex",
      source_url: @source_url,
      homepage_url: @source_url,
      description:
        "An Elixir client for the INE (Instituto Nacional de Estadística, Spain) JSON API, with Explorer integration",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      test_coverage: [
        tool: ExCoveralls
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      name: "inex",
      files: ~w(lib livebooks mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "INE API JSON" => "https://www.ine.es/dyngs/DAB/index.htm?cid=1099"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md" | Path.wildcard("livebooks/*.livemd")],
      groups_for_extras: [
        General: ["README.md", "CHANGELOG.md"],
        Livebooks: Path.wildcard("livebooks/*.livemd")
      ],
      groups_for_modules: [
        "Data API Modules": [
          Inex.Classifications,
          Inex.Operations,
          Inex.Periodicities,
          Inex.Publications,
          Inex.Scales,
          Inex.Series,
          Inex.Tables,
          Inex.Units,
          Inex.Variables
        ],
        "Explorer Integration": [
          Inex.DataFrame
        ],
        "Supporting Modules": [
          Inex.Client,
          Inex.Error,
          Inex.Filters,
          Inex.Telemetry,
          Inex.Telemetry.Logger
        ]
      ]
    ]
  end

  defp deps do
    [
      # Required dependencies
      {:req, "~> 0.5"},
      {:telemetry, "~> 1.3"},
      {:nimble_options, "~> 1.0"},
      {:explorer, "~> 0.12"},

      # Development deps
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},

      # Test deps
      {:plug, "~> 1.16", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end

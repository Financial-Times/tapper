defmodule Tapper.Mixfile do
  use Mix.Project

  def project do
    [app: :tapper,
     version: "0.6.0",
     elixir: "~> 1.6",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: [bench: "run benchmarking/tapper_bench.exs"],
     name: "Tapper",
     source_url: "https://github.com/Financial-Times/tapper",
     description: description(),
     package: package(),
     docs: docs(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {Tapper.Application, []}]
  end

  def package do
    [
      maintainers: ["Ellis Pritchard"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Financial-Times/tapper"} ]
  end

  defp description do
    """
    Implements an interface for recording traces and sending them to a Zipkin server.
    """
  end

  def docs do
    [main: "readme",
     extras: ["README.md", "benchmarking/BENCHMARKS.md"]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:jason, "~> 1.1"},
      {:httpoison, "~> 0.12 or ~> 1.0"},
      {:deferred_config, "~> 0.1"},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 0.1", only: :bench},
      {:mix_test_watch, "~> 0.3", only: :dev, runtime: false},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev]},
      {:inch_ex, ">= 0.0.0", only: :docs, optional: true}
    ]
  end
end

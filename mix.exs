defmodule WeatherGen.MixProject do
  use Mix.Project

  def project do
    [
      app: :weather_gen,
      version: "1.0.8",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :req]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4.0"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9"},
      {:castore, "~> 1.0"}
    ]
  end
end

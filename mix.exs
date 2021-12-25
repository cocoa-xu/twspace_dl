defmodule TwspaceDl.MixProject do
  use Mix.Project

  def project do
    [
      app: :twspace_dl,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      applications: [:httpotion],
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:httpotion, "~> 3.1.0"},
      {:jason, "~> 1.2"}
    ]
  end
end

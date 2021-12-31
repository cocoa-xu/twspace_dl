defmodule TwspaceDl.MixProject do
  use Mix.Project

  def project do
    [
      app: :twspace_dl,
      version: "0.1.2",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/cocoa-xu/twspace_dl"
    ]
  end

  def application do
    [
      applications: [:ibrowse, :httpotion, :jason],
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ibrowse, github: "cmullaparthi/ibrowse", tag: "v4.4.2"},
      {:httpotion, "~> 3.1.0"},
      {:jason, "~> 1.2"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "Twitter Space audio downloader"
  end

  defp elixirc_paths(_), do: ~w(lib)

  defp package() do
    [
      name: "twspace_dl",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/cocoa-xu/twspace_dl"}
    ]
  end
end

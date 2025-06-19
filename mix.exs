defmodule Xbase.MixProject do
  use Mix.Project

  def project do
    [
      app: :xbase,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Docs
      name: "Xbase",
      description: "A comprehensive Elixir library for reading, writing, and manipulating dBase database files",
      source_url: "https://github.com/your-org/xbase",
      homepage_url: "https://github.com/your-org/xbase",
      docs: [
        main: "Xbase",
        extras: [
          "README.md",
          "docs/guides/getting_started.md",
          "docs/guides/memo_fields.md",
          "docs/guides/indexes.md",
          "docs/guides/streaming.md",
          "docs/guides/performance.md"
        ],
        groups_for_extras: [
          "Guides": ~r/docs\/guides\/.*/
        ],
        groups_for_modules: [
          "Core": [Xbase.Parser, Xbase.Types],
          "Memo Support": [Xbase.MemoHandler, Xbase.DbtParser, Xbase.DbtWriter], 
          "Field Handling": [Xbase.FieldParser, Xbase.FieldEncoder],
          "Index Support": [Xbase.CdxParser]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end

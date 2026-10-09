# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ash_versioned,
      description: "Versioned resources for Ash. Implements SCD type 2 versioned-with-latest resources.",
      version: @version,
      elixir: "~> 1.18",
      aliases: aliases(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps(),
      docs: &docs/0,
      package: package(),
      test_coverage: test_coverage(),
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts/project",
        plt_core_path: "priv/plts/core"
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
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "test.create": :test,
        "test.migrate": :test,
        "test.rollback": :test,
        "test.reset": :test,
        "test.reset_hard": :test,
        "test.generate_migrations": :test,
        "test.check_migrations": :test
      ]
    ]
  end

  defp package do
    [
      maintainers: ["sFOX"],
      licenses: ["Apache-2.0"],
      files: ~w(lib .formatter.exs mix.exs licences/* *.md documentation),
      links: %{
        "GitHub" => "https://github.com/sfoxhq/ash_versioned",
        "Changelog" => "https://github.com/sfoxhq/ash_versioned/blob/main/CHANGELOG.md",
        "Issues" => "https://github.com/sfoxhq/ash_versioned/issues"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extra_section: "GUIDES",
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/getting-started-with-ash-versioned.md",
        "documentation/topics/basics.md",
        "documentation/topics/options.md",
        {"documentation/dsls/DSL-AshVersioned.Resource.md",
         search_data: Spark.Docs.search_data_for(AshVersioned.Resource)},
        {"documentation/dsls/DSL-AshVersioned.Relationships.md",
         search_data: Spark.Docs.search_data_for(AshVersioned.Relationships)},
        {"roadmap",
         %{
           title: "Roadmap",
           url: "https://github.com/sfoxhq/ash_versioned/blob/main/ROADMAP.md"
         }},
        "CONTRIBUTING.md": [filename: "CONTRIBUTING", title: "Contributing"],
        "CODE_OF_CONDUCT.md": [filename: "CODE_OF_CONDUCT", title: "Code of Conduct"],
        "CHANGELOG.md": [filename: "CHANGELOG", title: "CHANGELOG"],
        "LICENCE.md": [filename: "LICENCE", title: "Licence"],
        "licences/APACHE-2.0.txt": [filename: "APACHE-2.0", title: "Apache License, version 2.0"],
        "licences/dco.txt": [filename: "dco", title: "Developer Certificate of Origin"]
      ],
      canonical: "https://ash-versioned.hexdocs.pm",
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        Topics: ~r'documentation/topics',
        DSLs: ~r'documentation/dsls'
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.5"},
      {:ash_archival, "~> 2.0", optional: true},
      {:ash_postgres, "~> 2.0"},
      {:castore, "~> 1.0", optional: true},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:test]},
      {:ex_doc, "~> 0.29", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:picosat_elixir, "~> 0.2", only: [:dev, :test]},
      {:quokka, "~> 2.6", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sourceror, "~> 1.8", only: [:dev, :test]}
    ]
  end

  defp test_coverage do
    [
      tool: ExCoveralls
    ]
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      credo: "credo --strict",
      "spark.formatter": "spark.formatter --extensions AshVersioned.Resource,AshVersioned.Relationships",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshVersioned.Resource,AshVersioned.Relationships",
      "test.create": "ash.setup",
      "test.migrate": "ash.migrate",
      "test.rollback": "ash.rollback",
      "test.reset": "ash.reset",
      "test.reset_hard": [
        "ash_postgres.drop",
        fn _args ->
          File.rm_rf!("priv/repo")
          File.rm_rf!("priv/resource_snapshots")
        end,
        "test.generate_migrations",
        "test.create"
      ],
      "test.generate_migrations": "ash.codegen --dev",
      "test.check_migrations": "ash.codegen --check"
    ]
  end
end

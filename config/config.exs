# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

import Config

alias AshVersionedTest.Domain
alias AshVersionedTest.Repo

config :ash,
  default_string_length_count: :codepoints

config :spark, formatter: [remove_parens?: true]

if Mix.env() == :test do
  config :ash, disable_async?: true

  config :ash_versioned, Repo,
    username: System.get_env("POSTGRES_USER", "postgres"),
    # sobelow_skip ["Config.Secrets"]
    password: System.get_env("POSTGRES_PASSWORD", "postgres"),
    hostname: System.get_env("POSTGRES_HOST", "localhost"),
    port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
    database:
      System.get_env(
        "POSTGRES_TEST_DATABASE",
        "ash_versioned_test#{System.get_env("MIX_TEST_PARTITION")}"
      ),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :ash_versioned, :ash_domains, [Domain]
  config :ash_versioned, ecto_repos: [Repo]

  config :logger, level: :warning
end

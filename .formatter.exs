# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

spark_locals_without_parens = [
  action: 1,
  allow_nil?: 1,
  archive: 0,
  archive: 1,
  archive: 2,
  attribute: 1,
  attribute_type: 1,
  belongs_to_actor: 2,
  belongs_to_actor: 3,
  create_timestamp_attribute: 1,
  define_attribute?: 1,
  domain: 1,
  exclude_read_actions: 1,
  exclude_update_actions: 1,
  history_action: 1,
  identity: 0,
  identity: 1,
  identity: 2,
  latest: 0,
  latest: 1,
  latest: 2,
  name: 1,
  on_delete: 1,
  origin: 1,
  public?: 1,
  read_action: 1,
  reference_actor: 1,
  reference_actor: 2,
  source: 1,
  source_prefix: 1,
  transform: 1,
  type: 1,
  unarchive: 1,
  update_timestamp_attribute: 1,
  version: 0,
  version: 1,
  version: 2
]

[
  import_deps: [:ash, :ash_postgres],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter, Quokka],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]

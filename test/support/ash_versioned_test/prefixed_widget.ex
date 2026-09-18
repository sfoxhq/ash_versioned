# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.PrefixedWidget do
  @moduledoc """
  Resource testing `source_prefix`: `identity`/`latest`/`archive` pick up the
  section-level prefix on top of their (one custom, two default) names, while `version`
  declares its own `source` explicitly to prove an entity's own `source` wins over the
  prefix.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "prefixed_widgets"
    repo Repo
  end

  versioning do
    source_prefix "vo_"

    identity :mo_id
    version :mo_version, source: :explicit_version_source
    archive :archived
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:status]
    update :increment, accept: [:status]
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

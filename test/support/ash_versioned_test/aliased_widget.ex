# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.AliasedWidget do
  @moduledoc """
  Resource testing `identity :resource_id, origin: :accepted`. An externally supplied
  `resource_id` on create rather than self-generated. This borrows a shared `users.id` as
  the identity for a `customers`/`admins`-style resource.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "aliased_widgets"
    repo Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status]
    end

    update :increment do
      accept [:status]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  versioning do
    identity :resource_id, origin: :accepted
  end
end

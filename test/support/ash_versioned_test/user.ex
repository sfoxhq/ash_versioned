# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.User do
  @moduledoc """
  Non-versioned resource used as an actor destination in tests, alongside
  `AshVersionedTest.Owner` (versioned), and as the source of a `has_one_versioned` to
  `AshVersionedTest.Customer`, which borrows the user's `id` as its identity.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Relationships]

  alias AshVersionedTest.Customer
  alias AshVersionedTest.Repo

  postgres do
    table "users"
    repo Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
  end

  relationships do
    has_one_versioned :customer, Customer, destination_attribute: :resource_id
  end
end

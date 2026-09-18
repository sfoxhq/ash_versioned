# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.CatalogItem do
  @moduledoc """
  Resource testing a user's own business unique key on a versioned resource: `unique_sku`,
  partial-on-latest, the same technique AshVersioned uses for its own identity.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  import Ash.Expr

  alias AshVersionedTest.Repo

  postgres do
    table "catalog_items"
    repo Repo
  end

  versioning do
  end

  actions do
    defaults [:read]

    create :create do
      accept [:sku]
    end

    update :increment do
      accept [:sku]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :sku, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_sku, [:sku], where: expr(latest_version == true)
  end
end

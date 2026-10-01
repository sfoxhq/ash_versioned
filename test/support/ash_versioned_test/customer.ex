# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Customer do
  @moduledoc """
  Resource testing a "borrowed identity" pattern: `AshVersionedTest.User` is a plain,
  non-versioned resource. `Customer` is a separate, versioned resource holding business
  data about that same person, borrowing the `User`'s own `:id` as its `resource_id`
  via `identity :resource_id, origin: :accepted` rather than generating a unique identity
  of its own.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "customers"
    repo Repo
  end

  versioning do
    identity :resource_id, origin: :accepted
  end

  actions do
    defaults [:read]

    create :create do
      accept [:resource_id, :plan]
    end

    update :increment do
      accept [:plan]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :plan, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

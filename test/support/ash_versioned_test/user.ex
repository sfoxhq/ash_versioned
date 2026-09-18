# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.User do
  @moduledoc """
  Non-versioned resource used as an actor destination in tests, alongside
  `AshVersionedTest.Owner` (versioned).
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer

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
end

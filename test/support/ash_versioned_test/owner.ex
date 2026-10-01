# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Owner do
  @moduledoc "Test versioned resource used as a `belongs_to_actor` destination in tests."

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "owners"
    repo Repo
  end

  versioning do
    archive do
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end

    update :increment do
      accept [:name]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

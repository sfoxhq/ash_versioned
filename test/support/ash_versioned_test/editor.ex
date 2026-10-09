# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Editor do
  @moduledoc """
  Versioned resource with a self-referential `belongs_to_actor`, which must be resolved
  without introspecting the resource while it is being compiled.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "editors"
    repo Repo
  end

  versioning do
    belongs_to_actor :edited_by, __MODULE__
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

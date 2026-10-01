# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.TransformedActorWidget do
  @moduledoc """
  Resource testing `reference_actor`'s `transform` option against
  `AshVersionedTest.CompositeKeyActor`.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "transformed_actor_widgets"
    repo Repo
  end

  versioning do
    reference_actor :handled_by,
      transform: fn actor -> {:ok, "#{actor.tenant}:#{actor.ref}"} end
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
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Widget do
  @moduledoc """
  Resource for validating `AshVersioned` against real Postgres with polymorphic actors.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  import Ash.Expr

  alias AshVersionedTest.Owner
  alias AshVersionedTest.Repo
  alias AshVersionedTest.User

  postgres do
    table "widgets"
    repo Repo
  end

  versioning do
    exclude_read_actions [:audit_trail]
    exclude_update_actions [:rename_in_place]

    archive do
      exclude_read_actions [:peek_even_archived]
    end

    reference_actor :created_by
    belongs_to_actor :owned_by, Owner
    belongs_to_actor :reviewed_by, User
  end

  actions do
    defaults [:read]

    read :audit_trail do
      primary? false
    end

    # Hand-written alternative to the generated `get_with_archived`, exercising
    # `archive.exclude_read_actions` instead of `archive.read_action`.
    read :peek_even_archived do
      argument :resource_id, :uuid, allow_nil?: false
      get? true
      filter expr(resource_id == ^arg(:resource_id))
    end

    create :create do
      accept [:status]
    end

    create :import do
      accept [:status]
    end

    update :increment do
      accept [:status]
    end

    update :rename_in_place do
      accept [:status]
    end

    # Hand-written on purpose, to test that a user-defined :unarchive action wins over
    # the generated default of the same name.
    update :unarchive do
      accept []
      change set_attribute(:archived, false)
    end

    # An ordinary, user-authored destroy action gets transformed into a soft archive
    # rather than compiling as a real, irreversible delete.
    destroy :nuke do
      accept []
    end
  end

  attributes do
    integer_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

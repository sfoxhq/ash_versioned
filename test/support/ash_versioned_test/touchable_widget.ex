# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.TouchableWidget do
  @moduledoc """
  Resource testing the "touch" pattern documented in `actor-attribution.md`.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "touchable_widgets"
    repo Repo
  end

  versioning do
    reference_actor :touched_by
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status]
    end

    update :increment do
      accept [:status]
    end

    update :touch do
      accept []

      change fn changeset, _ ->
        Ash.Changeset.force_change_attribute(changeset, :touch_nonce, Ash.UUID.generate())
      end
    end
  end

  attributes do
    integer_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false
    attribute :touch_nonce, :uuid, public?: false, writable?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

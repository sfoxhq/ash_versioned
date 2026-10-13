# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.GuardedWidget do
  @moduledoc """
  Resource testing that a versioned update or archive is authorized once, against the
  policies of the user's action, and never against the generated internal actions it
  runs through (which have no policies here, so would always be forbidden).
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "guarded_widgets"
    repo Repo
  end

  versioning do
    archive do
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:create, :increment]) do
      authorize_if always()
    end

    # Checks the stored record.
    policy action([:edit_open, :archive]) do
      authorize_if expr(status == "open")
    end

    # Checks the actor.
    policy action(:edit_as_editor) do
      authorize_if actor_attribute_equals(:role, "editor")
    end

    # Checks the change being made.
    policy action(:edit_unless_locking) do
      forbid_if changing_attributes(status: [to: "locked"])
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status]
    end

    update :increment do
      accept [:status]
    end

    update :edit_open do
      accept [:status]
    end

    update :edit_as_editor do
      accept [:status]
    end

    update :edit_unless_locking do
      accept [:status]
    end

    # Declared without a policy: never authorized.
    update :unpoliced do
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

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.FlakyWidget do
  @moduledoc """
  Resource testing that a failed reinsert rolls back the already-applied mark-stale flip
  within the same transaction, rather than leaving the old row permanently marked stale
  with no replacement ever inserted.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.RejectFlagged
  alias AshVersionedTest.Repo

  postgres do
    table "flaky_widgets"
    repo Repo
  end

  versioning do
  end

  validations do
    validate {RejectFlagged, []}, on: [:create], where: [action_is(:version_reinsert)]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status, :fail_reinsert]
    end

    update :increment do
      accept [:status, :fail_reinsert]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false
    attribute :fail_reinsert, :boolean, public?: true, allow_nil?: false, default: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

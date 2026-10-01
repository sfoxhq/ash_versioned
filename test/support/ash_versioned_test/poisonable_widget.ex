# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.PoisonableWidget do
  @moduledoc """
  Resource testing a real (non-staleness) failure during the atomic mark-stale flip is
  propagated as-is, not misreported as `StaleRecord`.

  `poison_flip` is not writable, so the test updates it directly with SQL.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "poisonable_widgets"
    repo Repo

    check_constraints do
      check_constraint :poison_flip, "poisoned_row",
        check: "NOT poison_flip OR latest_version",
        message: "poisoned row"
    end
  end

  versioning do
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
    attribute :poison_flip, :boolean, public?: false, writable?: false, default: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

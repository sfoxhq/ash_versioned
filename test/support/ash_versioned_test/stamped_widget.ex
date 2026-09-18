# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.StampedWidget do
  @moduledoc """
  Resource testing that a plain, resource-author-declared `created_at` attribute (not an
  `AshVersioned`-managed field) is stamped once on create and carried forward unchanged
  through every later version, without any extension-level configuration.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "stamped_widgets"
    repo Repo
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

    attribute :created_at, :utc_datetime_usec,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: &DateTime.utc_now/0

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

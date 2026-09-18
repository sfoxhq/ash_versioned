# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.PortedWidget do
  @moduledoc """
  Resource testing the "porting an existing schema" path: `mo_id`, `mo_version`, and
  `mo_is_latest` are pre-declared attributes under names and types a hand-rolled table
  might already have had (a plain `:uuid`, an `:integer`, and a `:boolean`, respectively,
  none of them matching AshVersioned's own default names or — for identity — its default
  type). `identity`, `version`, and `latest` all set `define_attribute? false` to adopt
  them as-is rather than generating anything.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Repo

  postgres do
    table "ported_widgets"
    repo Repo
  end

  versioning do
    identity :mo_id do
      define_attribute? false
    end

    version :mo_version do
      define_attribute? false
    end

    latest :mo_is_latest do
      define_attribute? false
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
  end

  attributes do
    integer_primary_key :id
    attribute :status, :string, public?: true, allow_nil?: false

    attribute :mo_id, :uuid,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: &Ash.UUID.generate/0

    attribute :mo_version, :integer,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: 0

    attribute :mo_is_latest, :boolean,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end

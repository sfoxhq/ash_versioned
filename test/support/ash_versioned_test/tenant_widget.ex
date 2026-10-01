# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.TenantWidget do
  @moduledoc """
  Resource testing that AshVersioned's identity uniqueness composes correctly with
  attribute multitenancy: the same `resource_id` value in two different tenants must be
  treated as two distinct logical objects. The tenant column is be folded into the partial
  unique index built for `unique_external_ref` (see the `identities` block below), not
  just the standard identity path.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  import Ash.Expr

  alias AshVersionedTest.Repo

  postgres do
    table "tenant_widgets"
    repo Repo
  end

  multitenancy do
    strategy :attribute
    attribute :tenant
  end

  versioning do
    identity :resource_id, origin: :accepted
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status, :resource_id, :external_ref]
    end

    update :increment do
      accept [:status, :external_ref]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :tenant, :string, allow_nil?: false, public?: true
    attribute :status, :string, public?: true, allow_nil?: false
    attribute :external_ref, :string, public?: true, allow_nil?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    # The business unique key on a versioned resource needs the same partial-on-latest
    # scoping AshVersioned applies to its own identity, or it wrongly spans every
    # historical row for the same logical object, not just the current one. AshVersioned
    # handles the required `postgres.identity_wheres_to_sql` entry.
    #
    # `all_tenants?: true` shows that flag composes correctly with our machinery too: this
    # key is unique *globally*, unlike resource_id which is tenant-scoped.
    identity :unique_external_ref, [:external_ref],
      where: expr(latest_version == true),
      all_tenants?: true
  end
end

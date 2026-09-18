# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.CompositeKeyActor do
  @moduledoc """
  Resource testing a non-versioned resource with a composite primary key, used as
  a `reference_actor` actor in tests, not supported by `AshVersioned.ReferenceActorValue`.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:tenant, :ref]
    end
  end

  attributes do
    attribute :tenant, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :ref, :string, primary_key?: true, allow_nil?: false, public?: true
  end
end

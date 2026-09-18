# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Domain do
  @moduledoc "Test domain for validating `AshVersioned`."

  use Ash.Domain, validate_config_inclusion?: false

  alias AshVersionedTest.AliasedWidget
  alias AshVersionedTest.CatalogItem
  alias AshVersionedTest.CompositeKeyActor
  alias AshVersionedTest.Customer
  alias AshVersionedTest.FlakyWidget
  alias AshVersionedTest.LinkedWidget
  alias AshVersionedTest.Owner
  alias AshVersionedTest.PoisonableWidget
  alias AshVersionedTest.PortedWidget
  alias AshVersionedTest.PreexistingPkWidget
  alias AshVersionedTest.PrefixedWidget
  alias AshVersionedTest.StampedWidget
  alias AshVersionedTest.TenantWidget
  alias AshVersionedTest.TouchableWidget
  alias AshVersionedTest.TransformedActorWidget
  alias AshVersionedTest.User
  alias AshVersionedTest.UuidPkWidget
  alias AshVersionedTest.Widget

  resources do
    resource TransformedActorWidget
    resource Widget
    resource Owner
    resource AliasedWidget
    resource UuidPkWidget
    resource PreexistingPkWidget
    resource User
    resource FlakyWidget
    resource TenantWidget
    resource CatalogItem
    resource Customer
    resource PortedWidget
    resource CompositeKeyActor
    resource LinkedWidget
    resource TouchableWidget
    resource PoisonableWidget
    resource PrefixedWidget
    resource StampedWidget
  end
end

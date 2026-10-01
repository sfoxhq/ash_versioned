# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.ExtensionTest do
  use AshVersioned.DataCase, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias Ash.Error.Changes.StaleRecord
  alias Ash.Error.Invalid
  alias Ash.Resource.Info
  alias AshVersioned.Resource.BelongsToActor
  alias AshVersioned.Resource.ReferenceActor
  alias AshVersionedTest.AliasedWidget
  alias AshVersionedTest.CatalogItem
  alias AshVersionedTest.CompositeKeyActor
  alias AshVersionedTest.Customer
  alias AshVersionedTest.FlakyWidget
  alias AshVersionedTest.LinkedWidget
  alias AshVersionedTest.Owner
  alias AshVersionedTest.PlainStructActor
  alias AshVersionedTest.PoisonableWidget
  alias AshVersionedTest.PortedWidget
  alias AshVersionedTest.PreexistingPkWidget
  alias AshVersionedTest.PrefixedWidget
  alias AshVersionedTest.ReferenceActorTransforms
  alias AshVersionedTest.Repo
  alias AshVersionedTest.StampedWidget
  alias AshVersionedTest.TenantWidget
  alias AshVersionedTest.TouchableWidget
  alias AshVersionedTest.TransformedActorWidget
  alias AshVersionedTest.User
  alias AshVersionedTest.UuidPkWidget
  alias AshVersionedTest.Widget

  require Ash.Query
  require Spark.Test

  test "create mints version 0, latest, with a fresh resource_id" do
    widget =
      Widget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    assert widget.version_number == 0
    assert widget.latest_version == true
    assert widget.status == "new"
    refute is_nil(widget.resource_id)
  end

  test "increment appends a new row, carries resource_id forward, bumps version" do
    widget =
      Widget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    incremented =
      widget
      |> Ash.Changeset.for_update(:increment, %{status: "active"})
      |> Ash.update!()

    assert incremented.id != widget.id
    assert incremented.resource_id == widget.resource_id
    assert incremented.version_number == widget.version_number + 1
    assert incremented.latest_version == true
    assert incremented.status == "active"

    stale_reloaded = Ash.get!(Widget, widget.id, action: :version_history)
    assert stale_reloaded.latest_version == false
  end

  test "a plain (non-actor) belongs_to's generated attribute survives reinsert" do
    owner =
      User
      |> Ash.Changeset.for_create(:create, %{name: "Casey"})
      |> Ash.create!()

    widget =
      LinkedWidget
      |> Ash.Changeset.for_create(:create, %{status: "new", owner_id: owner.id})
      |> Ash.create!()

    incremented =
      widget
      |> Ash.Changeset.for_update(:increment, %{status: "active"})
      |> Ash.update!()

    assert incremented.owner_id == owner.id
  end

  test "a create action forced into upsert?: true at the call site is rejected at runtime" do
    assert {:error, error} =
             Widget
             |> Ash.Changeset.for_create(:create, %{status: "new"}, upsert?: true)
             |> Ash.create()

    assert %Invalid{} = error
  end

  test "incrementing a stale (already-superseded) row fails with StaleRecord" do
    widget =
      Widget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    widget
    |> Ash.Changeset.for_update(:increment, %{status: "active"})
    |> Ash.update!()

    assert {:error, error} =
             widget
             |> Ash.Changeset.for_update(:increment, %{status: "should not apply"})
             |> Ash.update()

    assert %Invalid{errors: [%StaleRecord{}]} = error
  end

  test "a real failure during the mark-stale flip is never misreported as StaleRecord" do
    widget =
      PoisonableWidget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    Repo.query!("update poisonable_widgets set poison_flip = true where id = $1", [widget.id])

    assert {:error, error} =
             widget
             |> Ash.Changeset.for_update(:increment, %{status: "active"})
             |> Ash.update()

    refute match?(%Invalid{errors: [%StaleRecord{}]}, error)
    assert Exception.message(error) =~ "poisoned row"

    reloaded = Ash.get!(PoisonableWidget, widget.id)
    assert reloaded.latest_version == true
    assert reloaded.version_number == widget.version_number
    assert reloaded.status == "new"
  end

  test "a reinsert failure rolls back the mark-stale flip instead of leaving the old row stranded" do
    widget =
      FlakyWidget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    assert {:error, _error} =
             widget
             |> Ash.Changeset.for_update(:increment, %{status: "active", fail_reinsert: true})
             |> Ash.update()

    reloaded = Ash.get!(FlakyWidget, widget.id)
    assert reloaded.latest_version == true
    assert reloaded.version_number == widget.version_number
    assert reloaded.status == "new"
  end

  test "incrementing with no actual changes is a no-op returning the current row" do
    widget =
      Widget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    result =
      widget
      |> Ash.Changeset.for_update(:increment, %{status: "new"})
      |> Ash.update!()

    assert result.id == widget.id
    assert result.version_number == widget.version_number
  end

  test "a dedicated always-changing attribute defeats the no-op skip, forcing a real version update and restamp" do
    widget =
      TouchableWidget
      |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: "actor-a")
      |> Ash.create!(actor: "actor-a")

    touched =
      widget
      |> Ash.Changeset.for_update(:touch, %{}, actor: "actor-b")
      |> Ash.update!(actor: "actor-b")

    assert touched.id != widget.id
    assert touched.version_number == widget.version_number + 1
    assert touched.status == "new"
    assert touched.touched_by == "actor-b"
  end

  test "only the latest row is queryable via the current_resource_id identity's implied filter" do
    widget =
      Widget
      |> Ash.Changeset.for_create(:create, %{status: "new"})
      |> Ash.create!()

    incremented =
      widget
      |> Ash.Changeset.for_update(:increment, %{status: "active"})
      |> Ash.update!()

    latest =
      Widget
      |> Ash.Query.filter(resource_id == ^widget.resource_id and latest_version == true)
      |> Ash.read_one!()

    assert latest.id == incremented.id
  end

  describe "default latest scoping and history access" do
    test "a plain read only ever returns the latest, unarchived row for an identity" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      results =
        Widget
        |> Ash.Query.filter(resource_id == ^widget.resource_id)
        |> Ash.read!()

      assert [only] = results
      assert only.id == incremented.id
    end

    test "the history action returns every version, ignoring the default scoping" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      _incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      history =
        Widget
        |> Ash.Query.for_read(:version_history)
        |> Ash.Query.filter(resource_id == ^widget.resource_id)
        |> Ash.Query.sort(version_number: :asc)
        |> Ash.read!()

      assert Enum.map(history, & &1.version_number) == [0, 1]
      assert Enum.map(history, & &1.latest_version) == [false, true]
    end
  end

  describe "action classification: exclude_update_actions/exclude_read_actions and upsert rejection" do
    test "an update action not listed in exclude_update_actions is wired as mutating by default" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      assert incremented.id != widget.id
      assert incremented.resource_id == widget.resource_id
      assert incremented.version_number == widget.version_number + 1
    end

    test "an exclude_update_actions entry that doesn't correspond to a real update action fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.StaleExcludeActionWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              exclude_update_actions [:typo_action]
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.StaleExcludeActionWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "typo_action"))
    end

    test "an exclude_read_actions entry that doesn't correspond to a real read action fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.StaleExcludeReadActionWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              exclude_read_actions [:typo_action]
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.StaleExcludeReadActionWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "typo_action"))
    end

    test "an update action with its own manual fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.CustomManualWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]

              update :increment do
                accept [:status]
                manual fn changeset, _context -> {:ok, changeset.data} end
              end
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.CustomManualWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ ":increment"))
    end

    test "a create action with upsert?: true fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.UpsertingCreateWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]

              create :sneaky_upsert, accept: [:status], upsert?: true
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.UpsertingCreateWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "sneaky_upsert"))
    end

    test "a resource with no create action at all fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NoCreateActionWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.NoCreateActionWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "no `:create` action"))
    end

    test "an update action listed in exclude_update_actions behaves as an ordinary in-place update" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      renamed =
        widget
        |> Ash.Changeset.for_update(:rename_in_place, %{status: "renamed"})
        |> Ash.update!()

      assert renamed.id == widget.id
      assert renamed.version_number == widget.version_number
      assert renamed.status == "renamed"
    end

    test "a read action listed in exclude_read_actions sees stale and archived versions too" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      widget
      |> Ash.Changeset.for_update(:increment, %{status: "active"})
      |> Ash.update!()

      versions =
        Widget
        |> Ash.Query.for_read(:audit_trail)
        |> Ash.Query.filter(resource_id == ^widget.resource_id)
        |> Ash.Query.sort(version_number: :asc)
        |> Ash.read!()

      assert Enum.map(versions, & &1.version_number) == [0, 1]
      assert Enum.map(versions, & &1.latest_version) == [false, true]
    end

    test "a read action not listed in exclude_read_actions stays scoped to the latest version" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      widget
      |> Ash.Changeset.for_update(:increment, %{status: "active"})
      |> Ash.update!()

      assert [current] =
               Widget
               |> Ash.Query.filter(resource_id == ^widget.resource_id)
               |> Ash.read!()

      assert current.status == "active"
    end
  end

  describe "archive vs. purge" do
    test "a non-archivable resource that defines a destroy action fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.DeletableWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read, :destroy]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.DeletableWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "archive"))
    end

    test "AshArchival.Resource combined with AshVersioned.Resource fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.DoublyArchivedWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource, AshArchival.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
            end
          end
        end

      assert [{AshVersionedTest.DoublyArchivedWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "AshArchival.Resource"))
    end

    test "archiving appends a new, archived version rather than mutating in place" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      archived =
        widget
        |> Ash.Changeset.for_destroy(:nuke, %{})
        |> Ash.destroy!(return_destroyed?: true)

      assert archived.id != widget.id
      assert archived.resource_id == widget.resource_id
      assert archived.version_number == widget.version_number + 1
      assert archived.archived == true

      assert Widget
             |> Ash.Query.filter(resource_id == ^widget.resource_id)
             |> Ash.read!() == []

      history =
        Widget
        |> Ash.Query.for_read(:version_history)
        |> Ash.Query.filter(resource_id == ^widget.resource_id)
        |> Ash.read!()

      assert length(history) == 2
    end

    test "the generated get_with_archived action finds the latest version whether or not it's archived, but not a stale one" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      found =
        Widget
        |> Ash.Query.for_read(:get_with_archived, %{resource_id: widget.resource_id})
        |> Ash.read_one!()

      assert found.id == widget.id

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      found =
        Widget
        |> Ash.Query.for_read(:get_with_archived, %{resource_id: widget.resource_id})
        |> Ash.read_one!()

      assert found.id == incremented.id

      archived =
        incremented
        |> Ash.Changeset.for_destroy(:nuke, %{})
        |> Ash.destroy!(return_destroyed?: true)

      found =
        Widget
        |> Ash.Query.for_read(:get_with_archived, %{resource_id: widget.resource_id})
        |> Ash.read_one!()

      assert found.id == archived.id
      assert found.archived == true

      assert Widget
             |> Ash.Query.for_read(:get_with_archived, %{resource_id: widget.resource_id})
             |> Ash.Query.filter(id == ^widget.id)
             |> Ash.read!() == []
    end

    test "archive.exclude_read_actions grants the same archived-agnostic, latest-only scoping to a hand-written action" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      archived =
        widget
        |> Ash.Changeset.for_destroy(:nuke, %{})
        |> Ash.destroy!(return_destroyed?: true)

      found =
        Widget
        |> Ash.Query.for_read(:peek_even_archived, %{resource_id: widget.resource_id})
        |> Ash.read_one!()

      assert found.id == archived.id
      assert found.archived == true

      assert Widget
             |> Ash.Query.for_read(:peek_even_archived, %{resource_id: widget.resource_id})
             |> Ash.Query.filter(id == ^widget.id)
             |> Ash.read!() == []
    end

    test "unarchiving via a hand-written action overrides the generated default of the same name" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      widget
      |> Ash.Changeset.for_destroy(:nuke, %{})
      |> Ash.destroy!()

      archived_row =
        Widget
        |> Ash.Query.for_read(:version_history)
        |> Ash.Query.filter(resource_id == ^widget.resource_id and archived == true)
        |> Ash.read_one!()

      unarchived =
        archived_row
        |> Ash.Changeset.for_update(:unarchive, %{})
        |> Ash.update!()

      assert unarchived.id != archived_row.id
      assert unarchived.resource_id == widget.resource_id
      assert unarchived.version_number == archived_row.version_number + 1
      assert unarchived.archived == false

      assert [current] =
               Widget
               |> Ash.Query.filter(resource_id == ^widget.resource_id)
               |> Ash.read!()

      assert current.id == unarchived.id

      history =
        Widget
        |> Ash.Query.for_read(:version_history)
        |> Ash.Query.filter(resource_id == ^widget.resource_id)
        |> Ash.read!()

      assert length(history) == 3
    end

    test "mutating an archived row through an unrelated action doesn't silently unarchive it" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      widget
      |> Ash.Changeset.for_destroy(:nuke, %{})
      |> Ash.destroy!()

      archived_row =
        Widget
        |> Ash.Query.for_read(:version_history)
        |> Ash.Query.filter(resource_id == ^widget.resource_id and archived == true)
        |> Ash.read_one!()

      incremented =
        archived_row
        |> Ash.Changeset.for_update(:increment, %{status: "touched"})
        |> Ash.update!()

      assert incremented.archived == true
    end

    test "a resource with no hand-written destroy or unarchive action gets working defaults for both" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      archived =
        owner
        |> Ash.Changeset.for_destroy(:archive, %{})
        |> Ash.destroy!(return_destroyed?: true)

      assert archived.archived == true

      assert Owner
             |> Ash.Query.filter(resource_id == ^owner.resource_id)
             |> Ash.read!() == []

      unarchived =
        archived
        |> Ash.Changeset.for_update(:unarchive, %{})
        |> Ash.update!()

      assert unarchived.archived == false

      assert [current] =
               Owner
               |> Ash.Query.filter(resource_id == ^owner.resource_id)
               |> Ash.read!()

      assert current.id == unarchived.id
    end
  end

  describe "actor attribution and identity origin: :accepted" do
    test "raw and belongs_to actor fields are stamped from context.actor on create" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      assert widget.created_by == owner.resource_id
      assert widget.owned_by_id == owner.resource_id
      assert is_nil(widget.reviewed_by_id)

      loaded = Ash.load!(widget, :owned_by, actor: owner)
      assert loaded.owned_by.id == owner.id
    end

    test "loading a belongs_to_actor relationship resolves to the actor's current version, not the one stamped at creation" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      incremented_owner =
        owner
        |> Ash.Changeset.for_update(:increment, %{name: "Ada Lovelace"})
        |> Ash.update!()

      assert incremented_owner.resource_id == owner.resource_id
      assert incremented_owner.id != owner.id

      loaded = Ash.load!(widget, :owned_by)

      assert loaded.owned_by.id == incremented_owner.id
      assert loaded.owned_by.name == "Ada Lovelace"
    end

    test "a belongs_to_actor relationship stays scoped to the latest version even when loaded through a query using a non-default read action" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      incremented_owner =
        owner
        |> Ash.Changeset.for_update(:increment, %{name: "Ada Lovelace"})
        |> Ash.update!()

      loaded = Ash.load!(widget, owned_by: Ash.Query.for_read(Owner, :version_history))

      assert loaded.owned_by.id == incremented_owner.id
      assert loaded.owned_by.name == "Ada Lovelace"
    end

    test "a belongs_to_actor relationship still resolves after the actor itself has been archived" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      archived_owner =
        owner
        |> Ash.Changeset.for_destroy(:archive, %{})
        |> Ash.destroy!(return_destroyed?: true)

      assert archived_owner.resource_id == owner.resource_id
      assert archived_owner.archived == true

      loaded = Ash.load!(widget, :owned_by)

      assert loaded.owned_by.id == archived_owner.id
      assert loaded.owned_by.name == "Ada"
      assert loaded.owned_by.archived == true
    end

    test "actor attribution isn't limited to a single designated create action" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:import, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      assert widget.created_by == owner.resource_id
      assert widget.owned_by_id == owner.resource_id
    end

    test "a polymorphic actor: raw falls back to the plain primary key, and only the matching belongs_to field is stamped" do
      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Grace"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: user)
        |> Ash.create!(actor: user)

      assert widget.created_by == user.id
      assert widget.reviewed_by_id == user.id
      assert is_nil(widget.owned_by_id)
    end

    test "actor fields are re-stamped (not copied forward) on every mutation" do
      first_owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      second_owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Grace"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: first_owner)
        |> Ash.create!(actor: first_owner)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"}, actor: second_owner)
        |> Ash.update!(actor: second_owner)

      assert incremented.created_by == second_owner.resource_id
      assert incremented.owned_by_id == second_owner.resource_id
    end

    test "switching which belongs_to_actor type matches clears the previously-matched field, and reference_actor keeps tracking regardless" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Grace"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      assert widget.created_by == owner.resource_id
      assert widget.owned_by_id == owner.resource_id
      assert is_nil(widget.reviewed_by_id)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"}, actor: user)
        |> Ash.update!(actor: user)

      assert incremented.created_by == user.id
      assert incremented.reviewed_by_id == user.id
      assert is_nil(incremented.owned_by_id)

      rotated_back =
        incremented
        |> Ash.Changeset.for_update(:increment, %{status: "active-again"}, actor: owner)
        |> Ash.update!(actor: owner)

      assert rotated_back.created_by == owner.resource_id
      assert rotated_back.owned_by_id == owner.resource_id
      assert is_nil(rotated_back.reviewed_by_id)
    end

    test "rotating to a reference-only actor (matching no belongs_to_actor destination) clears every belongs_to_actor field" do
      owner =
        Owner
        |> Ash.Changeset.for_create(:create, %{name: "Ada"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: owner)
        |> Ash.create!(actor: owner)

      assert widget.owned_by_id == owner.resource_id
      assert is_nil(widget.reviewed_by_id)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"}, actor: "system")
        |> Ash.update!(actor: "system")

      assert incremented.created_by == "system"
      assert is_nil(incremented.owned_by_id)
      assert is_nil(incremented.reviewed_by_id)
    end

    test "identity origin: :accepted lets create supply its own identity attribute" do
      explicit_id = Ash.UUIDv7.generate()

      widget =
        AliasedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new", resource_id: explicit_id})
        |> Ash.create!()

      assert widget.resource_id == explicit_id
    end
  end

  describe "reference_actor value derivation" do
    test "an integer primary key actor is stringified, not rejected by the attribute's cast" do
      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Grace"})
        |> Ash.create!()

      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: user)
        |> Ash.create!(actor: user)

      assert widget.created_by == user.id
    end

    test "an actor with a composite primary key and no transform fails clearly, not by persisting the struct" do
      actor =
        CompositeKeyActor
        |> Ash.Changeset.for_create(:create, %{tenant: "acme", ref: "widget-1"})
        |> Ash.create!()

      assert {:error, error} =
               Widget
               |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: actor)
               |> Ash.create(actor: actor)

      assert Exception.message(error) =~ "Cannot derive an identity for provided actor"
    end

    test "a plain, non-Ash struct actor fails clearly instead of crashing on Spark.extensions/1" do
      assert {:error, error} =
               Widget
               |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: %PlainStructActor{id: "cron"})
               |> Ash.create(actor: %PlainStructActor{id: "cron"})

      assert %Invalid{errors: [%InvalidAttribute{field: :created_by}]} = error
    end

    test "a non-struct actor with no String.Chars implementation fails clearly, not by persisting garbage" do
      assert {:error, error} =
               Widget
               |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: %{tenant: "acme"})
               |> Ash.create(actor: %{tenant: "acme"})

      assert %Invalid{errors: [%InvalidAttribute{field: :created_by}]} = error
      assert Exception.message(error) =~ "Cannot derive an identity for provided actor"
    end

    test "a function transform derives a value for a composite-key actor the default derivation can't handle" do
      actor =
        CompositeKeyActor
        |> Ash.Changeset.for_create(:create, %{tenant: "acme", ref: "widget-1"})
        |> Ash.create!()

      widget =
        TransformedActorWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"}, actor: actor)
        |> Ash.create!(actor: actor)

      assert widget.handled_by == "acme:widget-1"
    end

    test "transform accepts an {module, function, args} MFA, with args appended after the actor" do
      reference_actor = %ReferenceActor{
        transform: {ReferenceActorTransforms, :prefixed, ["cust_"]}
      }

      assert AshVersioned.ActorValue.actor_value(reference_actor, %{
               tenant: "acme",
               ref: "widget-1"
             }) ==
               {:ok, "cust_acme:widget-1"}
    end
  end

  describe "temporal metadata" do
    test "inserted_at is set on create, and the old row's updated_at exactly equals the new row's inserted_at" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      refute is_nil(widget.inserted_at)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      stale_reloaded = Ash.get!(Widget, widget.id, action: :version_history)

      assert stale_reloaded.updated_at == incremented.inserted_at
    end
  end

  describe "read-only custom attributes carry forward across versions" do
    test "created_at is stamped once on create and copied unchanged through every later version" do
      widget =
        StampedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      refute is_nil(widget.created_at)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      assert incremented.created_at == widget.created_at
      assert incremented.inserted_at != widget.inserted_at
    end

    test "created_at cannot be set externally on create or update" do
      assert {:error, %Invalid{}} =
               StampedWidget
               |> Ash.Changeset.for_create(:create, %{
                 status: "new",
                 created_at: ~U[2000-01-01 00:00:00.000000Z]
               })
               |> Ash.create()

      widget =
        StampedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      assert {:error, %Invalid{}} =
               widget
               |> Ash.Changeset.for_update(:increment, %{
                 status: "active",
                 created_at: ~U[2000-01-01 00:00:00.000000Z]
               })
               |> Ash.update()
    end

    test "an explicit force_change_attribute on the incoming changeset is respected, same as a regular update" do
      widget =
        StampedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.Changeset.force_change_attribute(:created_at, ~U[2000-01-01 00:00:00.000000Z])
        |> Ash.update!()

      assert incremented.created_at == ~U[2000-01-01 00:00:00.000000Z]
    end
  end

  describe "primary key: AshVersioned verifies, it never generates" do
    test "a self-declared integer_primary_key works" do
      widget =
        Widget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      assert is_integer(widget.id)
    end

    test "a self-declared uuid_v7_primary_key works" do
      widget =
        UuidPkWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      assert is_binary(widget.id)
      assert {:ok, _} = Ecto.UUID.cast(widget.id)
    end

    test "a private (public?: false) primary key works through create and the flip/reinsert increment cycle" do
      assert is_nil(Info.public_attribute(UuidPkWidget, :id))

      widget =
        UuidPkWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      assert is_binary(widget.id)

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      assert incremented.id != widget.id
      assert incremented.resource_id == widget.resource_id
      assert incremented.version_number == widget.version_number + 1
    end

    test "a self-declared uuid_primary_key works" do
      widget =
        PreexistingPkWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      assert is_binary(widget.id)
      assert {:ok, _} = Ecto.UUID.cast(widget.id)
    end

    test "no primary key at all fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NoPkWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.NoPkWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "no primary key"))
    end

    test "a composite primary key fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.CompositePkWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              attribute :part_a, :uuid,
                primary_key?: true,
                allow_nil?: false,
                writable?: false,
                default: &Ash.UUID.generate/0

              attribute :part_b, :uuid,
                primary_key?: true,
                allow_nil?: false,
                writable?: false,
                default: &Ash.UUID.generate/0

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.CompositePkWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "composite primary key"))
    end

    test "a writable primary key (a natural key) fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NaturalKeyWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:sku]
              update :increment, accept: [:sku]
            end

            attributes do
              attribute :sku, :string,
                primary_key?: true,
                allow_nil?: false,
                writable?: true,
                public?: true

              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.NaturalKeyWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "natural"))
    end
  end

  describe "porting an existing schema: define_attribute? false adopts pre-declared columns" do
    test "identity/version/latest are adopted under their existing names and types" do
      widget =
        PortedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      refute is_nil(widget.mo_id)
      assert widget.mo_version == 0
      assert widget.mo_is_latest == true

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      assert incremented.mo_id == widget.mo_id
      assert incremented.mo_version == 1
      assert incremented.mo_is_latest == true

      stale_reloaded = Ash.get!(PortedWidget, widget.id, action: :version_history)
      assert stale_reloaded.mo_is_latest == false
    end

    test "more than one identity entity fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.DoubleIdentityWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              identity(:resource_id)
              identity(:other_id)
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.DoubleIdentityWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "Expected at most one identity"))
    end

    test "more than one reference_actor entity fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.DoubleReferenceActorWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              reference_actor :created_by
              reference_actor :touched_by
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.DoubleReferenceActorWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "Expected at most one reference_actor"))
    end

    test "a missing create_timestamp_attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NoTimestampsWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              attribute :status, :string, public?: true, allow_nil?: false
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.NoTimestampsWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "create_timestamp_attribute"))
    end

    test "a generated identity of an unrecognized type fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.UnknownIdentityTypeWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              identity :resource_id, type: :integer
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.UnknownIdentityTypeWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "doesn't know how to auto-generate"))
    end

    test "a nullable identity attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NullableIdentityWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              identity :resource_id do
                define_attribute? false
              end
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              # allow_nil?: true (the default) — the identity must never be nil.
              attribute :resource_id, :uuid,
                writable?: false,
                public?: true,
                default: &Ash.UUID.generate/0

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.NullableIdentityWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "allow_nil?: false"))
    end

    test "a writable version attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.WritableVersionWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              version :version_number do
                define_attribute? false
              end
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              # version must never be caller-writable.
              attribute :version_number, :integer,
                writable?: true,
                allow_nil?: false,
                default: 0,
                public?: true

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.WritableVersionWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "writable?: false"))
    end

    test "a nullable archived attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.NullableArchivedWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              archive do
                define_attribute? false
              end
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              # The archived flag must never be nil.
              attribute :archived, :boolean, writable?: false, default: false, public?: true

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.NullableArchivedWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "allow_nil?: false"))
    end

    test "a writable archived attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.WritableArchivedWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              archive do
                define_attribute? false
              end
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              # Archived must never be caller-writable.
              attribute :archived, :boolean,
                writable?: true,
                allow_nil?: false,
                default: false,
                public?: true

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.WritableArchivedWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "writable?: false"))
    end

    test "a non-boolean archived attribute fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.StringArchivedWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              archive do
                define_attribute? false
              end
            end

            actions do
              defaults [:read]
              create :create, accept: [:status]
              update :increment, accept: [:status]
            end

            attributes do
              integer_primary_key :id
              # Archived must be boolean-family.
              attribute :archived, :string,
                writable?: false,
                allow_nil?: false,
                default: "false",
                public?: true

              attribute :status, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end
          end
        end

      assert [{AshVersionedTest.StringArchivedWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "a type storing as one of"))
    end
  end

  describe "source_prefix and per-entity source overrides" do
    test "source_prefix prefixes every attribute AshVersioned generates, composing with a custom name" do
      assert Info.attribute(PrefixedWidget, :mo_id).source == :vo_mo_id

      assert Info.attribute(PrefixedWidget, :latest_version).source ==
               :vo_latest_version

      assert Info.attribute(PrefixedWidget, :archived).source == :vo_archived
    end

    test "an entity's own source wins over source_prefix" do
      assert Info.attribute(PrefixedWidget, :mo_version).source ==
               :explicit_version_source
    end

    test "with no source_prefix, source defaults to the attribute name as usual" do
      assert Info.attribute(Widget, :resource_id).source == :resource_id
    end

    test "a resource using source_prefix works end-to-end like any other" do
      widget =
        PrefixedWidget
        |> Ash.Changeset.for_create(:create, %{status: "new"})
        |> Ash.create!()

      incremented =
        widget
        |> Ash.Changeset.for_update(:increment, %{status: "active"})
        |> Ash.update!()

      assert incremented.mo_id == widget.mo_id
      assert incremented.mo_version == widget.mo_version + 1
      assert incremented.latest_version
    end
  end

  describe "AshVersioned.Resource.Info.versioning_entities/2" do
    test "a single module is equivalent to wrapping it in a list" do
      assert AshVersioned.Resource.Info.versioning_entities(Widget, BelongsToActor) ==
               AshVersioned.Resource.Info.versioning_entities(Widget, [BelongsToActor])
    end

    test "a single module filters down to only that entity type" do
      entities = AshVersioned.Resource.Info.versioning_entities(Widget, BelongsToActor)

      assert length(entities) == 2
      assert Enum.all?(entities, &match?(%BelongsToActor{}, &1))
    end

    test "a list of modules returns every matching entity, in declaration order" do
      entities =
        AshVersioned.Resource.Info.versioning_entities(Widget, [ReferenceActor, BelongsToActor])

      assert [%ReferenceActor{}, %BelongsToActor{}, %BelongsToActor{}] = entities
    end
  end

  describe "attribute-strategy multitenancy" do
    test "the same resource_id in two different tenants is not treated as the same identity" do
      shared_id = Ash.UUIDv7.generate()

      tenant_a =
        TenantWidget
        |> Ash.Changeset.for_create(:create, %{status: "a", resource_id: shared_id}, tenant: "tenant-a")
        |> Ash.create!()

      tenant_b =
        TenantWidget
        |> Ash.Changeset.for_create(:create, %{status: "b", resource_id: shared_id}, tenant: "tenant-b")
        |> Ash.create!()

      assert tenant_a.resource_id == shared_id
      assert tenant_b.resource_id == shared_id
      assert tenant_a.id != tenant_b.id
    end

    test "reads are scoped to the tenant even when resource_id matches across tenants" do
      shared_id = Ash.UUIDv7.generate()

      TenantWidget
      |> Ash.Changeset.for_create(:create, %{status: "a", resource_id: shared_id}, tenant: "tenant-a")
      |> Ash.create!()

      TenantWidget
      |> Ash.Changeset.for_create(:create, %{status: "b", resource_id: shared_id}, tenant: "tenant-b")
      |> Ash.create!()

      assert [only] = Ash.read!(TenantWidget, tenant: "tenant-a")
      assert only.status == "a"
    end

    test "incrementing a row in one tenant doesn't collide with the identically-identified row in another" do
      shared_id = Ash.UUIDv7.generate()

      tenant_a =
        TenantWidget
        |> Ash.Changeset.for_create(:create, %{status: "a", resource_id: shared_id}, tenant: "tenant-a")
        |> Ash.create!()

      TenantWidget
      |> Ash.Changeset.for_create(:create, %{status: "b", resource_id: shared_id}, tenant: "tenant-b")
      |> Ash.create!()

      incremented =
        tenant_a
        |> Ash.Changeset.for_update(:increment, %{status: "a2"}, tenant: "tenant-a")
        |> Ash.update!(tenant: "tenant-a")

      assert incremented.version_number == 1

      assert [only] = Ash.read!(TenantWidget, tenant: "tenant-b")
      assert only.status == "b"
      assert only.version_number == 0
    end

    test "a user's own identity marked all_tenants?: true is enforced globally, unlike resource_id" do
      TenantWidget
      |> Ash.Changeset.for_create(
        :create,
        %{status: "a", external_ref: "dup", resource_id: Ash.UUIDv7.generate()},
        tenant: "tenant-a"
      )
      |> Ash.create!()

      assert {:error, error} =
               TenantWidget
               |> Ash.Changeset.for_create(
                 :create,
                 %{status: "b", external_ref: "dup", resource_id: Ash.UUIDv7.generate()},
                 tenant: "tenant-b"
               )
               |> Ash.create()

      assert %Invalid{errors: [%InvalidAttribute{field: :external_ref}]} = error
    end

    test "a user's own identity is scoped to the latest row, so a superseded value can be reused" do
      widget =
        TenantWidget
        |> Ash.Changeset.for_create(
          :create,
          %{status: "a", external_ref: "original", resource_id: Ash.UUIDv7.generate()},
          tenant: "tenant-a"
        )
        |> Ash.create!()

      # Once "original" is superseded (widget's current latest row now holds "changed"),
      # no current row holds "original" any more.
      widget
      |> Ash.Changeset.for_update(:increment, %{status: "a2", external_ref: "changed"}, tenant: "tenant-a")
      |> Ash.update!(tenant: "tenant-a")

      assert {:ok, _} =
               TenantWidget
               |> Ash.Changeset.for_create(
                 :create,
                 %{status: "b", external_ref: "original", resource_id: Ash.UUIDv7.generate()},
                 tenant: "tenant-a"
               )
               |> Ash.create()
    end
  end

  describe "a user's own business unique keys" do
    test "partial-on-latest (unique_sku): only one current row per value, but a superseded value is reusable" do
      item =
        CatalogItem
        |> Ash.Changeset.for_create(:create, %{sku: "A"})
        |> Ash.create!()

      assert {:error, _} =
               CatalogItem
               |> Ash.Changeset.for_create(:create, %{sku: "A"})
               |> Ash.create()

      _incremented =
        item
        |> Ash.Changeset.for_update(:increment, %{sku: "B"})
        |> Ash.update!()

      assert {:ok, _} =
               CatalogItem
               |> Ash.Changeset.for_create(:create, %{sku: "A"})
               |> Ash.create()
    end

    test "a composite identity with latest folded into the keys (instead of a where:) fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.LatestInKeysWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:serial_number]
              update :increment, accept: [:serial_number]
            end

            attributes do
              integer_primary_key :id
              attribute :serial_number, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end

            identities do
              # This "looks" OK, but this results in an index on every row, which will
              # cause collisions on default index uniqueness.
              identity :unique_serial_number, [:serial_number, :latest_version]
            end
          end
        end

      assert [{AshVersionedTest.LatestInKeysWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "not safely scoped"))
    end

    test "a where:-scoped identity that also redundantly folds latest into the keys fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.RedundantLatestKeyWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            import Ash.Expr

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:legacy_code]
              update :increment, accept: [:legacy_code]
            end

            attributes do
              integer_primary_key :id
              attribute :legacy_code, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end

            identities do
              # The `where:` clause already scopes this to latest; also listing
              # `latest_version` as a key column adds nothing and should still be rejected.
              identity :unique_legacy_code, [:legacy_code, :latest_version], where: expr(latest_version == true)
            end
          end
        end

      assert [{AshVersionedTest.RedundantLatestKeyWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "not safely scoped"))
    end

    test "a plain unscoped identity fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.UnscopedIdentityWidget do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
            end

            actions do
              defaults [:read]
              create :create, accept: [:legacy_code]
              update :increment, accept: [:legacy_code]
            end

            attributes do
              integer_primary_key :id
              attribute :legacy_code, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end

            identities do
              # No `where:` or no version in the keys won't survive the object's first
              # mutation.
              identity :unique_legacy_code, [:legacy_code]
            end
          end
        end

      assert [{AshVersionedTest.UnscopedIdentityWidget, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "not safely scoped"))
    end
  end

  describe "borrowed identity: a plain users table alongside a versioned customers table" do
    test "Customer borrows User's own id as its resource_id, and it's stable across Customer's own versions" do
      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Ada Lovelace"})
        |> Ash.create!()

      customer =
        Customer
        |> Ash.Changeset.for_create(:create, %{resource_id: user.id, plan: "trial"})
        |> Ash.create!()

      assert customer.resource_id == user.id

      upgraded =
        customer
        |> Ash.Changeset.for_update(:increment, %{plan: "paid"})
        |> Ash.update!()

      assert upgraded.resource_id == user.id
      assert upgraded.plan == "paid"

      assert Ash.get!(User, user.id).name == "Ada Lovelace"
    end
  end
end

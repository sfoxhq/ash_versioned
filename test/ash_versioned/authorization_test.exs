# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.AuthorizationTest do
  use AshVersioned.DataCase, async: true

  alias Ash.Error.Changes.StaleRecord
  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias AshVersionedTest.GuardedWidget

  @editor %{role: "editor"}
  @viewer %{role: "viewer"}

  defp create(status) do
    GuardedWidget
    |> Ash.Changeset.for_create(:create, %{status: status}, actor: @editor)
    |> Ash.create!()
  end

  defp versioned_update(record, action, attrs, actor \\ @editor) do
    record
    |> Ash.Changeset.for_update(action, attrs, actor: actor)
    |> Ash.update()
  end

  describe "a versioned update" do
    test "is authorized against the update action, not the internal actions it runs through" do
      widget = create("open")

      assert {:ok, incremented} = versioned_update(widget, :increment, %{status: "active"})
      assert incremented.version_number == widget.version_number + 1
      assert incremented.status == "active"
    end

    test "with no applicable policy is forbidden" do
      assert {:error, %Forbidden{}} = versioned_update(create("open"), :unpoliced, %{status: "x"})
    end

    test "checks policies against the stored record" do
      assert {:ok, %{status: "x"}} = versioned_update(create("open"), :edit_open, %{status: "x"})

      assert {:error, %Forbidden{}} =
               versioned_update(create("closed"), :edit_open, %{status: "x"})
    end

    test "checks policies against the database, not the record passed in" do
      forged = %{create("closed") | status: "open"}

      assert {:error, %Forbidden{}} = versioned_update(forged, :edit_open, %{status: "x"})
    end

    test "checks policies against the actor" do
      assert {:ok, _} = versioned_update(create("open"), :edit_as_editor, %{status: "x"}, @editor)

      assert {:error, %Forbidden{}} =
               versioned_update(create("open"), :edit_as_editor, %{status: "x"}, @viewer)
    end

    test "checks policies against the change being made" do
      assert {:ok, %{status: "done"}} =
               versioned_update(create("open"), :edit_unless_locking, %{status: "done"})

      assert {:error, %Forbidden{}} =
               versioned_update(create("open"), :edit_unless_locking, %{status: "locked"})
    end

    test "of a superseded version is rejected as stale, even when policies allow it" do
      widget = create("open")
      assert {:ok, _} = versioned_update(widget, :edit_open, %{status: "closed"})

      # The superseded row still says "open", so the policy passes; the stale check
      # rejects it.
      assert {:error, %Invalid{errors: [%StaleRecord{}]}} =
               versioned_update(widget, :edit_open, %{status: "x"})
    end
  end

  describe "a versioned archive" do
    test "is authorized against the destroy action" do
      widget = create("open")

      archived =
        widget
        |> Ash.Changeset.for_destroy(:archive, %{}, actor: @editor)
        |> Ash.destroy!(return_destroyed?: true)

      assert archived.archived == true
      assert archived.version_number == widget.version_number + 1

      assert {:error, %Forbidden{}} =
               "closed"
               |> create()
               |> Ash.Changeset.for_destroy(:archive, %{}, actor: @editor)
               |> Ash.destroy()
    end
  end

  describe "a bulk versioned update" do
    test "authorizes and versions each record separately" do
      for status <- ["open", "open", "closed"], do: create(status)

      # Versioned updates are manual actions, so can't use the default `:atomic` bulk
      # strategy.
      result =
        Ash.bulk_update(GuardedWidget, :edit_open, %{status: "edited"},
          actor: @editor,
          strategy: :stream,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :partial_success
      assert [%Forbidden{}] = result.errors

      assert Enum.map(result.records, &{&1.status, &1.version_number}) == [
               {"edited", 1},
               {"edited", 1}
             ]

      rows =
        GuardedWidget
        |> Ash.read!(action: :version_history, authorize?: false)
        |> Enum.map(&{&1.status, &1.version_number, &1.latest_version})
        |> Enum.sort()

      assert rows == [
               {"closed", 0, true},
               {"edited", 1, true},
               {"edited", 1, true},
               {"open", 0, false},
               {"open", 0, false}
             ]
    end
  end

  describe "internal actions" do
    test "can't be called directly without a policy allowing them" do
      assert {:error, %Forbidden{}} =
               GuardedWidget
               |> Ash.Changeset.for_create(:__ash_versioned_reinsert__, %{status: "forged"}, actor: @editor)
               |> Ash.create()

      assert {:error, %Forbidden{}} =
               versioned_update(create("open"), :__ash_versioned_mark_stale__, %{})
    end
  end
end

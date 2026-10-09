# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.RelationshipsTest do
  use AshVersioned.DataCase, async: true

  alias AshVersionedTest.Customer
  alias AshVersionedTest.Editor
  alias AshVersionedTest.Note
  alias AshVersionedTest.Project
  alias AshVersionedTest.Task
  alias AshVersionedTest.User

  require Ash.Query
  require Spark.Test

  defp create_project(attrs \\ %{}) do
    Project
    |> Ash.Changeset.for_create(:create, Map.merge(%{title: "Apollo"}, attrs))
    |> Ash.create!()
  end

  defp create_task(project, title) do
    Task
    |> Ash.Changeset.for_create(:create, %{title: title, project_id: project.resource_id})
    |> Ash.create!()
  end

  defp increment(record, attrs) do
    record
    |> Ash.Changeset.for_update(:increment, attrs)
    |> Ash.update!()
  end

  defp archive(record) do
    record
    |> Ash.Changeset.for_destroy(:archive, %{})
    |> Ash.destroy!(return_destroyed?: true)
  end

  describe "belongs_to_versioned" do
    test "from a non-versioned resource, resolves the destination's latest version by identity" do
      project = create_project()

      note =
        Note
        |> Ash.Changeset.for_create(:create, %{body: "kickoff", project_id: project.resource_id})
        |> Ash.create!()

      renamed = increment(project, %{title: "Artemis"})

      loaded = Ash.load!(note, :project)

      assert loaded.project.id == renamed.id
      assert loaded.project.title == "Artemis"
    end

    test "from a versioned resource, survives versions of both the source and the destination" do
      project = create_project()
      task = create_task(project, "design")

      renamed_project = increment(project, %{title: "Artemis"})
      renamed_task = increment(task, %{title: "build"})

      assert renamed_task.project_id == project.resource_id

      loaded = Ash.load!(renamed_task, :project)

      assert loaded.project.id == renamed_project.id
    end

    test "still resolves after the destination has been archived" do
      project = create_project()

      note =
        Note
        |> Ash.Changeset.for_create(:create, %{body: "kickoff", project_id: project.resource_id})
        |> Ash.create!()

      archived = archive(project)

      loaded = Ash.load!(note, :project)

      assert loaded.project.id == archived.id
      assert loaded.project.archived == true
    end

    test "filtering through the relationship only considers the latest version" do
      project = create_project()

      Note
      |> Ash.Changeset.for_create(:create, %{body: "kickoff", project_id: project.resource_id})
      |> Ash.create!()

      increment(project, %{title: "Artemis"})

      assert [] =
               Note
               |> Ash.Query.filter(project.title == "Apollo")
               |> Ash.read!()

      assert [_note] =
               Note
               |> Ash.Query.filter(project.title == "Artemis")
               |> Ash.read!()
    end

    test "is self-referential" do
      parent = create_project(%{title: "Program"})
      child = create_project(%{parent_id: parent.resource_id})

      renamed_parent = increment(parent, %{title: "Program II"})

      loaded = Ash.load!(child, :parent)

      assert loaded.parent.id == renamed_parent.id
    end

    test "is mutually referential" do
      project = create_project()
      task = create_task(project, "design")

      featuring = increment(project, %{featured_task_id: task.resource_id})
      renamed_task = increment(task, %{title: "build"})

      loaded = Ash.load!(featuring, [:featured_task, featured_task: :project])

      assert loaded.featured_task.id == renamed_task.id
      assert loaded.featured_task.project.id == featuring.id
    end
  end

  describe "has_many_versioned" do
    test "doesn't depend on the destination's history action name" do
      assert Ash.Resource.Info.relationship(Project, :tasks).read_action ==
               :__ash_versioned_read__

      assert AshVersioned.Resource.Info.versioning_history_action!(Task) == :all_versions
    end

    test "loads only the latest version of each related record" do
      project = create_project()
      task = create_task(project, "design")
      create_task(project, "test")

      task
      |> increment(%{title: "build"})
      |> increment(%{title: "ship"})

      loaded = Ash.load!(project, :tasks)

      assert loaded.tasks
             |> Enum.map(& &1.title)
             |> Enum.sort() == ["ship", "test"]
    end

    test "resolves from every version of a versioned source" do
      project = create_project()
      create_task(project, "design")

      renamed = increment(project, %{title: "Artemis"})

      assert [%{title: "design"}] = Ash.load!(renamed, :tasks).tasks
    end

    test "aggregates count records, not versions" do
      project = create_project()
      task = create_task(project, "design")
      create_task(project, "test")

      task
      |> increment(%{title: "build"})
      |> increment(%{title: "ship"})

      assert Ash.load!(project, :task_count).task_count == 2
    end

    test "exists only considers the latest version" do
      project = create_project()
      task = create_task(project, "design")

      increment(task, %{title: "build"})

      assert [] =
               Project
               |> Ash.Query.filter(exists(tasks, title == "design"))
               |> Ash.read!()

      assert [_project] =
               Project
               |> Ash.Query.filter(exists(tasks, title == "build"))
               |> Ash.read!()
    end

    test "includes archived records, which a relationship filter can exclude" do
      project = create_project()
      task = create_task(project, "design")
      create_task(project, "test")

      archive(task)

      loaded = Ash.load!(project, [:tasks, :active_tasks, :task_count, :active_task_count])

      assert loaded.tasks
             |> Enum.map(& &1.title)
             |> Enum.sort() == ["design", "test"]

      assert [%{title: "test"}] = loaded.active_tasks
      assert loaded.task_count == 2
      assert loaded.active_task_count == 1
    end
  end

  describe "versioned relationships through other relationships" do
    test "resolve the latest version of each record, archived or not, in loads and aggregates" do
      project = create_project()

      project
      |> create_task("design")
      |> increment(%{title: "build"})
      |> increment(%{title: "ship"})

      project
      |> create_task("abandoned")
      |> archive()

      increment(project, %{title: "Artemis"})

      note =
        Note
        |> Ash.Changeset.for_create(:create, %{body: "kickoff", project_id: project.resource_id})
        |> Ash.create!()
        |> Ash.load!([:project_tasks, :project_task_titles])

      assert note.project_tasks
             |> Enum.map(& &1.title)
             |> Enum.sort() == ["abandoned", "ship"]

      assert Enum.sort(note.project_task_titles) == ["abandoned", "ship"]
    end

    test "fail to compile when a relationship in the path to a versioned resource isn't versioned" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.UnversionedHopNote do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Relationships]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :project, AshVersionedTest.Project do
                destination_attribute :resource_id
                validate_destination_attribute? false
              end

              has_many :project_tasks, AshVersionedTest.Task, through: [:project, :tasks]
            end
          end
        end

      assert [{AshVersionedTest.UnversionedHopNote, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "Use `belongs_to_versioned` for :project"))
    end
  end

  describe "has_one_versioned" do
    test "loads the latest version of a record identified by the source's primary key" do
      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Ada Lovelace"})
        |> Ash.create!()

      customer =
        Customer
        |> Ash.Changeset.for_create(:create, %{resource_id: user.id, plan: "trial"})
        |> Ash.create!()

      upgraded = increment(customer, %{plan: "paid"})

      loaded = Ash.load!(user, :customer)

      assert loaded.customer.id == upgraded.id

      assert [] =
               User
               |> Ash.Query.filter(customer.plan == "trial")
               |> Ash.read!()

      assert [_user] =
               User
               |> Ash.Query.filter(customer.plan == "paid")
               |> Ash.read!()
    end
  end

  describe "self-referential belongs_to_actor" do
    test "compiles and resolves the actor's latest version" do
      chief =
        Editor
        |> Ash.Changeset.for_create(:create, %{name: "Chief"})
        |> Ash.create!()

      assert is_nil(chief.edited_by_id)

      editor =
        Editor
        |> Ash.Changeset.for_create(:create, %{name: "Junior"}, actor: chief)
        |> Ash.create!(actor: chief)

      assert editor.edited_by_id == chief.resource_id

      promoted = increment(chief, %{name: "Editor in Chief"})

      loaded = Ash.load!(editor, :edited_by)

      assert loaded.edited_by.id == promoted.id
    end
  end

  describe "destination_attribute resolution" do
    test "defaults to :resource_id" do
      assert Ash.Resource.Info.relationship(Note, :project).destination_attribute == :resource_id
    end

    test "a self-referential belongs_to_versioned uses the resource's own renamed identity" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.RenamedIdentityNode do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Resource]

            versioning do
              identity :node_id
            end

            actions do
              defaults [:read]
              create :create, accept: [:name, :parent_id]
              update :increment, accept: [:name]
            end

            attributes do
              uuid_v7_primary_key :id
              attribute :name, :string, public?: true, allow_nil?: false
              create_timestamp :inserted_at
              update_timestamp :updated_at
            end

            relationships do
              belongs_to_versioned :parent, __MODULE__
            end
          end
        end

      # The inline Ets fixture has unrelated errors (identity pre-checks, domain
      # registration); only the versioned relationship verification matters here.
      refute Enum.any?(errors, fn {_module, dsl_errors} ->
               Enum.any?(dsl_errors, &(Exception.message(&1) =~ "Versioned relationship"))
             end)

      relationship = Ash.Resource.Info.relationship(AshVersionedTest.RenamedIdentityNode, :parent)

      assert relationship.destination_attribute == :node_id
    end
  end

  describe "compile-time verification" do
    test "a versioned relationship to a non-versioned resource fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.UnversionedDestinationNote do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Relationships]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to_versioned :user, AshVersionedTest.User
            end
          end
        end

      assert [{AshVersionedTest.UnversionedDestinationNote, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "is not an `AshVersioned.Resource`"))
    end

    test "a belongs_to_versioned not joined on the destination's identity fails to compile" do
      errors =
        Spark.Test.dsl_errors do
          defmodule Elixir.AshVersionedTest.WrongIdentityNote do
            @moduledoc false
            use Ash.Resource,
              domain: :"Elixir.AshVersionedTest.Domain",
              data_layer: :"Elixir.Ash.DataLayer.Ets",
              extensions: [AshVersioned.Relationships]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to_versioned :project, AshVersionedTest.Project, destination_attribute: :id
            end
          end
        end

      assert [{AshVersionedTest.WrongIdentityNote, dsl_errors}] = errors
      assert Enum.any?(dsl_errors, &(&1.message =~ "identity attribute"))
    end

    test "declaring the reserved relationship read action on a versioned resource fails to compile" do
      assert_raise Spark.Error.DslError, ~r/reserved by AshVersioned/, fn ->
        defmodule Elixir.AshVersionedTest.ReservedReadActionWidget do
          @moduledoc false
          use Ash.Resource,
            domain: :"Elixir.AshVersionedTest.Domain",
            data_layer: :"Elixir.Ash.DataLayer.Ets",
            extensions: [AshVersioned.Resource]

          versioning do
          end

          actions do
            defaults [:read]
            read :__ash_versioned_read__
            create :create, accept: [:status]
            update :increment, accept: [:status]
          end

          attributes do
            attribute :status, :string, public?: true, allow_nil?: false
          end
        end
      end
    end

    test "declaring the reserved latest calculation on a versioned resource fails to compile" do
      assert_raise Spark.Error.DslError, ~r/reserved by AshVersioned/, fn ->
        defmodule Elixir.AshVersionedTest.ReservedCalculationWidget do
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
          end

          calculations do
            calculate :__ash_versioned_latest__, :boolean, expr(true)
          end
        end
      end
    end
  end
end

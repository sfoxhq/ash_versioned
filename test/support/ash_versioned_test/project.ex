# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Project do
  @moduledoc """
  Versioned resource with versioned relationships: a self-referential
  `belongs_to_versioned`, a `belongs_to_versioned` that is mutually referential with
  `AshVersionedTest.Task`, and `has_many_versioned` relationships to
  `AshVersionedTest.Task`. Lists `AshVersioned.Relationships` explicitly alongside
  `AshVersioned.Resource`, which also adds it.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource, AshVersioned.Relationships]

  alias AshVersionedTest.Repo
  alias AshVersionedTest.Task

  postgres do
    table "projects"
    repo Repo
  end

  versioning do
    archive do
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :parent_id, :featured_task_id]
    end

    update :increment do
      accept [:title, :parent_id, :featured_task_id]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to_versioned :parent, __MODULE__
    belongs_to_versioned :featured_task, Task

    has_many_versioned :tasks, Task do
      source_attribute :resource_id
      destination_attribute :project_id
    end

    has_many_versioned :active_tasks, Task do
      source_attribute :resource_id
      destination_attribute :project_id
      filter expr(archived == false)
    end
  end

  aggregates do
    count :task_count, :tasks
    count :active_task_count, :active_tasks
  end
end

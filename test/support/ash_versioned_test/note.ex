# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Note do
  @moduledoc """
  Non-versioned resource with a `belongs_to_versioned` to a versioned
  `AshVersionedTest.Project`, and a `has_many_versioned` through it to the project's
  versioned `AshVersionedTest.Task`s.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Relationships]

  alias AshVersionedTest.Project
  alias AshVersionedTest.Repo
  alias AshVersionedTest.Task

  postgres do
    table "notes"
    repo Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:body, :project_id]
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :body, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to_versioned :project, Project
    has_many_versioned :project_tasks, Task, through: [:project, :tasks]
  end

  aggregates do
    list :project_task_titles, :project_tasks, :title
  end
end

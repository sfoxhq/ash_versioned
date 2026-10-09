# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Task do
  @moduledoc """
  Versioned resource belonging to a versioned `AshVersionedTest.Project`, relying on
  `AshVersioned.Resource` to add `AshVersioned.Relationships`.
  """

  use Ash.Resource,
    domain: AshVersionedTest.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  alias AshVersionedTest.Project
  alias AshVersionedTest.Repo

  postgres do
    table "tasks"
    repo Repo
  end

  # A renamed history action must not affect relationships to this resource.
  versioning do
    history_action :all_versions

    archive do
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :project_id]
    end

    update :increment do
      accept [:title, :project_id]
    end
  end

  attributes do
    integer_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to_versioned :project, Project, allow_nil?: false
  end
end

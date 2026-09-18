# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.Info do
  @moduledoc """
  Introspection helpers for the `AshVersioned.Resource` extension.
  """

  use Spark.InfoGenerator, extension: AshVersioned.Resource, sections: [:versioning]

  alias AshVersioned.Resource.Archive
  alias AshVersioned.Resource.Identity
  alias AshVersioned.Resource.Latest
  alias AshVersioned.Resource.Version

  @doc """
  Finds the first `AshVersioned.Resource` entry for the provided entity module or returns
  `nil` if not found.
  """
  def versioning_entity(dsl_or_resource, module) do
    dsl_or_resource
    |> versioning()
    |> Enum.find(&(&1.__struct__ == module))
  end

  @doc """
  Filters `AshVersioned.Resource` entries on the provided entity module or list of entity
  modules.
  """
  def versioning_entities(dsl_or_resource, modules) do
    modules = List.wrap(modules)

    dsl_or_resource
    |> versioning()
    |> Enum.filter(&(&1.__struct__ in modules))
  end

  @doc """
  The `AshVersioned.Resource.Identity` entity for this resource.
  """
  def versioning_identity(dsl_or_resource), do: versioning_entity(dsl_or_resource, Identity)

  @doc "The name of the identity attribute."
  def versioning_identity_attribute(dsl_or_resource), do: versioning_identity(dsl_or_resource).name

  @doc """
  The `AshVersioned.Resource.Version` entity for this resource.
  """
  def versioning_version(dsl_or_resource), do: versioning_entity(dsl_or_resource, Version)

  @doc "The name of the version attribute."
  def versioning_version_attribute(dsl_or_resource), do: versioning_version(dsl_or_resource).name

  @doc """
  The `AshVersioned.Resource.Latest` entity for this resource.
  """
  def versioning_latest(dsl_or_resource), do: versioning_entity(dsl_or_resource, Latest)

  @doc "The name of the latest attribute."
  def versioning_latest_attribute(dsl_or_resource), do: versioning_latest(dsl_or_resource).name

  @doc """
  The `AshVersioned.Resource.Archive` entity for this resource, or `nil` if none is
  declared.
  """
  def versioning_archive(dsl_or_resource), do: versioning_entity(dsl_or_resource, Archive)

  @doc """
  Returns `true` if this resource declares an `archive` entity.
  """
  def versioning_archivable?(dsl_or_resource), do: not is_nil(versioning_archive(dsl_or_resource))

  @doc """
  The name of the archived attribute. Raises if the resource isn't archivable — check
  `versioning_archivable?/1` first.
  """
  def versioning_archived_attribute!(dsl_or_resource), do: versioning_archive(dsl_or_resource).attribute

  @doc """
  Returns the list of all read actions that should be exempted from read filtering
  entirely (explicitly configured actions and the history action).
  """
  def versioning_all_excluded_read_actions!(dsl_or_resource) do
    [
      versioning_history_action!(dsl_or_resource)
      | versioning_exclude_read_actions!(dsl_or_resource)
    ]
  end

  @doc """
  Returns the list of read actions that should skip only archived record filtering but
  keep latest record filtering. Returns `[]` if the resource isn't archivable.
  """
  def versioning_archive_excluded_read_actions!(dsl_or_resource) do
    case versioning_archive(dsl_or_resource) do
      nil ->
        []

      %Archive{read_action: false, exclude_read_actions: exclude_read_actions} ->
        exclude_read_actions

      %Archive{read_action: read_action, exclude_read_actions: exclude_read_actions} ->
        [read_action | exclude_read_actions]
    end
  end
end

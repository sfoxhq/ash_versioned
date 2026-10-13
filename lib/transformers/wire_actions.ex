# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Transformers.WireActions do
  @moduledoc """
  Wires up the actions and overrides that make versioning work.

  - Defines the create action `__ash_versioned_reinsert__`, the update action
    `__ash_versioned_mark_stale__`, the history read action, and the read action
    `__ash_versioned_read__` used by relationships to this resource.
  - Adds `AshVersioned.Resource.ManualIncrement` as `manual` on every user update action,
    except those in `exclude_update_actions`.
  - Ensures that every create action applies actor attribution.
  - Ensures that every create action accepts the identity attribute when the resource
    identity is `origin: :accepted`.
  - When the resource declares `archive`, every destroy action is marked `soft?: true`,
    and may create a default destroy action if none are defined.

  Note that update actions with `manual` implementations will be rejected; this is not
  currently a supported workflow.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Change.SetAttribute
  alias Ash.Resource.Dsl
  alias Ash.Resource.Info
  alias Ash.Resource.Transformers.BelongsToAttribute
  alias AshVersioned.Changes.ActorAttribution
  alias AshVersioned.Changes.RejectUpsert
  alias AshVersioned.Resource.Archive
  alias AshVersioned.Resource.BelongsToActor
  alias AshVersioned.Resource.Info, as: VersioningInfo
  alias AshVersioned.Resource.ManualIncrement
  alias AshVersioned.Resource.ReferenceActor
  alias AshVersioned.Transformers.AddFields
  alias AshVersioned.VersionedRelationship
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @mark_stale_action_name :__ash_versioned_mark_stale__
  @reinsert_action_name :__ash_versioned_reinsert__

  @doc "The name of the generated action that flips a row from latest to stale."
  def mark_stale_action_name, do: @mark_stale_action_name

  @doc """
  The name of the generated `:create` action `AshVersioned.Resource.ManualIncrement`
  reinserts through.
  """
  def reinsert_action_name, do: @reinsert_action_name

  @impl Transformer
  def after?(AddFields), do: true
  def after?(BelongsToAttribute), do: true
  def after?(_), do: false

  @impl Transformer
  def transform(dsl) do
    relationship_read_action = VersionedRelationship.read_action()

    if action_named?(dsl, relationship_read_action) or
         VersioningInfo.versioning_history_action!(dsl) == relationship_read_action do
      {:error,
       DslError.exception(
         module: Transformer.get_persisted(dsl, :module),
         path: [:actions, relationship_read_action],
         message: """
         `#{inspect(relationship_read_action)}` is reserved by AshVersioned for the \
         generated relationship read action and cannot be declared on a versioned resource.
         """
       )}
    else
      wire_actions(dsl)
    end
  end

  defp wire_actions(dsl) do
    user_create_actions =
      dsl
      |> Transformer.get_entities([:actions])
      |> Enum.filter(&(&1.type == :create))

    identity = VersioningInfo.versioning_identity(dsl)
    latest = VersioningInfo.versioning_latest(dsl)
    exclude_update_actions = VersioningInfo.versioning_exclude_update_actions!(dsl)
    history_action_name = VersioningInfo.versioning_history_action!(dsl)
    archive = VersioningInfo.versioning_archive(dsl)

    reinsertable_attributes =
      dsl
      |> Info.attributes()
      |> Enum.filter(& &1.writable?)
      |> Enum.map(& &1.name)

    mark_stale_change =
      Transformer.build_entity!(Dsl, [:actions, :update], :change,
        change: {SetAttribute, attribute: latest.name, value: false}
      )

    mark_stale_action =
      Transformer.build_entity!(Dsl, [:actions], :update,
        name: mark_stale_action_name(),
        accept: [],
        require_atomic?: true,
        atomic_upgrade_with: history_action_name,
        changes: [mark_stale_change]
      )

    reinsert_action =
      Transformer.build_entity!(Dsl, [:actions], :create,
        name: reinsert_action_name(),
        accept: reinsertable_attributes
      )

    history_action =
      Transformer.build_entity!(Dsl, [:actions], :read,
        name: history_action_name,
        primary?: false
      )

    relationship_read_action =
      Transformer.build_entity!(Dsl, [:actions], :read,
        name: VersionedRelationship.read_action(),
        primary?: false
      )

    reject_upsert_change =
      Transformer.build_entity!(Dsl, [:changes], :change, change: RejectUpsert, on: [:create])

    dsl =
      dsl
      |> Transformer.add_entity([:actions], mark_stale_action)
      |> Transformer.add_entity([:actions], reinsert_action)
      |> Transformer.add_entity([:actions], history_action)
      |> Transformer.add_entity([:actions], relationship_read_action)
      |> Transformer.add_entity([:changes], reject_upsert_change)
      |> maybe_generate_unarchive_action(archive)
      |> wire_mutate_actions(exclude_update_actions)
      |> wire_create_actions(user_create_actions, identity.origin, identity.name)
      |> maybe_generate_default_destroy_action(archive)
      |> wire_destroy_actions(archive)
      |> maybe_generate_archive_read_action(archive, identity.name)

    {:ok, dsl}
  end

  defp maybe_generate_archive_read_action(dsl, nil, _identity_field), do: dsl

  # coveralls-ignore-next-line # Exercised at compile time
  defp maybe_generate_archive_read_action(dsl, %Archive{read_action: false}, _identity_field), do: dsl

  defp maybe_generate_archive_read_action(dsl, %Archive{read_action: action_name}, identity_field) do
    if action_named?(dsl, action_name) do
      # coveralls-ignore-next-line # Exercised at compile time
      dsl
    else
      read_action =
        Transformer.build_entity!(Dsl, [:actions], :read,
          name: action_name,
          primary?: false,
          get_by: [identity_field]
        )

      Transformer.add_entity(dsl, [:actions], read_action)
    end
  end

  defp maybe_generate_unarchive_action(dsl, nil), do: dsl

  # coveralls-ignore-next-line # Exercised at compile time
  defp maybe_generate_unarchive_action(dsl, %Archive{unarchive: false}), do: dsl

  defp maybe_generate_unarchive_action(dsl, %Archive{unarchive: action_name, attribute: archived_field}) do
    if action_named?(dsl, action_name) do
      dsl
    else
      unarchive_change =
        Transformer.build_entity!(Dsl, [:actions, :update], :change,
          change: {SetAttribute, attribute: archived_field, value: false}
        )

      unarchive_action =
        Transformer.build_entity!(Dsl, [:actions], :update,
          name: action_name,
          accept: [],
          changes: [unarchive_change]
        )

      Transformer.add_entity(dsl, [:actions], unarchive_action)
    end
  end

  defp action_named?(dsl, name), do: Enum.any?(Transformer.get_entities(dsl, [:actions]), &(&1.name == name))

  defp maybe_generate_default_destroy_action(dsl, nil), do: dsl

  # coveralls-ignore-next-line # Exercised at compile time
  defp maybe_generate_default_destroy_action(dsl, %Archive{action: false}), do: dsl

  defp maybe_generate_default_destroy_action(dsl, %Archive{action: action_name}) do
    if Enum.any?(Transformer.get_entities(dsl, [:actions]), &(&1.type == :destroy)) do
      # coveralls-ignore-next-line # Exercised at compile time
      dsl
    else
      destroy_action = Transformer.build_entity!(Dsl, [:actions], :destroy, name: action_name)
      Transformer.add_entity(dsl, [:actions], destroy_action)
    end
  end

  defp wire_destroy_actions(dsl, nil), do: dsl

  defp wire_destroy_actions(dsl, %Archive{attribute: archived_field}) do
    archive_change =
      Transformer.build_entity!(Dsl, [:actions, :destroy], :change,
        change: {SetAttribute, attribute: archived_field, value: true}
      )

    dsl
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&(&1.type == :destroy))
    |> Enum.reduce(dsl, fn destroy_action, dsl ->
      updated = %{
        destroy_action
        | soft?: true,
          require_atomic?: false,
          manual: {ManualIncrement, original_manual: destroy_action.manual},
          changes: [archive_change | destroy_action.changes]
      }

      Transformer.replace_entity(dsl, [:actions], updated, &(&1.name == destroy_action.name))
    end)
  end

  defp wire_mutate_actions(dsl, exclude_update_actions) do
    excluded = MapSet.new([@mark_stale_action_name | exclude_update_actions])

    dsl
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&(&1.type == :update && !MapSet.member?(excluded, &1.name)))
    |> Enum.reduce(dsl, fn action, dsl ->
      replaced = %{
        action
        | manual: {ManualIncrement, original_manual: action.manual},
          require_atomic?: false
      }

      Transformer.replace_entity(dsl, [:actions], replaced, &(&1.name == action.name))
    end)
  end

  defp wire_create_actions(dsl, create_actions, identity_origin, identity_field) do
    actors = VersioningInfo.versioning_entities(dsl, [ReferenceActor, BelongsToActor])

    actor_changes =
      Enum.map(actors, fn actor ->
        # coveralls-ignore-next-line
        Transformer.build_entity!(Dsl, [:actions, :create], :change, change: {ActorAttribution, actor_config: actor})
      end)

    Enum.reduce(create_actions, dsl, fn create_action, dsl ->
      accept =
        if identity_origin == :accepted do
          # coveralls-ignore-next-line
          Enum.uniq((create_action.accept || []) ++ [identity_field])
        else
          create_action.accept
        end

      replaced = %{
        create_action
        | changes: create_action.changes ++ actor_changes,
          accept: accept
      }

      Transformer.replace_entity(dsl, [:actions], replaced, &(&1.name == create_action.name))
    end)
  end
end

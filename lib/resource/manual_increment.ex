# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.ManualIncrement do
  @moduledoc """
  Implements the core atomic primitive for `AshVersioned.Resource`s: mark the current
  latest row as stale and insert a new version in a single transaction. This works for all
  update actions and, if the resource has `archive` set, destroy actions.

  Increment is implemented as a bulk update scoped to the current row's primary key and
  latest flag. This acts as an optimistic locking signal so that a concurrent update that
  commits earlier will force this to fail with `Ash.Error.Changes.StaleRecord` instead of
  reinserting on top of already-stale data.

  AshVersioned performs the increment in a transaction that does the following:

  1. Captures the change timestamp
  2. Updates the old version latest flag (to false) and the update timestamp
  3. Clears the primary key
  4. Copies the versioned resource's identity field
  5. Increments the version number by 1
  6. Sets the latest flag to true
  7. Sets the creation and update timestamps to the captured change timestamp
  8. Applies the actor attributions from the context
  9. Copies all other writable or non-generated values from the old resource changeset or
     data to the new resource; this includes the archived field (if present)
  """

  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  import Ash.Expr

  alias Ash.Error.Changes.StaleRecord
  alias Ash.Resource.ManualDestroy
  alias Ash.Resource.ManualUpdate
  alias AshVersioned.Changes.ActorAttribution
  alias AshVersioned.Resource.BelongsToActor
  alias AshVersioned.Resource.Info
  alias AshVersioned.Resource.ReferenceActor
  alias AshVersioned.Transformers.WireActions

  require Ash.Query

  @doc """
  Increments a new version for the resource on update.
  """
  @impl ManualUpdate
  def update(changeset, _opts, context), do: increment(changeset, context)

  # coveralls-ignore-start
  #
  # This function is required for implementation of `destroy` actions, but is never called
  # because `soft?` deletions converts destroy actions into update actions.
  @doc false
  @impl ManualDestroy
  def destroy(changeset, _opts, context), do: increment(changeset, context)
  # coveralls-ignore-stop

  defp increment(changeset, context) do
    updated_at_field = Info.versioning_update_timestamp_attribute!(changeset.resource)

    if Map.delete(changeset.attributes, updated_at_field) == %{} do
      {:ok, changeset.data}
    else
      now = DateTime.utc_now()

      Ash.transact(
        changeset.resource,
        fn -> mark_stale_and_reinsert(changeset, context, now) end,
        tenant: context.tenant,
        return_notifications?: context.return_notifications? || false
      )
    end
  end

  # Both halves of the increment primitive (marking the old version stale and inserting
  # the new version) must pass. If either fails, call `AshDataLayer.rollback/2` to abort
  # the transaction.
  defp mark_stale_and_reinsert(changeset, context, now) do
    %{resource: resource, data: current} = changeset
    [pk_field] = Ash.Resource.Info.primary_key(resource)
    identity_field = Info.versioning_identity_attribute(resource)
    latest_field = Info.versioning_latest_attribute(resource)
    updated_at_field = Info.versioning_update_timestamp_attribute!(resource)

    flip_result =
      resource
      |> Ash.Query.filter(^ref(pk_field) == ^Map.fetch!(current, pk_field) and ^ref(latest_field) == true)
      |> Ash.bulk_update(WireActions.mark_stale_action_name(), %{},
        strategy: :atomic,
        return_records?: true,
        authorize?: false,
        actor: context.actor,
        tenant: context.tenant,
        atomic_update: %{updated_at_field => now}
      )

    case flip_result do
      %Ash.BulkResult{error_count: 0, records: [_]} ->
        reinsert(changeset, context, now)

      # If no updates were applied, and there are no errors, we tried to update a stale
      # resource.
      %Ash.BulkResult{error_count: 0, records: []} ->
        Ash.DataLayer.rollback(
          resource,
          StaleRecord.exception(resource: resource, field: identity_field)
        )

      %Ash.BulkResult{errors: errors} ->
        Ash.DataLayer.rollback(resource, errors)
    end
  end

  defp reinsert(original_changeset, context, now) do
    %{resource: resource, data: current} = original_changeset
    identity_field = Info.versioning_identity_attribute(resource)
    inserted_at_field = Info.versioning_create_timestamp_attribute!(resource)
    latest_field = Info.versioning_latest_attribute(resource)
    updated_at_field = Info.versioning_update_timestamp_attribute!(resource)
    version_field = Info.versioning_version_attribute(resource)

    managed_fields =
      [identity_field, inserted_at_field, latest_field, updated_at_field, version_field] ++
        archived_field_list(resource) ++ actor_field_names(resource)

    carried_over_fields = carried_over_readonly_attribute_names(resource, managed_fields)

    attrs =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.filter(& &1.writable?)
      |> Enum.map(& &1.name)
      |> then(&Map.take(current, &1))
      |> Map.merge(Map.drop(original_changeset.attributes, managed_fields ++ carried_over_fields))

    changeset =
      resource
      |> Ash.Changeset.for_create(WireActions.reinsert_action_name(), attrs,
        actor: context.actor,
        tenant: context.tenant,
        authorize?: false
      )
      |> Ash.Changeset.force_change_attribute(identity_field, Map.fetch!(current, identity_field))
      |> Ash.Changeset.force_change_attribute(
        version_field,
        Map.fetch!(current, version_field) + 1
      )
      |> Ash.Changeset.force_change_attribute(latest_field, true)
      |> Ash.Changeset.force_change_attribute(inserted_at_field, now)
      |> Ash.Changeset.force_change_attribute(updated_at_field, now)
      |> force_change_archived(resource, original_changeset)
      |> force_change_actors(resource, context.actor)
      |> force_readonly_attribute_changes(original_changeset, current, carried_over_fields)

    case Ash.create(changeset, actor: context.actor, tenant: context.tenant, authorize?: false) do
      {:ok, record} -> record
      {:error, error} -> Ash.DataLayer.rollback(resource, error)
    end
  end

  defp archived_field_list(resource) do
    if Info.versioning_archivable?(resource) do
      [Info.versioning_archived_attribute!(resource)]
    else
      []
    end
  end

  defp actor_field_names(resource) do
    resource
    |> Info.versioning()
    |> Enum.filter(&actor_entity?/1)
    |> Enum.map(& &1.attribute_name)
  end

  defp force_change_archived(changeset, resource, original_changeset) do
    if Info.versioning_archivable?(resource) do
      archived_field = Info.versioning_archived_attribute!(resource)
      current_value = Map.get(original_changeset.data, archived_field, false)
      value = Map.get(original_changeset.attributes, archived_field, current_value)
      Ash.Changeset.force_change_attribute(changeset, archived_field, value)
    else
      changeset
    end
  end

  defp force_change_actors(changeset, resource, actor) do
    resource
    |> Info.versioning()
    |> Enum.filter(&actor_entity?/1)
    |> Enum.reduce(changeset, &ActorAttribution.set_actor(&2, &1, actor))
  end

  defp carried_over_readonly_attribute_names(resource, managed_fields) do
    managed = MapSet.new(managed_fields)
    [pk_field] = Ash.Resource.Info.primary_key(resource)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.reject(&(&1.writable? or &1.generated? or &1.name in managed or &1.name == pk_field))
    |> Enum.map(& &1.name)
  end

  defp force_readonly_attribute_changes(changeset, original_changeset, current, field_names) do
    Enum.reduce(field_names, changeset, fn field_name, changeset ->
      value = Map.get(original_changeset.attributes, field_name, Map.fetch!(current, field_name))
      Ash.Changeset.force_change_attribute(changeset, field_name, value)
    end)
  end

  defp actor_entity?(%ReferenceActor{}), do: true
  defp actor_entity?(%BelongsToActor{}), do: true
  defp actor_entity?(_), do: false
end

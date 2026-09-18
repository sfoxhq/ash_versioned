# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Changes.ActorAttribution do
  @moduledoc """
  Ensures that actor attribution is applied to the changeset extracted from
  `context.actor`. See `AshVersioned.ActorValue`, `AshVersioned.Resource.BelongsToActor`,
  `AshVersioned.Resource.ReferenceActor` for more details.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change

  @doc """
  Ensures that actor attribution is applied to the changeset extracted from
  `context.actor` on creation.
  """
  @impl Change
  def change(changeset, opts, context) do
    set_actor(changeset, Keyword.fetch!(opts, :actor_config), context.actor)
  end

  @doc """
  Ensures that actor attribution is applied to the changeset extracted from
  `context.actor` on update, called by `AshVersioned.Resource.ManualIncrement`.
  """
  def set_actor(changeset, actor_config, actor) do
    case AshVersioned.ActorValue.actor_value(actor_config, actor) do
      {:ok, value} ->
        Ash.Changeset.force_change_attribute(changeset, actor_config.attribute_name, value)

      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: actor_config.attribute_name, message: reason)
    end
  end
end

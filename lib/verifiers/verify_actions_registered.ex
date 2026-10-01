# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyActionsRegistered do
  @moduledoc """
  Ensures that every action named in `exclude_update_actions` is a defined update action
  on the resource, and that every action named in `exclude_read_actions` is a defined read
  action.

  All create actions with `upsert?: true` are rejected unconditionally.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    with :ok <- verify_exclusions_exist(dsl_state, :exclude_update_actions),
         :ok <- verify_exclusions_exist(dsl_state, :exclude_read_actions) do
      verify_no_upserting_creates(dsl_state)
    end
  end

  defp verify_exclusions_exist(dsl_state, :exclude_update_actions) do
    verify_exclusions_exist(
      dsl_state,
      :exclude_update_actions,
      Info.versioning_exclude_update_actions!(dsl_state),
      :update
    )
  end

  defp verify_exclusions_exist(dsl_state, :exclude_read_actions) do
    verify_exclusions_exist(
      dsl_state,
      :exclude_read_actions,
      Info.versioning_exclude_read_actions!(dsl_state),
      :read
    )
  end

  defp verify_exclusions_exist(dsl_state, option, exclusions, action_type) do
    action_names =
      dsl_state
      |> Verifier.get_entities([:actions])
      |> Enum.filter(&(&1.type == action_type))
      |> MapSet.new(& &1.name)

    case Enum.reject(exclusions, &MapSet.member?(action_names, &1)) do
      [] ->
        :ok

      stale ->
        names = Enum.map_join(stale, ", ", &inspect/1)
        count = if match?([_], stale), do: "action", else: "actions"

        {:error,
         DslError.exception(
           message: """
           `#{option}` names the following non-existent #{action_type} #{count} which must be fixed or removed: : #{names}
           """,
           path: [:versioning, option],
           module: Verifier.get_persisted(dsl_state, :module)
         )}
    end
  end

  defp verify_no_upserting_creates(dsl_state) do
    case upserting_creates(dsl_state) do
      [] ->
        :ok

      offenders ->
        names = Enum.map_join(offenders, ", ", &inspect(&1.name))
        count = if match?([_], offenders), do: "action", else: "actions"

        {:error,
         DslError.exception(
           message: """
           The following create #{count} are invalid because they attempt to perform an upsert: #{names}.
           """,
           path: [:versioning],
           module: Verifier.get_persisted(dsl_state, :module)
         )}
    end
  end

  defp upserting_creates(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:actions])
    |> Enum.filter(&(&1.type == :create && &1.upsert?))
  end
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyNotDeletable do
  @moduledoc """
  An `AshVersioned.Resource` is not deletable. Resources can be declared with `archive`,
  which turns destroy actions to soft deletions supported by AshVersioned.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    if Info.versioning_archivable?(dsl_state) do
      :ok
    else
      case destroy_actions(dsl_state) do
        [] ->
          :ok

        actions ->
          deletion_not_allowed(dsl_state, actions)
      end
    end
  end

  defp destroy_actions(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:actions])
    |> Enum.filter(&(&1.type == :destroy))
  end

  defp deletion_not_allowed(dsl_state, actions) do
    names = Enum.map_join(actions, ", ", &inspect(&1.name))
    count = if match?([_], actions), do: "action", else: "actions"

    {:error,
     DslError.exception(
       message: """
       Destroy #{count} #{names} are defined, but AshVersioned resources are not \
       deletable. If soft deletions are required, enable it with `archive`.
       """,
       path: [:actions],
       module: Verifier.get_persisted(dsl_state, :module)
     )}
  end
end

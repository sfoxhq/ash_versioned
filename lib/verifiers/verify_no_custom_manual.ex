# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyNoCustomManual do
  @moduledoc """
  AshVersioned does not support resource-supplied `manual` update or destroy action
  implementations.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.Resource.ManualIncrement
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    case manual_actions(dsl_state) do
      [] ->
        :ok

      actions ->
        names = Enum.map_join(actions, ", ", &inspect(&1.name))
        count = if match?([_], actions), do: "Action", else: "Actions"

        {:error,
         DslError.exception(
           message: """
           #{count} #{names} declare `manual`, but AshVersioned resources require \
           strict update implementations which conflicts with resource-defined manual \
           implementations. Either remove `manual` or add it to `exclude_update_actions` \
           if in-place updates are absolutely required.
           """,
           path: [:actions],
           module: Verifier.get_persisted(dsl_state, :module)
         )}
    end
  end

  defp manual_actions(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:actions])
    |> Enum.filter(&custom_manual?/1)
  end

  defp custom_manual?(%{manual: {ManualIncrement, opts}}) when is_list(opts) do
    not is_nil(Keyword.get(opts, :original_manual))
  end

  defp custom_manual?(_), do: false
end

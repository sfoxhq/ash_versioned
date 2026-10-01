# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyCreateActionPresent do
  @moduledoc """
  An `AshVersioned.Resource` resource must declare at least one `create` action.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.Transformers.WireActions
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    if Enum.any?(
         Verifier.get_entities(dsl_state, [:actions]),
         &(&1.type == :create && &1.name != WireActions.reinsert_action_name())
       ) do
      :ok
    else
      {:error,
       DslError.exception(
         message: "This resource has no `:create` action.",
         path: [:actions],
         module: Verifier.get_persisted(dsl_state, :module)
       )}
    end
  end
end

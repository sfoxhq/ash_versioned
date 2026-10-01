# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyNoArchivalConflict do
  @moduledoc """
  `AshArchival.Resource` and `AshVersioned.Resource` cannot be combined.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    if AshArchival.Resource in Spark.extensions(dsl_state) do
      {:error,
       DslError.exception(
         message: """
         This resource has both `AshArchival.Resource` and `AshVersioned.Resource` \
         extensions, which implement incompatible concepts of archival.
         """,
         path: [:extensions],
         module: Verifier.get_persisted(dsl_state, :module)
       )}
    else
      :ok
    end
  end
end

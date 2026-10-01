# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyPrimaryKey do
  @moduledoc """
  An `AshVersioned.Resource` must declare a generated surrogate primary key. AshVersioned
  does not support natural or composite primary keys.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    primary_keys =
      dsl_state
      |> Verifier.get_entities([:attributes])
      |> Enum.filter(& &1.primary_key?)

    case primary_keys do
      [attribute] -> verify_surrogate(dsl_state, attribute)
      [] -> {:error, no_primary_key_error(dsl_state)}
      multiple -> {:error, composite_primary_key_error(dsl_state, multiple)}
    end
  end

  defp verify_surrogate(_dsl_state, %{writable?: false}), do: :ok

  defp verify_surrogate(dsl_state, attribute) do
    {:error,
     DslError.exception(
       message: """
       Primary key attribute `#{attribute.name}` appears to be a natural key. \
       AshVersioned requires a generated surrogate primary key.

       If you meant to specify a business identifier, use `identity` with \
       `origin: :accepted`.
       """,
       path: [:attributes, attribute.name],
       module: Verifier.get_persisted(dsl_state, :module)
     )}
  end

  defp no_primary_key_error(dsl_state) do
    DslError.exception(
      message: """
      This resource has no primary key defined. AshVersioned requires a generated \
      surrogate primary key.
      """,
      path: [:attributes],
      module: Verifier.get_persisted(dsl_state, :module)
    )
  end

  defp composite_primary_key_error(dsl_state, attributes) do
    names = Enum.map_join(attributes, ", ", &inspect(&1.name))

    DslError.exception(
      message: """
      This resource has a composite primary key (#{names}). AshVersioned requires \
      a generated surrogate primary key and has no support for composite identities.
      """,
      path: [:attributes],
      module: Verifier.get_persisted(dsl_state, :module)
    )
  end
end

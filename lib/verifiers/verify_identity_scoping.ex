# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyIdentityScoping do
  @moduledoc """
  Every `identity` on an `AshVersioned.Resource` resource must pass
  `AshVersioned.IdentityScoping.safe?/4`.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.IdentityScoping
  alias AshVersioned.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    identity_field = Info.versioning_identity_attribute(dsl_state)
    version_field = Info.versioning_version_attribute(dsl_state)
    latest_field = Info.versioning_latest_attribute(dsl_state)

    unsafe_identities =
      dsl_state
      |> Verifier.get_entities([:identities])
      |> Enum.reject(&IdentityScoping.safe?(&1, identity_field, version_field, latest_field))

    case unsafe_identities do
      [] ->
        :ok

      [identity | _] ->
        {:error, unsafe_identity_error(dsl_state, identity, identity_field, version_field, latest_field)}
    end
  end

  defp unsafe_identity_error(dsl_state, identity, identity_field, version_field, latest_field) do
    keys = inspect(identity.keys)
    history = inspect(Enum.uniq(identity.keys ++ [identity_field, version_field]))
    name_s = inspect(identity.name)

    DslError.exception(
      message: """
      Identity `#{identity.name}` (#{keys}) is not safely scoped for a versioned resource.

      Identities must match one of these shapes:

        1. Scoped to the current row:

             identity #{name_s}, #{keys}, where: expr(#{latest_field} == true)

           AshVersioned detects when this is used and adds `postgres.identity_wheres_to_sql`
           automatically.

        2. Scoped to the object's full history including both identity and version attributes:

             identity #{name_s}, #{history}

      If `#{keys}` is meant to be unique for the lifetime of the object and never \
      reassigned to a different one, it may be a better fit as the resource's actual \
      `identity` than as a separate business identity.
      """,
      path: [:identities, identity.name],
      module: Verifier.get_persisted(dsl_state, :module)
    )
  end
end

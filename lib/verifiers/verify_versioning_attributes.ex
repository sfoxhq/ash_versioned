# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyVersioningAttributes do
  @moduledoc """
  Verifies every attribute AshVersioned relies on, whether generated or adopted.
  """

  use Spark.Dsl.Verifier

  alias AshVersioned.Resource.Identity
  alias AshVersioned.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @integer_storage_types [:integer, :bigint]
  @boolean_storage_types [:boolean]
  @datetime_storage_types [
    :utc_datetime,
    :utc_datetime_usec,
    :naive_datetime,
    :naive_datetime_usec
  ]
  @generatable_identity_types [:uuid_v7, :uuid]

  # "At most one" for `identity`/`version`/`latest`/`archive`/`reference_actor` is
  # enforced by Spark itself (`singleton_entity_keys` on the `versioning` section,
  # see `AshVersioned.Resource`) — `Spark.Dsl.Verifiers.VerifySectionSingletonEntities`
  # runs that check, so there's nothing to duplicate here.
  @impl Verifier
  def verify(dsl_state), do: verify_attributes(dsl_state)

  defp verify_attributes(dsl_state) do
    with :ok <- verify_identity(dsl_state),
         :ok <- verify_version(dsl_state),
         :ok <- verify_latest(dsl_state),
         :ok <- verify_timestamps(dsl_state) do
      verify_archived_attribute(dsl_state)
    end
  end

  defp verify_identity(dsl_state) do
    identity = Info.versioning_identity(dsl_state)

    with :ok <- verify_generatable(dsl_state, identity),
         {:ok, identity_attribute} <- fetch_attribute(dsl_state, identity.name, :identity),
         :ok <- verify_not_nullable(dsl_state, identity_attribute, :identity) do
      verify_writable(dsl_state, identity_attribute, :identity, identity.origin == :accepted)
    end
  end

  defp verify_version(dsl_state) do
    with {:ok, version_attribute} <-
           fetch_attribute(dsl_state, Info.versioning_version_attribute(dsl_state), :version),
         :ok <- verify_not_nullable(dsl_state, version_attribute, :version),
         :ok <- verify_writable(dsl_state, version_attribute, :version, false) do
      verify_storage_type(dsl_state, version_attribute, :version, @integer_storage_types)
    end
  end

  defp verify_latest(dsl_state) do
    with {:ok, latest_attribute} <-
           fetch_attribute(dsl_state, Info.versioning_latest_attribute(dsl_state), :latest),
         :ok <- verify_not_nullable(dsl_state, latest_attribute, :latest),
         :ok <- verify_writable(dsl_state, latest_attribute, :latest, false) do
      verify_storage_type(dsl_state, latest_attribute, :latest, @boolean_storage_types)
    end
  end

  defp verify_timestamps(dsl_state) do
    with {:ok, create_timestamp_attribute} <-
           fetch_attribute(
             dsl_state,
             Info.versioning_create_timestamp_attribute!(dsl_state),
             :create_timestamp_attribute
           ),
         :ok <-
           verify_not_nullable(dsl_state, create_timestamp_attribute, :create_timestamp_attribute),
         :ok <-
           verify_storage_type(
             dsl_state,
             create_timestamp_attribute,
             :create_timestamp_attribute,
             @datetime_storage_types
           ),
         {:ok, update_timestamp_attribute} <-
           fetch_attribute(
             dsl_state,
             Info.versioning_update_timestamp_attribute!(dsl_state),
             :update_timestamp_attribute
           ),
         :ok <-
           verify_not_nullable(dsl_state, update_timestamp_attribute, :update_timestamp_attribute) do
      verify_storage_type(
        dsl_state,
        update_timestamp_attribute,
        :update_timestamp_attribute,
        @datetime_storage_types
      )
    end
  end

  defp verify_archived_attribute(dsl_state) do
    if Info.versioning_archivable?(dsl_state) do
      with {:ok, archived_attribute} <-
             fetch_attribute(dsl_state, Info.versioning_archived_attribute!(dsl_state), :archived),
           :ok <- verify_not_nullable(dsl_state, archived_attribute, :archived),
           :ok <- verify_writable(dsl_state, archived_attribute, :archived, false) do
        verify_storage_type(dsl_state, archived_attribute, :archived, @boolean_storage_types)
      end
    else
      :ok
    end
  end

  defp verify_generatable(_dsl_state, %Identity{define_attribute?: false}), do: :ok
  defp verify_generatable(_dsl_state, %Identity{origin: :accepted}), do: :ok

  defp verify_generatable(_dsl_state, %Identity{origin: :generated, type: type})
       when type in @generatable_identity_types, do: :ok

  defp verify_generatable(dsl_state, %Identity{type: type}) do
    {:error,
     DslError.exception(
       message: """
       AshVersioned doesn't know how to auto-generate a default value for identity type \
       #{inspect(type)}. Use `:uuid_v7` or `:uuid`, or set `origin :accepted` so the \
       identity is supplied by the caller instead of generated.
       """,
       path: [:versioning, :identity, :type],
       module: Verifier.get_persisted(dsl_state, :module)
     )}
  end

  defp fetch_attribute(dsl_state, name, role) do
    found =
      dsl_state
      |> Verifier.get_entities([:attributes])
      |> Enum.find(&(&1.name == name))

    case found do
      nil -> {:error, missing_error(dsl_state, name, role)}
      attribute -> {:ok, attribute}
    end
  end

  defp verify_not_nullable(_dsl_state, %{allow_nil?: false}, _role), do: :ok

  defp verify_not_nullable(dsl_state, attribute, role),
    do: {:error, shape_error(dsl_state, attribute, role, "allow_nil?: false")}

  defp verify_writable(_dsl_state, %{writable?: writable?}, _role, writable?), do: :ok

  defp verify_writable(dsl_state, attribute, role, expected),
    do: {:error, shape_error(dsl_state, attribute, role, "writable?: #{expected}")}

  defp verify_storage_type(dsl_state, attribute, role, allowed_types) do
    if Ash.Type.storage_type(attribute.type, attribute.constraints) in allowed_types do
      :ok
    else
      {:error,
       shape_error(
         dsl_state,
         attribute,
         role,
         "a type storing as one of #{inspect(allowed_types)}"
       )}
    end
  end

  defp missing_error(dsl_state, name, role) do
    DslError.exception(
      message: """
      The `#{role}` attribute `#{inspect(name)}` doesn't exist on this resource.

      AshVersioned no longer generates this attribute automatically for this role — \
      declare it yourself in `attributes` (or point `#{role}` at your existing column), \
      matching the shape AshVersioned expects.
      """,
      path: [:versioning, role],
      module: Verifier.get_persisted(dsl_state, :module)
    )
  end

  defp shape_error(dsl_state, attribute, role, expectation) do
    DslError.exception(
      message: "The `#{role}` attribute `#{attribute.name}` must have #{expectation}.",
      path: [:versioning, role],
      module: Verifier.get_persisted(dsl_state, :module)
    )
  end
end

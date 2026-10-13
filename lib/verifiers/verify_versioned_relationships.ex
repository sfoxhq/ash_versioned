# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Verifiers.VerifyVersionedRelationships do
  @moduledoc """
  Verifies that every `belongs_to_versioned`, `has_one_versioned`, and
  `has_many_versioned` relationship points to an `AshVersioned.Resource`, and that every
  `belongs_to_versioned` joins on the destination's identity attribute.

  When `through` is used, every relationship in that path that is an
  `AshVersioned.Resource` must be a versioned relationship. A plain relationship to
  a versioned resource matches every version, so aggregates over the path would count each
  related record once per version.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Relationships.BelongsTo
  alias AshVersioned.Resource.Info
  alias AshVersioned.VersionedRelationship
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl Verifier
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:relationships])
    |> Enum.reduce_while(:ok, fn relationship, :ok ->
      case verify_relationship(dsl_state, relationship) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, error(module, relationship, message)}}
      end
    end)
  end

  defp verify_relationship(dsl_state, relationship) do
    with :ok <- verify_through_path(dsl_state, relationship) do
      verify_versioned_relationship(relationship)
    end
  end

  defp verify_versioned_relationship(relationship) do
    if VersionedRelationship.versioned?(relationship) do
      with :ok <- verify_versioned_destination(relationship) do
        verify_destination_attribute(relationship)
      end
    else
      :ok
    end
  end

  defp verify_through_path(dsl_state, relationship) do
    case Map.get(relationship, :through) do
      [_ | _] = path ->
        unversioned_hop =
          dsl_state
          |> expand_through_path(path)
          |> Enum.find(&(versioned_resource?(&1.destination) and not VersionedRelationship.versioned?(&1)))

        verify_hop(unversioned_hop)

      _ ->
        :ok
    end
  end

  defp verify_hop(nil), do: :ok

  defp verify_hop(hop) do
    {:error,
     """
     the `through` path includes #{inspect(hop.name)} on #{inspect(hop.source)}, a \
     relationship to the versioned resource #{inspect(hop.destination)} that is not a \
     versioned relationship. #{versioned_alternative(hop)}
     """}
  end

  defp expand_through_path(dsl_or_resource, path) do
    path
    |> Enum.reduce({dsl_or_resource, []}, fn name, {current, hops} ->
      relationship = Ash.Resource.Info.relationship(current, name)

      case Map.get(relationship, :through) do
        [_ | _] = nested ->
          nested_hops = expand_through_path(current, nested)
          {List.last(nested_hops).destination, hops ++ nested_hops}

        _ ->
          {relationship.destination, hops ++ [relationship]}
      end
    end)
    |> elem(1)
  end

  defp versioned_alternative(%{type: :many_to_many}), do: "Versioned `many_to_many` relationships are not supported."

  defp versioned_alternative(%{type: type, name: name}), do: "Use `#{type}_versioned` for #{inspect(name)}."

  defp versioned_resource?(resource), do: AshVersioned.Resource in Spark.extensions(resource)

  defp verify_versioned_destination(%{destination: destination}) do
    if versioned_resource?(destination) do
      :ok
    else
      {:error, "the destination #{inspect(destination)} is not an `AshVersioned.Resource`."}
    end
  end

  defp verify_destination_attribute(%BelongsTo{} = relationship) do
    identity = Info.versioning_identity_attribute(relationship.destination)

    if relationship.destination_attribute == identity do
      :ok
    else
      {:error,
       """
       `destination_attribute` is #{inspect(relationship.destination_attribute)}, but the \
       identity attribute of #{inspect(relationship.destination)} is #{inspect(identity)}.
       """}
    end
  end

  defp verify_destination_attribute(_relationship), do: :ok

  defp error(module, relationship, message) do
    DslError.exception(
      module: module,
      path: [:relationships, relationship.name],
      message: "Versioned relationship #{inspect(relationship.name)}: #{message}"
    )
  end
end

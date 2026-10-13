# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Transformers.ResolveVersionedRelationships do
  @moduledoc """
  Resolves every `belongs_to_versioned` relationship.

  - An unset `destination_attribute` becomes the versioned resource's identity attribute
    for a self-referential relationship, and `:resource_id` otherwise. Introspection on
    other destinations may cause deadlocks on mutually referential relationships.
  - An ignored `postgres.references` entry is added, as the destination's identity
    attribute is not unique and cannot be the target of a foreign key.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Relationships.BelongsTo
  alias AshVersioned.Resource.Info
  alias AshVersioned.Transformers.AddFields
  alias AshVersioned.VersionedRelationship
  alias Spark.Dsl.Transformer

  @default_destination_attribute :resource_id

  @impl Transformer
  def after?(AddFields), do: true
  def after?(_), do: false

  @impl Transformer
  def transform(dsl) do
    dsl =
      dsl
      |> Transformer.get_entities([:relationships])
      |> Enum.filter(&(match?(%BelongsTo{}, &1) and VersionedRelationship.versioned?(&1)))
      |> Enum.reduce(dsl, fn relationship, dsl ->
        dsl
        |> resolve_destination_attribute(relationship)
        |> VersionedRelationship.ignore_reference(relationship.name)
      end)

    {:ok, dsl}
  end

  defp resolve_destination_attribute(dsl, %{destination_attribute: nil} = relationship) do
    resolved = %{
      relationship
      | destination_attribute: default_destination_attribute(dsl, relationship)
    }

    Transformer.replace_entity(dsl, [:relationships], resolved, &(&1.name == relationship.name))
  end

  defp resolve_destination_attribute(dsl, _relationship), do: dsl

  defp default_destination_attribute(dsl, relationship) do
    if relationship.destination == Transformer.get_persisted(dsl, :module) and
         AshVersioned.Resource in Spark.extensions(dsl) do
      Info.versioning_identity_attribute(dsl)
    else
      @default_destination_attribute
    end
  end
end

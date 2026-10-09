# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.VersionedRelationship do
  @moduledoc """
  Shared configuration for relationships to versioned resources, used by
  `belongs_to_actor` (`AshVersioned.Resource`) and by `belongs_to_versioned`,
  `has_one_versioned`, and `has_many_versioned` (`AshVersioned.Relationships`).

  A relationship to a versioned resource:

  - reads through the destination's `__ash_versioned_read__` action, bypassing archive
    filtering;
  - filters on the destination's `__ash_versioned_latest__` calculation, so that loads,
    aggregates, `exists`, and data layer joins all see only the latest version; and
  - for `belongs_to`, joins on the destination's identity attribute rather than its
    primary key, so it never creates a foreign key (the identity is not unique across
    versions).
  """

  import Ash.Expr

  alias Ash.Resource.Dsl.Filter
  alias Spark.Dsl.Transformer

  @latest_calculation :__ash_versioned_latest__
  @read_action :__ash_versioned_read__
  @marker :__ash_versioned__

  @doc """
  The name of the boolean calculation added to every `AshVersioned.Resource` to filter to
  the latest version of a record.
  """
  def latest_calculation, do: @latest_calculation

  @doc """
  The name of the read action added to every `AshVersioned.Resource`, scoped to the
  latest version of each record, ignoring archiving.
  """
  def read_action, do: @read_action

  @doc "The filter applied to every relationship to a versioned resource."
  def latest_filter, do: %Filter{filter: expr(^ref(@latest_calculation) == true)}

  @doc """
  Options for `Spark.Dsl.Transformer.build_entity!/4` building a `belongs_to` to
  a versioned resource with the given identity attribute.
  """
  def belongs_to_options(identity_attribute) do
    [
      destination_attribute: identity_attribute,
      validate_destination_attribute?: false,
      read_action: @read_action,
      filters: [latest_filter()]
    ]
  end

  @doc """
  Applies the latest filter to a relationship struct before its Ash `transform/1` runs,
  and marks it as a versioned relationship.
  """
  def put_versioned(relationship) do
    relationship
    |> Map.put(:filters, [latest_filter() | relationship.filters || []])
    |> mark()
  end

  @doc """
  Marks a relationship as a versioned relationship, already configured for a versioned
  destination.
  """
  def mark(relationship), do: Map.put(relationship, @marker, true)

  @doc """
  Returns `true` if the relationship was declared with one of the `*_versioned`
  relationship entities, or is a `belongs_to_actor` relationship to a versioned resource.
  """
  def versioned?(relationship), do: Map.get(relationship, @marker, false)

  @doc """
  Adds an ignored `postgres.references` entry for the relationship, so that AshPostgres
  doesn't generate a foreign key to a non-unique identity attribute. Does nothing if the
  data layer isn't AshPostgres or if a reference for the relationship is already declared.
  """
  def ignore_reference(dsl, relationship_name) do
    if Ash.DataLayer.data_layer(dsl) == AshPostgres.DataLayer and
         not reference_declared?(dsl, relationship_name) do
      reference =
        Transformer.build_entity!(AshPostgres.DataLayer, [:postgres, :references], :reference,
          relationship: relationship_name,
          ignore?: true
        )

      Transformer.add_entity(dsl, [:postgres, :references], reference)
    else
      dsl
    end
  end

  defp reference_declared?(dsl, relationship_name) do
    dsl
    |> Transformer.get_entities([:postgres, :references])
    |> Enum.any?(&(&1.relationship == relationship_name))
  end
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# quokka:skip-module-directives
# credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
defmodule AshVersioned.Relationships do
  @moduledoc """
  Adds `belongs_to_versioned`, `has_one_versioned`, and `has_many_versioned` to the
  `relationships` section of any resource for relationships _to_ `AshVersioned.Resource`
  resources.

  ```elixir
  use Ash.Resource,
    extensions: [AshVersioned.Relationships]

  relationships do
    belongs_to_versioned :project, MyApp.Project
  end
  ```

  `AshVersioned.Resource` adds this extension automatically, so it only needs to be
  added on non-versioned resources.

  Each is equivalent to the same Ash relationship that:

  - filters on the latest version of the destination (in loads, aggregates, `exists`,
    and data layer joins alike);
  - reads through the destination's `__ash_versioned_read__` action by default, which
    includes archived records, so a relationship to an archived record still resolves; and
  - for `belongs_to_versioned`, joins on the destination's identity attribute
    (`:resource_id` by default) and never creates a foreign key.

  A destination with a non-default `identity` name requires `destination_attribute` on
  `belongs_to_versioned` (except for self-referential relationships, which use the
  resource's own identity), which is checked once the resources are compiled.

  When the source resource is versioned, `has_one_versioned` and `has_many_versioned`
  should set `source_attribute` to the source's identity attribute, since the
  destination's `belongs_to_versioned` holds the identity rather than the primary key.
  """

  alias Ash.Resource.Relationships.BelongsTo
  alias Ash.Resource.Relationships.HasMany
  alias Ash.Resource.Relationships.HasOne
  alias AshVersioned.VersionedRelationship
  alias Spark.Options.Helpers

  # The versioned entities are derived from Ash's own relationship entities.
  %{entities: ash_entities} = Enum.find(Ash.Resource.Dsl.sections(), &(&1.name == :relationships))

  @ash_belongs_to Enum.find(ash_entities, &(&1.name == :belongs_to))
  @ash_has_one Enum.find(ash_entities, &(&1.name == :has_one))
  @ash_has_many Enum.find(ash_entities, &(&1.name == :has_many))

  @read_action_doc """
  The read action on the destination resource used when loading data and filtering.
  Defaults to `:__ash_versioned_read__`, generated on every versioned resource, which
  returns the latest version of each record whether or not it is archived.
  """

  @destination_attribute_doc """
  The destination's identity attribute. Defaults to `:resource_id`, but self-referential
  relationships to versioned resources resolve automatically.
  """

  versioned_schema = fn schema ->
    schema
    |> Helpers.set_default!(:read_action, VersionedRelationship.read_action())
    |> Keyword.update!(:read_action, &Keyword.put(&1, :doc, @read_action_doc))
  end

  @doc false
  def transform_belongs_to(relationship) do
    relationship
    |> VersionedRelationship.put_versioned()
    |> Map.put(:validate_destination_attribute?, false)
    |> BelongsTo.transform()
  end

  @doc false
  def transform_has_one(relationship) do
    relationship
    |> VersionedRelationship.put_versioned()
    |> HasOne.transform()
  end

  @doc false
  def transform_has_many(relationship) do
    relationship
    |> VersionedRelationship.put_versioned()
    |> HasMany.transform()
  end

  @belongs_to_versioned %{
    @ash_belongs_to
    | name: :belongs_to_versioned,
      describe: """
      Declares a `belongs_to` relationship to the latest version of a versioned resource,
      joined on the destination's identity attribute. No foreign key is created, as the
      identity attribute is not unique across versions.

      Takes the same options as `belongs_to`, except `validate_destination_attribute?`.
      """,
      examples: [
        "belongs_to_versioned :project, MyApp.Project",
        """
        belongs_to_versioned :document, MyApp.Document do
          destination_attribute :document_id
          allow_nil? false
        end
        """
      ],
      schema:
        @ash_belongs_to.schema
        |> Keyword.delete(:validate_destination_attribute?)
        |> Keyword.update!(:destination_attribute, fn opts ->
          opts
          |> Keyword.delete(:default)
          |> Keyword.put(:doc, @destination_attribute_doc)
        end)
        |> versioned_schema.(),
      transform: {__MODULE__, :transform_belongs_to, []}
  }

  @has_one_versioned %{
    @ash_has_one
    | name: :has_one_versioned,
      describe: """
      Declares a `has_one` relationship to the latest version of a versioned resource.

      Takes the same options as `has_one`.
      """,
      examples: [
        "has_one_versioned :customer, MyApp.Customer, destination_attribute: :resource_id",
        """
        has_one_versioned :profile, MyApp.Profile do
          source_attribute :resource_id
        end
        """
      ],
      schema: versioned_schema.(@ash_has_one.schema),
      transform: {__MODULE__, :transform_has_one, []}
  }

  @has_many_versioned %{
    @ash_has_many
    | name: :has_many_versioned,
      describe: """
      Declares a `has_many` relationship to the latest versions of a versioned resource.

      Takes the same options as `has_many`.
      """,
      examples: [
        "has_many_versioned :tasks, MyApp.Task",
        """
        has_many_versioned :tasks, MyApp.Task do
          source_attribute :resource_id
          filter expr(archived == false)
        end
        """
      ],
      schema: versioned_schema.(@ash_has_many.schema),
      transform: {__MODULE__, :transform_has_many, []}
  }

  use Spark.Dsl.Extension,
    dsl_patches: [
      %Spark.Dsl.Patch.AddEntity{section_path: [:relationships], entity: @belongs_to_versioned},
      %Spark.Dsl.Patch.AddEntity{section_path: [:relationships], entity: @has_one_versioned},
      %Spark.Dsl.Patch.AddEntity{section_path: [:relationships], entity: @has_many_versioned}
    ],
    transformers: [AshVersioned.Transformers.ResolveVersionedRelationships],
    verifiers: [AshVersioned.Verifiers.VerifyVersionedRelationships]
end

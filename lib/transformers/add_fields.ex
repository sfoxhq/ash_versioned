# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Transformers.AddFields do
  @moduledoc """
  Resolves the `AshVersioned.Resource` entities for `identity`, `version`, `latest`, and
  (optionally) `archived`. For the required versioning attributes, defaults are provided
  if not declared. These are used to configure the resource for versioning, defining the
  attributes and default read scopes.

  Existing attributes will be adopted from the `attributes` section of the resource when
  `define_attribute?` is `false` or if there is an attribute that matches the declared or
  default name. Adopted attributes _may_ fail verification.
  """

  use Spark.Dsl.Transformer

  import Ash.Expr

  alias Ash.Resource.Builder
  alias Ash.Resource.Dsl
  alias Ash.Resource.Transformers.BelongsToAttribute
  alias AshVersioned.IdentityScoping
  alias AshVersioned.Preparations.FilterLatest
  alias AshVersioned.Resource.Archive
  alias AshVersioned.Resource.BelongsToActor
  alias AshVersioned.Resource.Identity
  alias AshVersioned.Resource.Info
  alias AshVersioned.Resource.Latest
  alias AshVersioned.Resource.ReferenceActor
  alias AshVersioned.Resource.Version
  alias Spark.Dsl.Transformer

  @impl Transformer
  def before?(BelongsToAttribute), do: true
  def before?(_), do: false

  # sobelow_skip ["DOS.BinToAtom"]
  @impl Transformer
  def transform(dsl) do
    archive = Info.versioning_archive(dsl)
    source_prefix = Transformer.get_option(dsl, [:versioning], :source_prefix)

    {identity, dsl} = resolve_singleton(dsl, Identity)
    {version, dsl} = resolve_singleton(dsl, Version)
    {latest, dsl} = resolve_singleton(dsl, Latest)

    identity_field = identity.name
    latest_field = latest.name

    # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
    current_identity_field = :"current_#{identity_field}"
    full_history_identity_field = :"full_history_#{identity_field}"

    current_identity =
      Transformer.build_entity!(Dsl, [:identities], :identity,
        name: current_identity_field,
        keys: [identity_field],
        where: expr(^ref(latest_field) == true)
      )

    full_history_identity =
      Transformer.build_entity!(Dsl, [:identities], :identity,
        name: full_history_identity_field,
        keys: [identity_field, version.name]
      )

    with {:ok, dsl} <- maybe_add_identity_attribute(dsl, identity, source_prefix),
         {:ok, dsl} <- maybe_add_attribute(dsl, version, :integer, source_prefix, default: 0),
         {:ok, dsl} <- maybe_add_attribute(dsl, latest, :boolean, source_prefix, default: true),
         {:ok, dsl} <- maybe_add_archived_attribute(dsl, archive, source_prefix) do
      dsl =
        dsl
        |> Transformer.add_entity([:identities], current_identity)
        |> Transformer.add_entity([:identities], full_history_identity)
        |> add_postgres_identity_wheres(latest_field)
        |> add_actor_fields()

      Builder.add_preparation(dsl, {FilterLatest, []})
    end
  end

  defp default(Identity), do: %Identity{name: :resource_id, define_attribute?: true, origin: :generated, type: :uuid_v7}

  defp default(Version), do: %Version{name: :version_number, define_attribute?: true}
  defp default(Latest), do: %Latest{name: :latest_version, define_attribute?: true}

  defp resolve_singleton(dsl, module) do
    if entity = Info.versioning_entity(dsl, module) do
      {entity, dsl}
    else
      default_module = default(module)
      {default_module, Transformer.add_entity(dsl, [:versioning], default_module)}
    end
  end

  # coveralls-ignore-next-line # Exercised at compile time.
  defp maybe_add_identity_attribute(dsl, %Identity{define_attribute?: false}, _source_prefix), do: {:ok, dsl}

  defp maybe_add_identity_attribute(dsl, %Identity{} = identity, source_prefix) do
    Builder.add_new_attribute(dsl, identity.name, identity.type,
      allow_nil?: false,
      writable?: identity.origin == :accepted,
      public?: true,
      default: identity_default_fn(identity),
      source: resolve_source(identity, source_prefix)
    )
  end

  defp add_actor_fields(dsl) do
    dsl
    |> Info.versioning_entities([ReferenceActor, BelongsToActor])
    |> Enum.reduce(dsl, &add_actor_field(&2, &1))
  end

  # coveralls-ignore-next-line # Exercised at compile time.
  defp identity_default_fn(%{origin: :accepted}), do: nil
  defp identity_default_fn(%{type: :uuid_v7}), do: &Ash.UUIDv7.generate/0
  # coveralls-ignore-next-line # Exercised at compile time.
  defp identity_default_fn(%{type: :uuid}), do: &Ash.UUID.generate/0
  defp identity_default_fn(_), do: nil

  defp maybe_add_attribute(dsl, %{define_attribute?: false}, _type, _source_prefix, _opts) do
    {:ok, dsl}
  end

  defp maybe_add_attribute(dsl, attribute, type, source_prefix, opts) do
    source = resolve_source(attribute, source_prefix)
    opts = Keyword.merge(opts, allow_nil?: false, writable?: false, public?: true, source: source)

    Builder.add_new_attribute(dsl, attribute.name, type, opts)
  end

  defp maybe_add_archived_attribute(dsl, nil, _source_prefix), do: {:ok, dsl}

  defp maybe_add_archived_attribute(dsl, %Archive{define_attribute?: false}, _source_prefix), do: {:ok, dsl}

  defp maybe_add_archived_attribute(dsl, %Archive{attribute: name, source: source}, source_prefix) do
    # coveralls-ignore-next-line # Exercised at compile time.
    Builder.add_new_attribute(dsl, name, :boolean,
      allow_nil?: false,
      writable?: false,
      public?: true,
      default: false,
      source: resolve_source(name, source, source_prefix)
    )
  end

  defp resolve_source(attribute, source_prefix), do: resolve_source(attribute.name, attribute.source, source_prefix)

  defp resolve_source(_name, nil, nil), do: nil
  # coveralls-ignore-start # Exercised at compile time.
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp resolve_source(name, nil, source_prefix), do: :"#{source_prefix}#{name}"
  defp resolve_source(_name, source, _source_prefix), do: source
  # coveralls-ignore-stop

  # coveralls-ignore-start # Exercised at compile time.
  defp add_actor_field(dsl, %ReferenceActor{} = actor) do
    resolved_actor = %{actor | attribute_name: actor.name}

    attribute =
      Transformer.build_entity!(Dsl, [:attributes], :attribute,
        name: actor.name,
        type: :string,
        allow_nil?: actor.allow_nil?,
        writable?: false,
        public?: actor.public?
      )

    dsl
    |> Transformer.replace_entity([:versioning], resolved_actor, &same_actor?(&1, actor))
    |> Transformer.add_entity([:attributes], attribute)
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp add_actor_field(dsl, %BelongsToActor{} = actor) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    attribute_name = :"#{actor.name}_id"

    {destination_attribute, validate_destination_attribute?, read_action, filters} =
      if AshVersioned.Resource in Spark.extensions(actor.destination) do
        latest_field = Info.versioning_latest_attribute(actor.destination)

        latest_filter =
          Transformer.build_entity!(Dsl, [:relationships, :belongs_to], :filter,
            filter: expr(^ref(latest_field) == true)
          )

        # Reads through `history_action` (which `FilterLatest` always exempts) rather than
        # the primary read action, so an archived actor still resolves — they're still the
        # one who touched this version. `latest_filter` alone then narrows it back to
        # exactly one row.
        history_action = Info.versioning_history_action!(actor.destination)

        {Info.versioning_identity_attribute(actor.destination), false, history_action, [latest_filter]}
      else
        {:id, true, nil, []}
      end

    resolved_actor = %{
      actor
      | attribute_name: attribute_name,
        destination_attribute: destination_attribute,
        validate_destination_attribute?: validate_destination_attribute?
    }

    relationship =
      Transformer.build_entity!(Dsl, [:relationships], :belongs_to,
        name: actor.name,
        destination: actor.destination,
        domain: actor.domain,
        define_attribute?: actor.define_attribute?,
        source_attribute: attribute_name,
        destination_attribute: destination_attribute,
        validate_destination_attribute?: validate_destination_attribute?,
        attribute_type: actor.attribute_type,
        allow_nil?: actor.allow_nil?,
        attribute_writable?: false,
        public?: actor.public?,
        read_action: read_action,
        filters: filters
      )

    dsl
    |> Transformer.replace_entity([:versioning], resolved_actor, &same_actor?(&1, actor))
    |> Transformer.add_entity([:relationships], relationship)
    |> add_reference(resolved_actor)
  end

  # coveralls-ignore-stop

  defp same_actor?(%struct{name: name}, %struct{name: name}), do: true
  defp same_actor?(_, _), do: false

  # coveralls-ignore-start # Exercised at compile time.
  defp add_reference(dsl, %BelongsToActor{define_attribute?: false}), do: dsl

  defp add_reference(dsl, %BelongsToActor{destination_attribute: :id} = actor) do
    if Ash.DataLayer.data_layer(dsl) == AshPostgres.DataLayer do
      reference =
        Transformer.build_entity!(AshPostgres.DataLayer, [:postgres, :references], :reference,
          relationship: actor.name,
          on_delete: actor.on_delete,
          on_update: :update
        )

      Transformer.add_entity(dsl, [:postgres, :references], reference)
    else
      dsl
    end
  end

  defp add_reference(dsl, %BelongsToActor{} = actor) do
    if Ash.DataLayer.data_layer(dsl) == AshPostgres.DataLayer do
      reference =
        Transformer.build_entity!(AshPostgres.DataLayer, [:postgres, :references], :reference,
          relationship: actor.name,
          ignore?: true
        )

      Transformer.add_entity(dsl, [:postgres, :references], reference)
    else
      dsl
    end
  end

  # coveralls-ignore-stop

  # Auto-populates `postgres.identity_wheres_to_sql` for *every* identity scoped to
  # "latest == true" (`IdentityScoping.scoped_to_latest?/2`). This must be created as SQL,
  # not an Ash expression, since it's being applied to the index construction in
  # AshPostgres.
  defp add_postgres_identity_wheres(dsl, latest_field) do
    if Ash.DataLayer.data_layer(dsl) == AshPostgres.DataLayer do
      # coveralls-ignore-start # Exercised with migration generation.

      existing = Transformer.get_option(dsl, [:postgres], :identity_wheres_to_sql, [])
      latest_column = attribute_source(dsl, latest_field)

      sql =
        dsl
        |> Transformer.get_entities([:identities])
        |> Enum.filter(&IdentityScoping.scoped_to_latest?(&1, latest_field))
        |> Enum.reduce(existing, fn identity, sql ->
          Keyword.put_new(sql, identity.name, "#{latest_column} = true")
        end)

      Transformer.set_option(dsl, [:postgres], :identity_wheres_to_sql, sql)
      # coveralls-ignore-stop
    else
      dsl
    end
  end

  # coveralls-ignore-start # Exercised with migration generation.
  defp attribute_source(dsl, name) do
    attribute =
      dsl
      |> Transformer.get_entities([:attributes])
      |> Enum.find(&(&1.name == name))

    case attribute do
      %{source: source} when is_nil(source) -> name
      %{source: source} -> source
      nil -> name
    end
  end

  # coveralls-ignore-stop
end

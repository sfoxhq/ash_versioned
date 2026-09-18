# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# quokka:skip-module-directives
# credo:disable-for-this-file Credo.Check.Readability.StrictModuleLayout
defmodule AshVersioned.Resource do
  @moduledoc """
  Configures a resource for versioning. The source table gets a stable resource
  identifier, a version number, and a flag marking a row as the latest version, and
  mutations append new rows instead of updating in place.

  Versioned resources must already have the following fields declared in `attributes`.

  - A surrogate primary key (`uuid_v7_primary_key`, `integer_primary_key`, or one already
    on a ported table). Composite keys are not supported.
  - Create and update timestamps (usually `:inserted_at` and `:updated_at`) with any
    non-null datetime-family attribute.
  """

  @identity %Spark.Dsl.Entity{
    name: :identity,
    describe: """
    Configures the identity held by every version of the same versioned resource;
    a "logical" primary key.

    If omitted, this is equivalent to `identity :resource_id`.
    """,
    examples: [
      "identity :resource_id",
      """
      identity do
        origin :accepted
      end
      """,
      "identity :resource_id, origin: :accepted",
      """
      identity :mo_id do
        define_attribute? false
      end
      """
    ],
    target: AshVersioned.Resource.Identity,
    args: [{:optional, :name, :resource_id}],
    schema: [
      name: [
        type: :atom,
        default: :resource_id,
        doc: "The name of the identity attribute."
      ],
      define_attribute?: [
        type: :boolean,
        default: true,
        doc: """
        If set to `false`, the identity attribute is not created and one must be manually
        added to `attributes`, invalidating many other options.
        """
      ],
      origin: [
        type: {:one_of, [:generated, :accepted]},
        default: :generated,
        doc: """
        If not set or set as `:generated`, the value of the identity is generated on
        resource creation.

        If set to `:accepted`, the identity is an accepted parameter on every create
        action.
        """
      ],
      type: [
        type: :any,
        default: :uuid_v7,
        doc: """
        The type of the generated attribute. See `Ash.Type` for more details.

        Types other than `:uuid` and `:uuid_v7` require that `origin` be set to
        `:accepted`.
        """
      ],
      source: [
        type: :atom,
        doc: "The name of the field on the underlying data layer."
      ]
    ]
  }

  @version %Spark.Dsl.Entity{
    name: :version,
    describe: """
    Configures the monotonically increasing version number, starting at 0.

    If omitted, this is equivalent to `version :version_number`.
    """,
    examples: [
      "version :version_number",
      """
      version :mo_version do
        define_attribute? false
      end
      """
    ],
    target: AshVersioned.Resource.Version,
    args: [{:optional, :name, :version_number}],
    schema: [
      name: [
        type: :atom,
        default: :version_number,
        doc: "The name of the version attribute."
      ],
      define_attribute?: [
        type: :boolean,
        default: true,
        doc: """
        If set to `false`, the version attribute is not created and one must be manually
        added to `attributes`, invalidating many other options.
        """
      ],
      source: [
        type: :atom,
        doc: "The name of the field on the underlying data layer."
      ]
    ]
  }

  @latest %Spark.Dsl.Entity{
    name: :latest,
    describe: """
    Configures the boolean flag marking the current version for this resource.

    If omitted, this is equivalent to `latest :latest_version`.
    """,
    examples: [
      "latest :latest_version",
      """
      latest :mo_is_latest do
        define_attribute? false
      end
      """
    ],
    target: AshVersioned.Resource.Latest,
    args: [{:optional, :name, :latest_version}],
    schema: [
      name: [
        type: :atom,
        default: :latest_version,
        doc: "The name of the latest attribute."
      ],
      define_attribute?: [
        type: :boolean,
        default: true,
        doc: """
        If set to `false`, the latest attribute is not created and one must be manually
        added to `attributes`, invalidating many other options.
        """
      ],
      source: [
        type: :atom,
        doc: "The name of the field on the underlying data layer."
      ]
    ]
  }

  @reference_actor %Spark.Dsl.Entity{
    name: :reference_actor,
    describe: """
    Creates a `:string` attribute for storing the actor responsible for resource version
    creation.

    `reference_actor` can be used when the actor field holds heterogeneous ID spaces
    (admin, customer, or sentinel values like `"system"`) that may not resolve
    to Ash resources. It works best with prefixed object ID strings (`admin_QweRTy`,
    `customer_Dv0rAk`, etc.).

    For more than one possible Ash resource actor type, use `belongs_to_actor` instead,
    which discriminates by the actor type.
    """,
    examples: [
      "reference_actor :created_by",
      "reference_actor :created_by, transform: &MyApp.actor_reference/1"
    ],
    target: AshVersioned.Resource.ReferenceActor,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the attribute to use for the actor."
      ],
      transform: [
        type: {:mfa_or_fun, 1},
        default: &AshVersioned.ReferenceActorValue.value_for/1,
        doc: """
        A function or `{module, function, args}` to transform the actor into a suitable
        string reference. The default is `AshVersioned.ReferenceActorValue.value_for/1`.
        Use a different function when support for composite primary keys, prefixed keys,
        or some other requirement arises.
        """
      ],
      allow_nil?: [
        type: :boolean,
        default: true,
        doc: "Whether this attribute can be nil."
      ],
      public?: [
        type: :boolean,
        default: false,
        doc: "Whether this attribute should be shown over public interfaces."
      ]
    ]
  }

  @belongs_to_actor %Spark.Dsl.Entity{
    name: :belongs_to_actor,
    describe: """
    Creates a `belongs_to` relationship to the actor resource. When creating a new
    version, associates the action's actor with the matching resource type. For
    polymorphic or variant types, declare a `belongs_to_actor` for each type.

    If your actor is not a resource, consider using `reference_actor` instead.
    """,
    examples: [
      "belongs_to_actor :edited_by, MyApp.Users.Author",
      "belongs_to_actor :reviewed_by, MyApp.Users.Author, domain: MyApp.Users"
    ],
    target: AshVersioned.Resource.BelongsToActor,
    no_depend_modules: [:destination, :domain],
    args: [:name, :destination],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the relationship to use for the actor."
      ],
      allow_nil?: [
        type: :boolean,
        default: true,
        doc: """
        Whether this relationship must always be present. The generated attribute will not
        allow nil values.
        """
      ],
      domain: [
        type: :atom,
        doc: "The Domain module to use when working with the related entity."
      ],
      attribute_type: [
        type: :any,
        default: Application.compile_env(:ash, :default_belongs_to_type, :uuid),
        doc: "The type of the generated attribute. See `Ash.Type` for more."
      ],
      public?: [
        type: :boolean,
        default: false,
        doc: "Whether this relationship should be included in public interfaces"
      ],
      define_attribute?: [
        type: :boolean,
        default: true,
        doc: """
        If set to `false`, an attribute is not created on the resource for this
        relationship, and one must be manually added in `attributes`, invalidating many
        other options.
        """
      ],
      destination: [
        type: Ash.OptionsHelpers.ash_resource(),
        required: true,
        doc: "The resource of the actor (e.g. MyApp.Users.User)"
      ],
      on_delete: [
        type:
          {:or,
           [
             {:one_of, [:delete, :nilify, :nothing, :restrict]},
             {:tagged_tuple, :nilify, {:wrap_list, :atom}}
           ]},
        default: :nothing,
        doc: """
        The action to take on this row when the actor is deleted. Can also be `{:nilify,
        columns}` to nilify specific columns (Postgres 15+ only). Only relevant for
        resources using a SQL data layer.

        Has no impact when `destination` is an `AshVersioned.Resource`.
        """
      ]
    ]
  }

  @archive %Spark.Dsl.Entity{
    name: :archive,
    describe: """
    Declares this resource archivable, which makes every destroy action a `soft?: true`
    destroy action.

    If not set, defining destroy actions on the resource is a compile error.
    """,
    examples: [
      "archive :archived",
      """
      archive do
        action :discard
      end
      """
    ],
    target: AshVersioned.Resource.Archive,
    args: [{:optional, :attribute, :archived}],
    schema: [
      attribute: [
        type: :atom,
        default: :archived,
        doc: "The name of the boolean attribute marking a version as archived."
      ],
      define_attribute?: [
        type: :boolean,
        default: true,
        doc: """
        If set to `false`, the archived attribute is not created and one must be manually
        added to `attributes`, invalidating many other options.
        """
      ],
      action: [
        type: {:or, [:atom, {:literal, false}]},
        default: :archive,
        doc: """
        The name of a generated default destroy action, created using this name unless a
        destroy action is already defined (regardless of its name). Set to `false` to skip
        generating it unconditionally.
        """
      ],
      read_action: [
        type: {:or, [:atom, {:literal, false}]},
        default: :get_with_archived,
        doc: """
        The name of a generated `get_by` read action that returns the latest version of
        a resource by its identity attribute, whether or not it's archived. This action is
        scoped to return the latest version of a resource. Skipped if an action with this
        name is already defined. Set to `false` to skip generating it unconditionally.
        """
      ],
      unarchive: [
        type: {:or, [:atom, {:literal, false}]},
        default: :unarchive,
        doc: """
        The name of a generated update action that sets the archived to `false`, accepting
        no input. Skipped if an action with this name is already defined. Set to `false`
        to skip generating it unconditionally.
        """
      ],
      exclude_read_actions: [
        type: {:list, :atom},
        default: [],
        doc: """
        Additional read actions (beyond `read_action`) that should skip the filtering
        archived resources while still respecting the latest version filtering. An
        action name only needs to appear here or in the top-level `exclude_read_actions`,
        not both.
        """
      ],
      source: [
        type: :atom,
        doc: "The name of the field on the underlying data layer."
      ]
    ]
  }

  @versioning %Spark.Dsl.Section{
    name: :versioning,
    describe: "Configures SCD (type 2) version tracking on this resource.",
    entities: [@identity, @version, @latest, @archive, @reference_actor, @belongs_to_actor],
    singleton_entity_keys: [:identity, :version, :latest, :archive, :reference_actor],
    schema: [
      create_timestamp_attribute: [
        type: :atom,
        default: :inserted_at,
        doc: """
        The name of the timestamp attribute used when inserting a new version. This
        reflects when this version became active. The attribute must already be defined in
        `attributes`.
        """
      ],
      update_timestamp_attribute: [
        type: :atom,
        default: :updated_at,
        doc: """
        The name of the timestamp attribute updated when a version is marked stale. This
        reflects when this version became inactive. The attribute must already be defined
        in `attributes`.
        """
      ],
      exclude_update_actions: [
        type: {:list, :atom},
        default: [],
        doc: """
        Update actions intentionally left as ordinary in-place updates instead of
        appending a new version. Every other update action on the resource is wired to
        append automatically.

        WARNING: This should _only_ be used in exceptional circumstances, because it
        breaks the core promise of SCD (type 2) versioning: inactive versions don't
        change.
        """
      ],
      exclude_read_actions: [
        type: {:list, :atom},
        default: [],
        doc: """
        Read actions that should skip the default latest (and archived) scoping applied to
        every other read action. This could include hand-declared audit or admin-facing
        actions that need to see stale and archived versions.
        """
      ],
      history_action: [
        type: :atom,
        default: :version_history,
        doc: """
        The name of the generated read action that returns every version, ignoring the
        default latest/archived scoping.
        """
      ],
      source_prefix: [
        type: :string,
        doc: """
        If specified, this prefix is applied to the underlying `source` of the generated
        AshVersioned fields. Fields adopting defined fields (`define_attribute? false`) or
        that declare `source` ignore this setting.

        ```elixir
        versioning do
          archive()
          source_prefix "vo_"
        end
        ```

        This is equivalent to:

        ```elixir
        versioning do
          archive :archived, source: :vo_archived
          identity :resource_id, source: :vo_resource_id
          latest :latest_version, source: :vo_latest_version
          version :version_number, source: :vo_version_number
        end
        ```

        The prefix is applied in front of _any_ name given, so `identity :mo_id` would
        become `identity :mo_id, source: :vo_mo_id`.
        """
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@versioning],
    transformers: [
      AshVersioned.Transformers.AddFields,
      AshVersioned.Transformers.WireActions
    ],
    verifiers: [
      AshVersioned.Verifiers.VerifyCreateActionPresent,
      AshVersioned.Verifiers.VerifyActionsRegistered,
      AshVersioned.Verifiers.VerifyNoCustomManual,
      AshVersioned.Verifiers.VerifyNotDeletable,
      AshVersioned.Verifiers.VerifyPrimaryKey,
      AshVersioned.Verifiers.VerifyVersioningAttributes,
      AshVersioned.Verifiers.VerifyIdentityScoping,
      AshVersioned.Verifiers.VerifyNoArchivalConflict
    ]
end

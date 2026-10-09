<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

# Options

AshVersioned offers extended capabilities for common requirements.

## Resource archival

AshVersioned does not allow [destroy actions to be defined][no-deletions],
unless `archive` is specified in the `versioning` section. This removes the
restriction and marks every destroy action as `soft?: true`[^1] and ensures
that each sets `archived: true` through a normal versioned update. The
`archive` attribute also defines:

- `archive`: a destroy action that sets `archived: true`
- `get_with_archived`: a read action that ignores the `archived` attribute
- `unarchive`: an update action that sets `archived: false`

All three can be renamed or disabled (`false`). The default destroy action is
skipped if **any** destroy action already exists on the resource; the read and
update actions are skipped if actions with the configured names already exist.

```elixir
versioning do
  archive()
end

archived =
  widget
  |> Ash.Changeset.for_destroy(:archive, %{})
  |> Ash.destroy!(return_destroyed?: true)

archived.archived == true
# nothing was destroyed — archived rows remain fully visible through
# version_history, they just drop out of ordinary reads.

unarchived =
  MyApp.Widget
  |> Ash.Query.for_read(:get_with_archived, %{resource_id: widget.resource_id})
  |> Ash.read_one!()
  |> Ash.Changeset.for_update(:unarchive, %{})
  |> Ash.update!()

unarchived.archived == false
```

There may be additional fields that need to be updated, so it's possible to
define your own variants (if you name them the same as the defaults, you do
not need to specify `false`).

```elixir
versioning do
  archive do
    action false # implied with the creation of the `delete` action
    unarchive false # required to prevent the creation of `:unarchive`
  end
end

actions do
  destroy :delete do
    accept []
    change set_attribute(:inventory, 0)
  end

  update :undelete do
    accept []
    change set_attribute(:archived, false)
  end
end
```

A hand-written read action that isn't named `get_with_archived` needs to be
added to `archive.exclude_read_actions` to get the same archived-agnostic
scoping. This is a different list from the top-level `exclude_read_actions`,
which bypasses scoping entirely and would require writing
`latest_version == true` into the filter yourself:

```elixir
versioning do
  archive do
    exclude_read_actions [:get_only_archived]
  end
end

actions do
  read :get_only_archived do
    argument :resource_id, :uuid, allow_nil?: false
    get? true
    filter expr(resource_id == ^arg(:resource_id) and archived == true)
  end
end
```

## Building relationships to versioned resources

Ash resource `belongs_to` relationships pointed to a versioned resource would
point to a specific resource _version_. In most cases, this is not what is
desired, so they should be built to reference the resource identity
(`resource_id`) and the _current_ version. The `AshVersioned.Relationships`
extension adds `belongs_to_versioned`, `has_one_versioned`, and
`has_many_versioned` to the `relationships` section of any resource.
AshVersioned resources include `AshVersioned.Relationships` automatically.

```elixir
use Ash.Resource,
  extensions: [AshVersioned.Relationships]

relationships do
  belongs_to_versioned :project, MyApp.Project
end
```

Each `*_versioned` relationship takes the same options and generates the same
relationship as its Ash equivalent with versioned resource options applied.
`belongs_to_versioned :project, MyApp.Project` is roughly equivalent to:

```elixir
relationships do
  belongs_to :project, MyApp.Project do
    destination_attribute :resource_id
    validate_destination_attribute? false
    read_action :__ash_version_read__
    filter expr(__ash_version_latest__ == true)
  end
end

postgres do
  references do
    reference :project, ignore?: true
  end
end
```

- `destination_attribute :resource_id` points the relationship at the
  versioned resource identity, not `:id`. If your versioned resource identity
  is not `resource_id`, set it appropriately:

  ```elixir
  belongs_to_versioned :project, MyApp.Project, destination_attribute: :mo_id
  ```

  The destination attribute name is checked at compile time and is not
  required for self-references.

- `validate_destination_attribute? false` prevents validation, which is
  required because versioned resources are unique using a _partial_ index not
  satisfying Ash's built-in destination attribute checks. Similarly, we have
  to ignore the PostgreSQL foreign key reference. These cannot be removed.

- `read_action :__ash_version_read__` routes the relationship through a
  reserved read action that returns the latest version of each record
  (ignoring any archived status). This avoids the primary read (which excludes
  archived rows by default), preventing archived resources from being treated
  as missing relationships.

  This can be replaced, but be aware that any read action that filters archive
  may cause archived references to be treated as omitted.

> `__ash_version_read__` and `__ash_version_latest__` are added to every
> versioned resource so that relationships can be built without knowing the
> destination's configuration (its `history_action` or `latest` attribute
> names). Both names are reserved, and declaring either on a versioned
> resource is a compile error.

### Relationships _from_ versioned resources

`has_one_versioned` and `has_many_versioned` describe the `belongs_to` on the
other side. When the source is versioned, the destination holds the source's
identity rather than its primary key, so `source_attribute` must be set:

```elixir
# MyApp.Task
relationships do
  belongs_to_versioned :project, MyApp.Project
end

# MyApp.Project
relationships do
  has_many_versioned :tasks, MyApp.Task do
    source_attribute :resource_id
  end
end
```

Archived records are included; relationship to an archived record is still
valid. Exclude them with an additional relationship filter combined with the
generated one:

```elixir
has_many_versioned :active_tasks, MyApp.Task do
  source_attribute :resource_id
  destination_attribute :project_id
  filter expr(archived == false)
end
```

> When using `:through` paths, every relationship in that path which uses a
> versioned resource must be a versioned relationship. AshVersioned enforces
> this.

## Actor attribution

AshVersioned provides two options for recording the actor responsible for each
version's changes, set from `context.actor`.

```elixir
versioning do
  belongs_to_actor :edited_by, MyApp.Author
  reference_actor :created_by
end
```

- **`belongs_to_actor`** generates a real `belongs_to` relationship to the
  destination actor resource, reachable directly after a preload. Use it when
  you want to traverse to the actor.

- **`reference_actor`** adds a plain `string` attribute instead. Use it when
  the field can hold heterogeneous IDs (an admin ID, a customer ID, an ID from
  another service, an email address, or a sentinel like `"system"`). If
  `context.actor` is an Ash resource, its primary key or `AshVersioned`
  resource identity attribute is used; anything else must implement
  `String.Chars`.

A resource can declare more than one `belongs_to_actor` field for different
actor types. Only the relationship matching the actor's actual resource type
gets set:

```elixir
versioning do
  belongs_to_actor :edited_by, MyApp.Author
  belongs_to_actor :reviewed_by, MyApp.Reviewer
end
```

Creating with an `Author` actor sets `edited_by_id` and leaves
`reviewed_by_id` as `nil`; creating with a `Reviewer` actor does the reverse.
Both fields exist on every row regardless of which kind of actor made it.

If the actor itself is an `AshVersioned.Resource`, both `belongs_to_actor` and
`reference_actor` resolve the identity attribute rather than its primary key,
so attribution stays correct across the actor's own versions, even if the
actor has since been archived.

Attribution happens only when there is a change that updates the record. If
you need to force a version bump purely to set actor attribution, drive it
through a real (if trivial) attribute change:

```elixir
attributes do
  attribute :touch_nonce, :uuid, public?: false, writable?: true
end

actions do
  update :touch do
    accept []

    change fn changeset, _ ->
      Ash.Changeset.force_change_attribute(changeset, :touch_nonce, Ash.UUID.generate())
    end
  end
end
```

## Additional and Alternative Identities

Some business requirements want a secondary unique key (separate from the
resource identifier); these could be serial numbers, external references, or
product codes. AshVersioned supports secondary unique keys, but it's important
that any `identity` added to enforce this uniqueness is properly scoped to
`latest_version`. Without this, this `identity` is _guaranteed_ to break on
the first resource mutation containing the identity.

```elixir
attributes do
  attribute :legacy_code, :string, public?: true, allow_nil?: false
end

identities do
  identity :unique_legacy_code, [:legacy_code]
end
```

Remember that old rows aren't deleted or modified[^1] under a mutation but
duplicated _then_ modified. The `legacy_code` uniqueness constraint would be
broken before the mutation transaction completes. Instead, remember to scope
to the `latest_version` (no need to add `postgres.identity_wheres_to_sql` for
this identity; AshVersioned detects this shape and supplies the appropriate
SQL).

```elixir
identities do
  identity :unique_legacy_code, [:legacy_code], where: expr(latest_version == true)
end
```

If the additional identity can move from one resource to another (SKUs or UPCs
are sometimes reused in retail environments), it's advisable to define a full
history identity that is a superset of the full history identity provided by
AshVersioned for all resources:

```elixir
identities do
  identity :full_history_legacy_code, [:legacy_code, :version_number, :resource_id]
end
```

Both `version_number` and `resource_id` must be part of this `identity` to
ensure that the identity migration works. (The order of the columns in the
identity may assist with partial full history lookups.)

### Consider `identity … origin: :accept`

It's worth considering whether the identity is a _natural_ key and not a
_secondary_ unique key. AshVersioned provides a better way for natural keys to
be used as resource identities:

```elixir
versioning do
  identity :code, type: :string, origin: :accept
end
```

All `create` actions will be modified to accept the resource identity value,
which will be copied forward on update actions.

#### No upsert support

AshVersioned does not support upsert actions[^2] and they are prevented at
both compile and runtime. Natural resource identities (`origin: :accepted`)
often need create-or-update semantics.

The replacement for upsert behaviour is a manual implementation. Look the
object up by its identity attribute, then call a create action if it wasn't
found or an update action if it was.

```elixir
Ash.transact(MyApp.Widget, fn ->
  case Ash.get(MyApp.Widget, resource_id: resource_id) do
    {:ok, widget} ->
      widget
      |> Ash.Changeset.for_update(:increment, params)
      |> Ash.update()

    {:error, %Ash.Error.Query.NotFound{}} ->
      MyApp.Widget
      |> Ash.Changeset.for_create(:create, params)
      |> Ash.create()

    {:error, reason} ->
      {:error, reason}
  end
end)
```

There may be a race condition when two concurrent processes both take the "not
found" branch for the same not-yet-existing identity. If you need this pattern
under concurrent writers, handle duplicate-identity failure on create as an
expected condition rather than a fatal error.

## Porting an existing SCD type 2 table

Use `define_attribute? false` on `identity`, `version`, or `latest` to adopt
an attribute you've already declared, under whatever name and type it already
has, instead of having `AshVersioned` generate one. This is the path for
porting a hand-rolled table whose identity/version/latest columns don't match
the defaults:

```elixir
versioning do
  identity :mo_id do
    define_attribute? false
  end

  version :mo_version do
    define_attribute? false
  end

  latest :mo_is_latest do
    define_attribute? false
  end
end

attributes do
  attribute :mo_id, :uuid, allow_nil?: false, writable?: false, default: &Ash.UUID.generate/0
  attribute :mo_version, :integer, allow_nil?: false, writable?: false, default: 0
  attribute :mo_is_latest, :boolean, allow_nil?: false, writable?: false, default: true
end
```

Each pre-declared attribute is verified the same way a generated one would be:
the identity attribute must be non-nullable and writable, the version
attribute must additionally be an integer, and the latest attribute a boolean.

[^1]: This is what [AshArchival][ash_archival] does. Its implementation is
    _incompatible_ with AshVersioned. Applying both AshArchival and
    AshVersioned on a resource will result in a build error.

[^2]: Database upsert operations (`ON CONFLICT DO UPDATE`) always update the
    conflicting row in place. SCD type 2 database definitions can never
    support this because this history is in the operational table. Database
    triggers could be used to support upsert through a separate history table.

[no-deletions]: basics.md#records-cannot-be-deleted
[ash_archival]: https://ash-archival.hexdocs.pm

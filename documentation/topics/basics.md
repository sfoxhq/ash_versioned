<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

# The versioning model

`AshVersioned` turns an Ash resource into a versioned resource using a
[Slowly Changing Dimension (type 2)][scd2] approach. This document covers the
mechanism used and its core consequences. Opt-in behaviour is covered in
[Options](options.md).

## How it works

Every mutation on a versioned resource appends a new row instead of updating
in place. The current row is set to stale (`latest_version: false`) and a new
row (copied from the current row with changes applied) is inserted. The old
row is never deleted or overwritten[^1], it just stops being the
`latest_version`. These changes are always executed in a transaction so there
are no partial updates.

Resource version integrity is ensured with two unique identities. The first
unique identity ensures that there is only one _active_ version of a resource
with a partial index on the resource identity where `latest_version == true`.

```elixir
identity :current_resource_id, [:resource_id], where: expr(latest_version == true)
```

The second unique identity ensures that a resource only has _one_ instance of
any given version.

```elixir
identity :full_history_resource_id, [:resource_id, :version_number]
```

The version integrity and update mechanisms impose structural and behavioural
constraints, described in more detail in the rest of this document.

## Resource identity

A versioned resource has two distinct identifiers.

- **The identity attribute** (the `resource_id`): the stable identity of the
  _logical object_, shared by every version. It never changes for a given
  object.

- **The primary key** (`id`): the physical identifier of _one version_ (a
  row). It changes on every mutation. A fetched row's `id` may be stale by
  time you read the resource's current `id`.

**Never look an object up by its primary key.** `id` is a data-layer
implementation detail, not an application-level handle. Filter, join, and
store foreign keys against the identity attribute instead. If you need a
specific version, query by identity attribute and version number together.

`AshVersioned` does not generate a primary key, but requires that you declare
a generated surrogate primary key yourself, the same way you would on any
other resource. Because the primary key is required only for internal
bookkeeping, we recommend `public?: false`:

```elixir
attributes do
  integer_primary_key :id, public?: false
  # or uuid_v7_primary_key, uuid_primary_key, ...
end
```

`AshVersioned.Resource` verifies at compile time that the resource has a
generated surrogate primary key. Missing, compound, or writable (natural)
primary keys are compile errors.

## History is the purpose

AshVersioned provides a full record of changes for a resource, but most
interactions with that resource operate only on the _latest_ version.
AshVersioned modifies read actions to include `latest_version == true` with a
[preparation][preparation].

The `version_history` read action is exempted from this scope narrowing as its
purpose is to see everything, including stale rows.

```elixir
MyApp.Widget
|> Ash.Query.for_read(:version_history)
|> Ash.Query.filter(resource_id == ^widget.resource_id)
|> Ash.Query.sort(version_number: :asc)
|> Ash.read!()
```

Read actions that need similar capability should be excluded from this scope
narrowing with the `exclude_read_actions` option.

```elixir
versioning do
  exclude_read_actions [:audit_trail]
end

actions do
  read :audit_trail do
    primary? false
  end
end
```

### Records cannot be deleted

AshVersioned does not allow destroy actions to be defined as versioned
resources should never be deleted. The [`archive`][archive] option on the
`versioning` section offers the alternative.

### Global `preparations` require care

If your resource defines additional global preparations, it is _imperative_
that the versioning history action is exempted from those preparations, and
strongly recommended that any other read actions in `exclude_read_actions` be
exempted as well. If this is not done, **AshVersioned** resource updates will
_probably_ fail with `StaleRecord` errors.

`AshVersioned.Resource.Info` includes four functions that assist with this:

- `versioning_all_excluded_read_actions!/1`
- `versioning_history_action!/1`
- `versioning_exclude_read_actions!/1`
- `versioning_archive_excluded_read_actions!/1`

The first function combines both functions, and you pass the `query.resource`
as the argument to any of them. For examples of this, see
`AshVersioned.Preparations.FilterLatest`.

## Authorization

A versioned update or archive is authorized once against the policies of the
action you call (`:increment`, `:archive`, …). The internal actions
(`__ash_versioned_mark_stale__` and `__ash_versioned_reinsert__`) are not
separately authorized, so your policies never need to allow them. Calling them
directly is still subject to the resource's policies.

Policies are evaluated as for any update action: filter checks against the
stored version (not the record passed in), checks on the actor, and checks on
the changes being made (such as `changing_attributes`). If the record passed
in has since been superseded by a newer version, the update fails with
`Ash.Error.Changes.StaleRecord`, even when policies allow it.

Bulk updates of a versioned resource require `strategy: :stream`, because
versioned updates are manual actions that cannot run atomically. Each record
is authorized and versioned separately.

## Multitenancy

AshVersioned has been verified to work with Ash's built-in attribute
[multitenancy][multitenancy].

[^1]: Except for setting `latest_version` to `false` and setting the updated
    timestamp to when the change was applied.

[scd2]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2:_add_new_row
[preparation]: https://ash.hexdocs.pm/preparations.html
[archive]: options.md#resource-archival
[multitenancy]: https://ash.hexdocs.pm/multitenancy.html

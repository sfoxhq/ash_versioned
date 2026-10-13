# `ash_versioned` Changelog

## v0.2.0 / 2026-10-13

Adds relationship declarations pointing to versioned resources and renames
generated internal actions.

### Breaking Changes

- The generated internal actions used by every versioned update have been
  renamed `version_mark_stale` → `__ash_versioned_mark_stale__` and
  `version_reinsert` → `__ash_versioned_reinsert__`.

  Notifiers, PubSub `publish` entries, validations (`action_is/1`), or
  policies referring to the old names must be updated.

- Every versioned resource now defines a reserved `__ash_versioned_latest__`
  calculation and a `__ash_versioned_read__` read action.

- When `AshVersioned.Relationships` is added to a resource, a `through` path
  with a plain relationship to a versioned resource is a compile error.
  Replace such relationships with their `*_versioned` equivalents.

### Features

- `AshVersioned.Relationships` adds `belongs_to_versioned`,
  `has_one_versioned`, and `has_many_versioned` to the `relationships`
  section, for relationships _to_ versioned resources from any resource.
  `AshVersioned.Resource` includes it automatically; non-versioned resources
  list it in `extensions`.

  - Each takes the same options as its Ash equivalent.
  - The latest version of the destination is resolved in loads, aggregates,
    `exists`, and filters or sorts through the relationship.
  - Relationships to archived records still resolve. Add a relationship
    `filter` to exclude them.
  - `belongs_to_versioned` joins on the destination's identity attribute
    (`:resource_id` by default, or the resource's own identity for
    self-references) and never creates a foreign key.
  - `has_one_versioned` and `has_many_versioned` support `through` paths,
    resolving the latest version of each record reached by the path.
  - Self-referential and mutually referential relationships are supported with
    destinations verified after compilation.

  Many-to-many relationships are not currently supported but are on the
  roadmap.

- `belongs_to_actor` relationships to a versioned resource now use the same
  underlying functionality as `belongs_to_versioned`.

### Bug Fixes

- `__ash_versioned_reinsert__` is no longer authorized separately. A versioned
  update (mark the current version stale, insert the new version) is a single
  operation, authorized once as the user's update or destroy action.

  Previously, the reinsert was checked against the resource's policies as a
  create action, so an actor allowed to update but not to create would be
  forbidden partway through an update. Policies written only to permit
  `version_reinsert` are no longer needed. `__ash_versioned_reinsert__` called
  directly is still subject to policies.

- A self-referential `belongs_to_actor` resolves its configuration from the
  resource's own DSL.

- A `postgres.references` entry declared for a `belongs_to_actor` relationship
  to a versioned resource is no longer accompanied by a second, generated
  `ignore?: true` reference for the same relationship.

### Migrations

No database changes are required for existing versioned resources: the new
calculation and read action, and the renamed actions, don't affect the schema.

## v0.1.0 / 2026-10-02

Initial release. Implements SCD2 (slowly-changing-dimension type 2) versioning
for Ash resources: every mutation appends a new row instead of updating in
place, so no historical value is ever overwritten.

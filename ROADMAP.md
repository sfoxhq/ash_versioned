<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

# AshVersioned Roadmap

These features have been considered but excluded from the initial release of
`ash_versioned`. Inasmuch this is a roadmap, no route towards any of these
points of interest has been determined.

## Composite resource identities

Right now, identities must be single-column keys. If it's possible to have
composite resource identities, surrogate keys for other capabilities (like
versioned join tables) would not be necessary.

A composite resource identity could be simulated with an encoded string value
(a base-64 encoding of `type1=key1&type2=key2`, for example) used as an
accepted natural key, but that is not easily searchable, which is an advantage
afforded by composite natural keys.

## Versioned `many_to_many` relationships (versioned joins)

AshVersioned 0.2 adds `belongs_to_versioned`, `has_one_versioned`, and
`has_many_versioned` for relationships _to_ versioned resources. Versioned
`many_to_many` relationships are more complex and require care.

A `many_to_many` relationship's state lives in the join resource, not on
either end. If either end is versioned the join resource _must_ be versioned
with archiving. This is because the relationships at any version or point in
time are part of that resource's history.

The keying of each end Would be expressed as separate DSL entities:

- `many_versioned_to_many`: versioned source, non-versioned destination
- `many_to_many_versioned`: non-versioned source, versioned destination
- `many_versioned_to_many_versioned`: versioned source and destination

A single DSL entity that resolves the version end(s) would be easier to use
(and to type), but is nontrivial. The source end can be resolved from the
resource's own DSL, but the destination end cannot be introspected at compile
time without risking compile deadlocks, so it would still need to be declared
or defaulted and checked by a verifier. A name for this entity has not been
settled; `versioned_many_to_many` reads well but breaks the `*_versioned`
naming convention established in AshVersioned 0.2.

The requirement of a versioned join raises unresolved problems:

- `manage_relationship` breaks the relationships of `many_to_many` records by
  destroying join rows, which versioned resources prohibit. Relationship
  breaking must be redefined as archiving the join row.
- The `latest == true` filter must be applied to the generated join
  relationship, which `many_to_many` does not expose. The join `has_many` must
  be built before Ash's `CreateJoinRelationship` transformer runs.
- Whether the join resource is versioned cannot be determined by introspection
  at compile time without risking compile deadlocks (join resources reference
  both ends), so it must be checked by a verifier.
- The natural shape of a join table (a composite primary key) is not usable.
  If composite resource identities aren't possible (above), the relationship
  must be kept alongside a surrogate relationship identity key. The number of
  indexes required on this table is high, and identity rejection may work
  against this design.

Tests for this will need to be built prior to suggesting changes or design
models.

## Point-in-time (`as_of`) queries

Reads of a versioned resource return the _latest_ version of each record.
Querying the state of data as of a given version or point in time is possible
today, but it is manual and messy, especially when the query crosses
relationships. The validity period of any version is already recorded:

- the period begins at the version's `inserted_at`
- the period ends at the version's `updated_at` if the version is not latest
- the period is open-ended if the version is latest (`updated_at` is ignored)

Finding the related records of version 5 of a resource requires reading that
version's validity period and querying the related (or join) resource for
versions valid in that period with the relationship identity.

AshVersioned should support this directly, taking query-side concepts from
Ash's new temporal resources: an `as_of` on reads that selects the versions
valid at that point in time instead of the latest versions. When an `as_of`
query crosses relationships to other versioned resources, the same `as_of`
applies to them, replacing the `latest == true` relationship filter with a
validity-period filter. AshVersioned should _not_ support the write-side
concepts (historical modification or ranged deletion).

Open questions:

- How `as_of` interacts with `FilterLatest` and the existing history action.
- An `as_of_version` option for querying as of a specific version of a
  resource, separate from a point-in-time `as_of`. Whether related records are
  resolved as of the start of that version's validity period (simple, but
  changes to related records during the version are only visible when querying
  by time), or whether related-record changes should write new versions of the
  resource (exact, but a `many_to_many` change would write new versions of
  both ends).
- How `as_of` propagates through relationship loads, aggregates, and `exists`
  expressions so that every consumer applies the same point in time.
- Whether the `inserted_at`/`updated_at` period columns are indexable enough
  for range queries, or whether a dedicated period column is warranted.

The 0.2 `*_versioned` relationships (and `belongs_to_actor`) take their
latest-version filter from a single shared definition, so it can later be made
`as_of`-aware in one place without changing any relationship declarations.

## Related-record archival

Archival capabilities in AshVersioned are limited only to the current table
and have no way of archiving related relationships. AshVersioned needs to
support related archival requests:

- from AshArchival resources
- from related AshVersioned resources with archive enabled
- to AshArchival resources
- to related AshVersioned resources with archive enabled

## Locking down internal-only generated actions

AshVersioned requires several generated actions and calculations
(`__ash_versioned_mark_stale__`, `__ash_versioned_reinsert__`,
`__ash_version_read__`, `__ash_version_latest__`, etc.) and are meant to be
called only from internal modules and operate at a level _below_ user
accessible features. These are "called" private actions, but that's
aspirational, not enforced.

There's no `private?`-style field on Ash update actions to actually lock it
down, and nothing stops a resource author's own domain from exposing it via a
code interface or calling it directly. Doing either bypasses the whole
flip/reinsert append-only guarantee. `__ash_versioned_mark_stale__` just flips
`latest_attribute` to `false` with no reinsert, silently dropping a version
from view with no replacement.

This surfaced as a real concern while fixing atomic upgrades in
`__ash_versioned_mark_stale__` interacting with the `history_action`.
Similarly, AshVersioned requires hygienic coding practices in order to support
`exclude_read_actions` instead of having structural exclusion capabilities.
Spark's `dsl_patches` can add new entities to another extension's DSL section,
but cannot add options to existing entities (such as a `private?` option on
update actions) or exclude them.

> This may require support from Ash itself, including the ability for certain
> internal actions to _exclude_ global preparations just as global validations
> can be excluded.

## Composing a resource-supplied `manual`

_Every_ update action on an AshVersioned resource is unconditionally set to
`manual: {AshVersioned.Resource.ManualIncrement, ...}`, replacing any
explicitly defined `manual`. This is rejected at compile time rather than
silently discarded, but this is a stopgap measure. AshVersioned needs to
expose some way of letting a defined `manual` function _use_ the core
AshVersioned tooling and for an update to signal that it's using this, or for
some sort of composition capability.

> As with locking down internal actions, composition may require support from
> Ash itself.

## Prefixing identity attributes

The AshVersioned resource `identity` has no way of working with or producing
prefixed identity types such as those provided by `ash_object_ids` or
`ash_prefixed_id`. Figuring out how to work with these would be _ideal_
especially with the recommendations for `reference_actor` implementations.

Both `ash_object_ids` and `ash_prefixed_id` modify how primary keys and
foreign keys are _presented_, but don't change them from the underlying
`uuid_v7` implementations (more or less), so using either should not require
`origin: :accept`.

## Data purging (GDPR / erasure)

Versioned history and data purging interact in ways (from a compliance and
legal perspective) that can only be determined by the business for which an
application is built. But AshVersioned should probably provide a mechanism by
which otherwise prohibited updates can be made on historical versions. There
are multiple considerations, such as purging, quarantine, and redaction.

Ideally, this would be built as a separate, independently versioned package.

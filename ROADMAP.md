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
`__ash_versioned_read__`, `__ash_versioned_latest__`, etc.) and are meant to
be called only from internal modules and operate at a level _below_ user
accessible features.

The generated actions `__ash_versioned_mark_stale__`,
`__ash_versioned_reinsert__`, and `__ash_versioned_read__` are now declared
`public?: false` (Ash 3.20, ash-project/ash#2629). This keeps them out of API
extensions (AshGraphql, AshJsonApi), out of the Ash manifest, and lets
policies distinguish them with `private_action?()`. The history action stays
public.

`public?: false` is a declaration, not enforcement. Ash does not appear to
stop a code interface from targeting a non-public action, nor a direct
`Ash.update/2`. Either bypasses the whole flip/reinsert append-only guarantee.
`__ash_versioned_mark_stale__` just flips `latest_attribute` to `false` with
no reinsert, silently dropping a version from view with no replacement.

### Verifier for code interfaces

A compile-time verifier should reject any code interface whose `action` is one
of the generated internal actions. Code interfaces can be declared in two
places, and where the verifier runs depends on which:

- **Resource `code_interface` section.** An AshVersioned resource verifier
  (alongside `VerifyNoCustomManual` and friends) can see these in its own DSL
  state. This case is straightforward.
- **Domain `resources do resource X do define ... end end`.** The resource's
  verifiers never see these; they live in the domain's DSL state. Catching
  them requires a verifier running on `Ash.Domain`, which AshVersioned does
  not control. Open questions: whether it needs a separate
  `AshVersioned.Domain` extension that users must add (easy to forget, which
  defeats the point), whether a `dsl_patches` entry can attach a verifier to
  `Ash.Domain` from the resource extension (unverified), and whether
  cross-module lookup from a domain verifier risks the compile deadlocks that
  already constrain `versioned_many_to_many` below.

Neither covers direct `Ash.update/2`-style calls, which can't be verified at
compile time.

### Remaining gaps

This surfaced as a real concern while fixing atomic upgrades in
`__ash_versioned_mark_stale__` interacting with the `history_action`.
Similarly, AshVersioned requires hygienic coding practices in order to support
`exclude_read_actions` instead of having structural exclusion capabilities.
Spark's `dsl_patches` can add new entities to another extension's DSL section,
but cannot add options to existing entities or exclude them.

> Excluding global preparations from internal actions, just as global
> validations can be excluded, may require support from Ash itself.

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

## Prefixing / encoding identity attributes

The AshVersioned resource `identity` has no way of producing prefixed or
otherwise encoded identities. After investigating integration with existing
Ash libraries (`ash_prefixed_id`, `ash_object_ids`, etc.) to adopt their
types, we determined that's not possible. We will now build a parallel, opt-in
capability instead.

- The existing libraries are organized around database primary keys and the
  foreign keys that point at them. The AshVersioned identity is neither: it is
  a separate attribute shared by every version of a record, generated and
  copied by AshVersioned, not by the resource's primary key declaration.

  The libraries have no easy way to type an arbitrary non-primary-key
  attribute.

- They generate a type per resource. A type that exists only after another
  resource has compiled can't be referenced from `belongs_to_versioned`
  without the cross-resource compile dependency the roadmap already identifies
  as a deadlock risk.

- Each library has a different shape, so there is no single integration point.

- AshVersioned needs to know how to _generate_ an identity value and how a
  foreign key to it must be typed. Both are decisions about its own identity
  attribute and cannot be delegated to a type AshVersioned doesn't control.

- Encoding must be opt-in. A resource that declares nothing keeps today's
  plain `uuid_v7` identity with no change in behavior or migrations.

## Document the accepted-or-generated identity pattern

An application can accept a caller-supplied identity and fall back to a
generated one when none is given. This is used in a real application for
well-known sentinel identities (the nil UUID, nil+1, and so on), which callers
supply explicitly, while every other record gets a generated UUIDv7.

This needs a guide section covering:

- why the fallback lives in the application's create action, not in
  AshVersioned (the action decides per call site; an action that neither
  receives nor generates the identity fails loudly);
- how `origin: :accepted` interacts with `set_new_attribute` ordering (the
  application's changes run before the ones AshVersioned appends);
- how `set_new_attribute` treats an explicit `nil` (unverified);
- that identity types are not restricted to UUIDv7 in this pattern, and that
  decoding of sentinel values must not assume a UUID version.

## Document the core table + details table pattern

We've adopted a pattern of a `resource` and `resource_details` table where the
`resource` table is immutable (often insert-only) and is used to provide the
adopted resource identities.

We should add a guide section examining this.

## Migrating to a versioned resource from an unversioned resource

There is no guide for converting (or migrating) an existing, unversioned
resource (with existing rows and existing foreign keys) into an AshVersioned
resource. (In general, an in-place conversion is not possible, but the guide
should describe what steps to take for the conversion and migration of the
resources.)

## Data purging (GDPR / erasure)

Versioned history and data purging interact in ways (from a compliance and
legal perspective) that can only be determined by the business for which an
application is built. But AshVersioned should probably provide a mechanism by
which otherwise prohibited updates can be made on historical versions. There
are multiple considerations, such as purging, quarantine, and redaction.

Ideally, this would be built as a separate, independently versioned package.

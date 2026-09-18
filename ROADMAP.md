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

## Versioned join tables (`many_to_many`)

Versioned `belongs_to` relationships are easy: when the relationship is
changed, a new version is written with the reference key updated or cleared.
Versioned `many_to_many` relationships are harder.

The patterns available in AshVersioned enable most of this, but there are
still unanswered questions. The intermediate join table must be versioned with
archiving enabled. The natural shape of a join table (a composite primary key)
is not usable. If composite resource identities aren't possible (above), then
the relationship must be kept while also keeping a surrogate relationship
identity key. The number of indexes that would need to exist on this table is
high, and the identity rejection may work against this design requiring
adjustments.

Tests for this will need to be built prior to suggesting changes or design
models.

## Related-record archival

Archival capabilities in AshVersioned are limited only to the current table
and have no way of archiving related relationships. AshVersioned needs to
support related archival requests:

- from AshArchival resources
- from related AshVersioned resources with archive enabled
- to AshArchival resources
- to related AshVersioned resources with archive enabled

## Locking down internal-only generated actions

AshVersioned requires several generated actions (`version_mark_stale`,
`version_reinsert`, `history_action`, etc.) and are meant to be called only
from internal modules and operate at a level _below_ user accessible features.
These are "called" private actions, but that's aspirational, not enforced.

There's no `private?`-style field on Ash update actions to actually lock it
down, and nothing stops a resource author's own domain from exposing it via a
code interface, or calling `Ash.update!(record, :version_mark_stale, %{})`
directly. Doing either bypasses the whole flip/reinsert append-only guarantee.
Calling the `version_mark_stale` action on its own just flips
`latest_attribute` to `false` with no reinsert, silently dropping a version
from view with no replacement.

This surfaced as a real concern while fixing atomic upgrades in
`version_mark_stale` interacting with the `history_action`. Similarly,
AshVersioned requires hygienic coding practices in order to support
`exclude_read_actions` instead of having structural exclusion capabilities or
extension capabilities to existing DSL sections.

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

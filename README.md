# AshVersioned

[![Hex.pm](https://img.shields.io/hexpm/v/ash_versioned.svg?style=for-the-badge)][hexpm]
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg?style=for-the-badge)][docs]
[![Apache-2.0](https://img.shields.io/hexpm/l/ash_versioned.svg?style=for-the-badge "Apache-2.0")](https://github.com/sfoxhq/ash_versioned/blob/main/LICENCE.md)

<!--
![Coveralls](https://img.shields.io/coverallsCoverage/github/sfoxhq/ash_versioned?style=for-the-badge)
-->

- code :: <https://github.com/sfoxhq/ash_versioned>
- issues :: <https://github.com/sfoxhq/ash_versioned/issues>

Resource versioning for Ash using [Slowly Changing Dimension (type 2)][scd2].
There are multiple approaches to SCD type 2, but AshVersioned uses a version
number column and a flag indicating the current version.

## Compared to other approaches

Ash has three other approaches that answer the question "what did this
resource look like before?" AshVersioned requires a structural commitment to
the core resource definition, whereas the other options place history in
separate tables.

- [`ash_paper_trail`][apt] stores historical records into a generated
  `Version` linked resource: one history table per versioned resource with
  matching column definitions.

- [`ash_events`][ae] and [`ash_event_log`][ael] store historical records as
  event logs into a single history table for the entire application. This
  makes tracking _any_ change across the entire database easy.

  - `ash_events` stores the action and its inputs, not just the resulting
    values, so state can be replayed and rebuilt from the event stream. This
    makes it closer to event sourcing than an audit trail.

  - `ash_event_log` is the lightest alternative: audit-only, no replay, and
    logged out-of-band so it doesn't sit in the write path.

AshVersioned trades the lower friction of out-of-band history for uniformity
and durability.

> AshVersioned uses one variation of SCD type 2. As stale rows have their
> update timestamps modified when they become stale, it shares many
> similarities with a (uni-) temporal table. AshVersioned is _not_ designed
> for temporal use and cannot readily support more complex temporal types.

## Installation

Add `ash_versioned` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_versioned, "~> 0.1"}
  ]
end
```

Documentation is found on [HexDocs][docs].

## Tutorials

- [Getting Started with AshVersioned](documentation/tutorials/getting-started-with-ash-versioned.md)

## Topics

- [The versioning model](documentation/topics/basics.md)
- [Options](documentation/topics/options.md)

## Reference

- [AshVersioned.Resource DSL](documentation/dsls/DSL-AshVersioned.Resource.md)

## Semantic Versioning

AshVersioned follows [Semantic Versioning 2.0][semver].

[ae]: https://hex.pm/packages/ash_events
[ael]: https://hex.pm/packages/ash_event_log
[apt]: https://hex.pm/packages/ash_paper_trail
[docs]: https://ash-versioned.hexdocs.pm/
[hexpm]: https://hex.pm/packages/ash_versioned
[scd2]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2:_add_new_row
[semver]: https://semver.org/

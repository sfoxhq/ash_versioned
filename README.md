# AshVersioned

[![Hex.pm](https://img.shields.io/hexpm/v/ash_versioned.svg?style=for-the-badge)][hexpm]
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg?style=for-the-badge)][docs]
[![Apache-2.0](https://img.shields.io/hexpm/l/ash_versioned.svg?style=for-the-badge "Apache-2.0")](https://github.com/sfoxhq/ash_versioned/blob/main/LICENCE.md)
![Coveralls](https://img.shields.io/coverallsCoverage/github/sfoxhq/ash_versioned?style=for-the-badge)

- code :: <https://github.com/sfoxhq/ash_versioned>
- issues :: <https://github.com/sfoxhq/ash_versioned/issues>

Versioned resources for Ash. Implements
[Slowly Changing Dimension (type 2)][scd2] resources with latest version and
current flag.

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

## Semantic Versioning

AshVersioned follows [Semantic Versioning 2.0][semver].

[docs]: https://ash-versioned.hexdocs.pm/
[hexpm]: https://hex.pm/packages/ash_versioned
[semver]: https://semver.org/
[scd2]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2:_add_new_row

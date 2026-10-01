<!--
SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>

SPDX-License-Identifier: Apache-2.0
-->

# Getting started with AshVersioned

`AshVersioned` enables Ash resource versioned with
[Slowly Changing Dimension type 2)][scd2]. Every mutation creates a new
version instead of an in-place mutation. Each version is a distinct row with
bookkeeping attributes, actions, and identities that keep those rows correctly
linked, ordered, and scoped.

## Installation

Add `ash_versioned` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_versioned, "~> 0.1"}
  ]
end
```

## A minimal resource

```elixir
defmodule MyApp.Widget do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshVersioned.Resource]

  postgres do
    table "widgets"
    repo MyApp.Repo
  end

  versioning do
  end

  actions do
    defaults [:read]

    create :create do
      accept [:status]
    end

    update :increment do
      accept [:status]
    end
  end

  attributes do
    integer_primary_key :id, public?: false
    attribute :status, :string, public?: true, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
```

Every update action (`:increment`) appends a new version.

## Prerequisites and what gets generated

AshVersioned resources are required to declare a generated surrogate primary
key and both create and update timestamps for use with versioning. This is why
the example resource above declares `integer_primary_key :id`,
`create_timestamp :inserted_at`, and `update_timestamp :updated_at` itself.

`versioning do ... end` adds three fields:

- `resource_id` (`uuid_v7`): stable across every version of the same logical
  object
- `version_number` (`integer`): starting at `0`, incremented on every mutation
- `latest_version` (`boolean`): marks the current version or stale

It also adds two unique indexes enforcing:

- at most one `latest_version: true` row per `resource_id`
- that `(resource_id, version_number)` is never duplicated across the
  resource's entire history

> #### Never look an object up by its primary key {: .warning}
>
> `id` changes on every mutation; `resource_id` is stable. Filter, join, and
> store foreign keys against `resource_id` — see [Identity][identity] for why.

## Using it

```elixir
widget =
  MyApp.Widget
  |> Ash.Changeset.for_create(:create, %{status: "new"})
  |> Ash.create!()

# version_number: 0, latest_version: true

incremented =
  widget
  |> Ash.Changeset.for_update(:increment, %{status: "active"})
  |> Ash.update!()

# a NEW row: version_number: 1, latest_version: true, same resource_id.
# the OLD row still exists, now with latest_version: false.
incremented.id != widget.id
incremented.resource_id == widget.resource_id
incremented.version_number == widget.version_number + 1
```

Every ordinary read action only ever sees the latest, unarchived row for each
`resource_id`. To see every version, including stale ones, use the generated
history action:

```elixir
MyApp.Widget
|> Ash.Query.for_read(:version_history)
|> Ash.Query.filter(resource_id == ^widget.resource_id)
|> Ash.Query.sort(version_number: :asc)
|> Ash.read!()
```

See [history action][history-action] for why this is a preparation rather than
a `base_filter`.

If two mutations race against the same row, the loser fails with
`Ash.Error.Changes.StaleRecord` rather than silently clobbering the winner's
version — the flip that marks a row stale is a filtered update scoped to that
exact row, so a concurrent mutation against the same row sees zero rows
affected.

## Where to go next

- [The versioning model][basics]: the core mechanic in full, required
  unique-key shapes, multitenancy, and why deletion isn't possible.
- [Options][options]: archival, actor attribution, and other advanced topics.

[scd2]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2:_add_new_row
[identity]: ../topics/basics.md#resource-identity
[history-action]: ../topics/basics.md#history-is-baseline-not-a-feature
[basics]: ../topics/basics.md
[options]: ../topics/options.md

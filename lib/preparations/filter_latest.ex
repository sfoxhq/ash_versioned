# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Preparations.FilterLatest do
  @moduledoc """
  Scopes read actions to include `latest_attribute == true`, and if `archive` is declared
  on the resource, `archived == false`.

  The resource `history_action` is _always_ excluded from both latest and archive
  filtering; user-declared actions can be excluded with `exclude_read_actions`.

  When `archive` is present, the generated `archive.read_action` is excluded from archive
  filtering (but not latest filtering); user-declared actions can be excluded with from
  archive filtering with `archive.exclude_read_actions`.

  An action name only needs to appear in one of the two exclusion lists; the top-level
  one is checked first and is a full bypass, so an action listed in both gets the
  top-level treatment.

  Reserved actions (like `__ash_versioned_read__`) are always excluded from at least archive filtering, and may be excluded from latest version filtering.
  """

  use Ash.Resource.Preparation

  import Ash.Expr

  alias Ash.Resource.Preparation
  alias AshVersioned.Resource.Info
  alias AshVersioned.VersionedRelationship

  require Ash.Query

  @impl Preparation
  def prepare(query, _opts, _context) do
    archive = Info.versioning_archive(query.resource)
    latest_field = Info.versioning_latest_attribute(query.resource)

    cond do
      query.action.name in Info.versioning_all_excluded_read_actions!(query.resource) ->
        query

      query.action.name == VersionedRelationship.read_action() ->
        Ash.Query.filter(query, ^ref(latest_field) == true)

      query.action.name in Info.versioning_archive_excluded_read_actions!(query.resource) ->
        Ash.Query.filter(query, ^ref(latest_field) == true)

      not is_nil(archive) ->
        Ash.Query.filter(query, ^ref(latest_field) == true and ^ref(archive.attribute) == false)

      true ->
        Ash.Query.filter(query, ^ref(latest_field) == true)
    end
  end
end

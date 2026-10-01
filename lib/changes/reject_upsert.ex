# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Changes.RejectUpsert do
  @moduledoc """
  Rejects any create call that has `upsert?: true` at runtime (see
  `AshVersioned.Transformers.WireActions`).
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change
  alias AshVersioned.Resource.Info

  @impl Change
  def change(changeset, _opts, _context) do
    if changeset.context[:private][:upsert?] do
      identity_field =
        Info.versioning_identity_attribute(changeset.resource)

      Ash.Changeset.add_error(changeset,
        message: """
        upsert is not supported. Look up the resource by `#{identity_field}` and update \
        if one is returned, or create a new resource.
        """
      )
    else
      changeset
    end
  end
end

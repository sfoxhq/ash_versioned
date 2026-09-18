# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.RejectFlagged do
  @moduledoc """
  Validation test fails whenever `fail_reinsert` is true. Used to deterministically
  trigger a reinsert failure inside `AshVersioned.Resource.ManualIncrement`.
  """

  use Ash.Resource.Validation

  alias Ash.Resource.Validation

  @impl Validation
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :fail_reinsert) do
      {:error, field: :fail_reinsert, message: "intentionally failed for testing"}
    else
      :ok
    end
  end
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.ReferenceActorTransforms do
  @moduledoc """
  A named function for testing `reference_actor`'s `transform` option in MFA form.
  """

  @doc "Prefixes `actor.tenant:actor.ref` with `prefix`."
  def prefixed(actor, prefix), do: {:ok, "#{prefix}#{actor.tenant}:#{actor.ref}"}
end

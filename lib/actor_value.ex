# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defprotocol AshVersioned.ActorValue do
  @moduledoc """
  Resolves the provided actor using the actor configuration.
  """

  @doc """
  Extracts the value of the `actor` for storage in a field described by `config`.

  Must return `{:ok, term()}` or `{:error, term()}`.
  """
  @spec actor_value(struct(), term()) :: {:ok, term()} | {:error, term()}
  def actor_value(config, actor)
end

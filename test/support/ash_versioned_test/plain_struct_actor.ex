# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.PlainStructActor do
  @moduledoc """
  A plain Elixir struct with no Ash/Spark association at all to test
  `AshVersioned.ReferenceActorValue` candidate derivation on non-Ash resources.
  """

  defstruct [:id]
end

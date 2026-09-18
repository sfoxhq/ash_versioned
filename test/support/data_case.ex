# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.DataCase do
  @moduledoc """
  Test case template for tests that need access to the test-support Postgres repo. Enables
  the SQL sandbox so changes made during a test are reverted at the end of it.
  """

  use ExUnit.CaseTemplate

  alias AshVersionedTest.Repo
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import AshVersioned.DataCase
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end

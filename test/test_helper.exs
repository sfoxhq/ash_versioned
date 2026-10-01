# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

ExUnit.start(capture_log: true, timeout: 1_000)

Application.ensure_all_started(:postgrex)
AshVersionedTest.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(AshVersionedTest.Repo, :manual)

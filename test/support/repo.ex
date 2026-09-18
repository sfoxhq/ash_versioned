# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersionedTest.Repo do
  @moduledoc false
  use AshPostgres.Repo, otp_app: :ash_versioned

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  def installed_extensions do
    ["ash-functions"]
  end
end

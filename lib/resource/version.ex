# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.Version do
  @moduledoc """
  Represents the `version` entity declared inside the `versioning` DSL section of
  `AshVersioned.Resource`.
  """

  defstruct [:name, :define_attribute?, :source, __spark_metadata__: nil]

  @type t :: %__MODULE__{name: atom(), define_attribute?: boolean(), source: atom() | nil}
end

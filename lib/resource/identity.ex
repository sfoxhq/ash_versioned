# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.Identity do
  @moduledoc """
  Represents the `identity` entity declared inside the `versioning` DSL section of
  `AshVersioned.Resource`.
  """

  defstruct [:name, :define_attribute?, :origin, :type, :source, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: atom(),
          define_attribute?: boolean(),
          origin: :generated | :accepted,
          type: term(),
          source: atom() | nil
        }
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.Archive do
  @moduledoc """
  Represents the `archive` entity declared inside the `versioning` DSL section of
  `AshVersioned.Resource`.

  A resource is archivable when the `archive` entity is declared.
  """

  defstruct [
    :attribute,
    :define_attribute?,
    :action,
    :read_action,
    :unarchive,
    :exclude_read_actions,
    :source,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          attribute: atom(),
          define_attribute?: boolean(),
          action: atom() | false,
          read_action: atom() | false,
          unarchive: atom() | false,
          exclude_read_actions: [atom()],
          source: atom() | nil
        }
end

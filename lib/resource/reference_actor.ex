# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.ReferenceActor do
  @moduledoc """
  Represents a `reference_actor` field declared inside the `versioning` DSL section of
  `AshVersioned.Resource`.

  The default `transform` is `AshVersioned.ReferenceActorValue`.
  """

  defstruct [
    :name,
    :attribute_name,
    :allow_nil?,
    :public?,
    :transform,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          attribute_name: atom(),
          allow_nil?: boolean(),
          public?: boolean(),
          transform: (term -> {:ok, term} | {:error, term}) | {module, atom, list}
        }

  defimpl AshVersioned.ActorValue do
    def actor_value(%@for{transform: {m, f, a}}, actor) when is_atom(m) and is_atom(f) and is_list(a) do
      apply(m, f, [actor | a])
    end

    def actor_value(%@for{transform: transform}, actor) when is_function(transform, 1) do
      transform.(actor)
    end
  end
end

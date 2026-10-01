# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.Resource.BelongsToActor do
  @moduledoc """
  Represents a `belongs_to_actor` declared inside the `versioning` DSL section of
  `AshVersioned.Resource`.
  """

  defstruct [
    :name,
    :attribute_name,
    :destination,
    :domain,
    :define_attribute?,
    :destination_attribute,
    :validate_destination_attribute?,
    :on_delete,
    :attribute_type,
    :allow_nil?,
    :public?,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          attribute_name: atom(),
          destination: Ash.Resource.t(),
          domain: atom() | nil,
          define_attribute?: boolean(),
          destination_attribute: atom(),
          validate_destination_attribute?: boolean(),
          on_delete: :delete | :nilify | :nothing | :restrict | {:nilify, [atom()]},
          attribute_type: term(),
          allow_nil?: boolean(),
          public?: boolean()
        }

  defimpl AshVersioned.ActorValue do
    @doc """
    If the actor matches the destination type, it is used for the field, otherwise the
    field's value is set to `nil`. This may be restricted by the `allow_nil?` value on the
    field definition.
    """
    def actor_value(%@for{destination: destination, destination_attribute: attribute}, actor) do
      if is_struct(actor, destination) do
        {:ok, Map.get(actor, attribute)}
      else
        {:ok, nil}
      end
    end
  end
end

# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.ReferenceActorValue do
  @moduledoc """
  The default `transform` function for a `reference_actor` field.
  """

  alias Ash.Resource.Info

  @doc """
  Returns the identity value for the provided `actor` or an error message.

  Ash resources are resolved using the primary key, if it resolves to a single value
  (composite primary keys are not supported). When the Ash resource is an
  `AshVersioned.Resource`, it uses the resource identity attribute.

  All other `actor` values (except `nil`) are checked for string conversion
  (`String.Chars`) and an error is returned if it cannot be converted.
  """
  def value_for(nil), do: {:ok, nil}

  def value_for(actor) do
    case resolve(actor) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:ok, value} -> stringify(value)
      :error -> derive_error()
    end
  end

  defp resolve(%resource{} = actor) do
    cond do
      Info.resource?(resource) -> resolve_resource(resource, actor)
      not is_nil(String.Chars.impl_for(actor)) -> {:ok, to_string(actor)}
      true -> :error
    end
  end

  defp resolve(actor), do: {:ok, actor}

  defp resolve_resource(resource, actor) do
    if AshVersioned.Resource in Spark.extensions(resource) do
      {:ok, Map.get(actor, AshVersioned.Resource.Info.versioning_identity_attribute(resource))}
    else
      case Info.primary_key(resource) do
        [pk] -> {:ok, Map.get(actor, pk)}
        _ -> :error
      end
    end
  end

  defp stringify(value) do
    if String.Chars.impl_for(value) do
      {:ok, to_string(value)}
    else
      derive_error()
    end
  end

  defp derive_error, do: {:error, "Cannot derive an identity for provided actor"}
end

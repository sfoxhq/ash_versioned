# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule AshVersioned.IdentityScoping do
  @moduledoc """
  Determines whether an `Ash.Resource.Identity` is usable on an `AshVersioned.Resource`.
  All user-defined identities on a versioned resource must conform to exactly one of these
  constraints:

  - it must have a partial lookup `where latest == true`; or
  - it must be a superset of the full record history (`{identity, version}`) and must not
    have a partial lookup `where latest == true`; or

  Identity definitions that do not follow these conventions will eventually trip the
  uniqueness guarantees provided by the default identities. The functions in this module
  are used by `AshVersioned.Verifiers.VerifyIdentityScoping` to ensure that invalid
  identities are caught at compile time, and by `AshVersioned.Transformers.AddFields` to
  ensure that partial indexes are created correctly.

  Additional conditions for partial lookups are not currently supported.
  """

  alias Ash.Query.Call
  alias Ash.Query.Ref

  @doc """
  Returns `true` if `identity` conforms to one of the two required indexes.
  """
  def safe?(identity, identity_field, version_field, latest_field) do
    full? = full_history_composite?(identity, identity_field, version_field, latest_field)
    latest? = scoped_to_latest?(identity, latest_field)

    # This is the same as `full? xor latest?`.
    latest_field not in identity.keys and full? != latest?
  end

  @doc """
  Returns `true` if `identity`'s keys include both `identity_field` and `version_field`
  and does not include `latest_field`.
  """
  def full_history_composite?(identity, identity_field, version_field, latest_field) do
    identity_field in identity.keys and version_field in identity.keys and
      latest_field not in identity.keys and not scoped_to_latest?(identity, latest_field)
  end

  @doc """
  Returns `true` if the identity `where` clause is `{latest} == true`.

  Complex `where` expressions are rejected.
  """
  def scoped_to_latest?(identity, latest_field) do
    match_latest_where?(identity.where, latest_field)
  end

  defp match_latest_where?(%Call{name: :==, args: [left, right]}, latest_field) do
    (ref?(left, latest_field) and right == true) or (ref?(right, latest_field) and left == true)
  end

  defp match_latest_where?(_where, _latest_field), do: false

  defp ref?({:_ref, _meta, field}, field), do: true

  # These implementations are difficult to cover as they result in build time errors.
  #
  # coveralls-ignore-start
  defp ref?(%Ref{attribute: field, relationship_path: []}, field), do: true
  defp ref?(_other, _field), do: false
  # coveralls-ignore-stop
end

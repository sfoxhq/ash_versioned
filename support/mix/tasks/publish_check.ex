# SPDX-FileCopyrightText: 2026 sFOX and contributors <https://github.com/sfoxhq/ash_versioned/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.PublishCheck do
  @shortdoc "Verifies that the release tag, mix.exs version, and CHANGELOG.md agree"

  @moduledoc """
  Verifies that a pending release is internally consistent.

  ```sh
  mix publish_check [TAG] [--notes-file PATH]
  ```

  With a `TAG` (the release workflow passes the pushed tag), checks that:

  - `TAG` (with an optional leading `v`) matches the `mix.exs` version.
  - `CHANGELOG.md` has a dated `## vX.Y.Z` section for that version, and the section is
    not empty.

  Without a `TAG`, the latest planned release is taken from the changelog (the first `##
  vX.Y.Z` heading) and checked against the `mix.exs` version. If they differ, the release
  is not ready: bump `@version` in `mix.exs` before tagging.

  Every version heading in the changelog must have both the version and the target release
  date (`## vX.Y.Z / YYYY-MM-DD`). The date must be a valid ISO 8601 date at most 7 days
  in the future.

  Any `##` heading that does not start with a version (`## NEXT`, `## Unreleased`, ...) is
  a placeholder for a release whose version is not yet decided. A changelog containing
  one, or a version heading without a valid date, is not ready to release (with or without
  a `TAG`).

  ## Options

  - `--notes-file PATH` - write the changelog section for the release to `PATH`
    (suitable for `gh release create --notes-file`).
  """

  use Mix.Task

  @requirements ["app.config"]

  # A changelog entry may be written ahead of the release, but not far ahead.
  @max_days_ahead 7

  @impl Mix.Task
  def run(args) do
    {opts, argv} =
      OptionParser.parse!(args, strict: [notes_file: :string, changelog: :string])

    path = Keyword.get(opts, :changelog, "CHANGELOG.md")
    lines = read_lines!(path)
    mix_version = Mix.Project.config()[:version]

    versions = release_versions!(lines)

    version =
      case argv do
        [tag] -> check_tag!(tag, mix_version)
        [] -> check_planned!(versions, mix_version)
        _ -> Mix.raise("Usage: mix publish_check [TAG] [--notes-file PATH]")
      end

    notes = section!(lines, version)

    if file = opts[:notes_file], do: File.write!(file, notes)

    Mix.shell().info("Release #{version} OK")
  end

  defp check_tag!(tag, mix_version) do
    if String.trim_leading(tag, "v") != mix_version do
      Mix.raise("Tag #{tag} does not match mix.exs version #{mix_version}")
    end

    mix_version
  end

  defp check_planned!([version | _], mix_version) do
    if version != mix_version do
      Mix.raise("Not ready: CHANGELOG.md plans v#{version} but mix.exs version is #{mix_version}")
    end

    version
  end

  defp check_planned!([], _mix_version), do: Mix.raise("No release (## vX.Y.Z) found in CHANGELOG.md")

  defp release_versions!(lines) do
    today = Date.utc_today()
    headings = for "## " <> heading <- lines, do: String.trim(heading)
    parsed = Enum.map(headings, &{&1, parse_heading(&1, today)})

    problems = for {heading, {:error, reason}} <- parsed, do: "\"## #{heading}\": #{reason}"

    if problems != [] do
      Mix.raise("Not ready: CHANGELOG.md has invalid headings:\n  " <> Enum.join(problems, "\n  "))
    end

    for {_heading, {:ok, version}} <- parsed, do: version
  end

  defp parse_heading(heading, today) do
    case Regex.run(~r{^v?(\d+\.\d+\.\d+\S*)(?:\s+/\s+(\S+))?$}, heading) do
      [_, version] ->
        {:error, "missing release date (expected \"## v#{version} / YYYY-MM-DD\")"}

      [_, version, date] ->
        check_date(version, date, today)

      nil ->
        if semver?(heading),
          do: {:error, "malformed version heading (expected \"## vX.Y.Z / YYYY-MM-DD\")"},
          else: pending()
    end
  end

  # Any heading that doesn't start with a version (`NEXT`, `Unreleased`, ...)
  # is a placeholder for a release that isn't decided yet.
  defp pending, do: {:error, "pending: no release version yet"}

  defp semver?(heading), do: Regex.match?(~r/^v?\d+\.\d+\.\d+/, heading)

  defp check_date(version, date, today) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        if Date.diff(date, today) > @max_days_ahead do
          {:error, "release date #{date} is more than #{@max_days_ahead} days in the future"}
        else
          {:ok, version}
        end

      {:error, _} ->
        {:error, "invalid release date #{inspect(date)} (expected YYYY-MM-DD)"}
    end
  end

  defp read_lines!(path) do
    case File.read(path) do
      {:ok, content} -> String.split(content, ~r/\R/)
      {:error, reason} -> Mix.raise("Cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp section!(lines, version) do
    heading = ~r/^## v?#{Regex.escape(version)}(\s|$)/

    notes =
      lines
      |> Enum.drop_while(&(not Regex.match?(heading, &1)))
      |> Enum.drop(1)
      |> Enum.take_while(&(not String.starts_with?(&1, "## ")))
      |> Enum.join("\n")
      |> String.trim()

    if notes == "" do
      Mix.raise("No CHANGELOG.md section found for #{version}")
    end

    notes <> "\n"
  end
end

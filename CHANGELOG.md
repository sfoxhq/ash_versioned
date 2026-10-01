# `ash_versioned` Changelog

## v0.1.0 / 2026-10-02

Initial release. Implements SCD2 (slowly-changing-dimension type 2) versioning
for Ash resources: every mutation appends a new row instead of updating in
place, so no historical value is ever overwritten.

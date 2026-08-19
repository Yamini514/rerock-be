Sequel.migration do
  # Data-only migration — folds Property's old, second "archived" flag into
  # the unified `publish_status` lifecycle now that public visibility is
  # governed solely by `publish_status == 'Published'` (see
  # services/public_properties.rb's `publicly_visible_scope`/`publicly_visible?`,
  # updated alongside this). Every Property that was archived under the old
  # two-flag system becomes `publish_status: 'Archived'` here — the exact
  # value that already means the same thing in the new model — so nothing
  # silently reappears publicly just because this migration ran.
  #
  # Properties with `archived: false` are left completely untouched: their
  # existing `publish_status` (Draft/Scheduled/Published) is preserved
  # exactly as-is, never overwritten — this only ever adds the 'Archived'
  # value onto rows that were already hidden, it never invents a status for
  # a row that wasn't previously archived.
  #
  # `.exclude(publish_status: 'Archived')` makes this idempotent (a property
  # already 'Archived' both ways is skipped) and keeps `publish_at` correctly
  # nulled for every row this touches, matching the new "Archived always has
  # a null publish_at" rule enforced going forward by models/property.rb.
  #
  # The `archived` column itself is deliberately NOT dropped or altered
  # here — same "retire from app logic first, decide on dropping the column
  # in a separate migration later" precedent as PropertyType's own
  # migrations/0079_deactivate_independent_house_and_farmhouse_property_types.rb.
  up do
    from(:properties)
      .where(archived: true)
      .exclude(publish_status: 'Archived')
      .update(publish_status: 'Archived', publish_at: nil)
  end

  # Not meaningfully reversible: once a row's publish_status has been set to
  # 'Archived' here, its original pre-migration value (was it already
  # 'Archived' via publish_status, or something else entirely?) is no longer
  # recoverable from the row alone. Left as a documented no-op rather than a
  # lossy guess, same as this codebase's other data-only migrations where a
  # clean inverse doesn't exist.
  down do
  end
end

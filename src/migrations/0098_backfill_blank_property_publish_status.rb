Sequel.migration do
  # Data-only migration — companion to migrations/0097. `publish_status`
  # defaults to 'Draft' at the column level (migrations/0012), but that
  # default only ever applies to a row that never sets the column at all.
  # PropertyForm.js's own progressive "Save & Next" always sends
  # `publish_status` in the payload — even before the admin has ever opened
  # the Publish tab, where the unselected placeholder option means it's
  # still `""` — which overwrites the column default with a blank string
  # instead of a real lifecycle value. models/property.rb's `before_validation`
  # now normalizes this going forward for every new save; this migration is
  # the one-time backfill for rows that already exist with a blank value.
  #
  # Scoped to blank only (`''`) — never touches a row that already has a
  # real value (Draft/Scheduled/Published/Archived), matching the same
  # "don't overwrite an existing publish_status" rule migrations/0097
  # follows for the `archived` -> publish_status mapping.
  up do
    from(:properties).where(publish_status: '').update(publish_status: 'Draft')
  end

  # Not reversible: a blank value becoming 'Draft' loses no information
  # (blank was never a real, distinguishable state), so there's nothing
  # meaningful to restore on rollback.
  down do
  end
end

Sequel.migration do
  change do
    # Community's existing `status` column becomes purely "Construction
    # Status" (Under Construction / Ready To Move / Completed — same
    # "Ready To Move" casing Property's own separate status enum already
    # uses, see components/ui/Badge.js's shared statusTone map) and the
    # existing `rera` free-text column becomes purely "RERA Number" — both
    # kept as-is (same column/name, no data loss) to avoid an unnecessary
    # rename migration. `rera_status` is the one genuinely new concept: a
    # real Approved/Pending/Not Registered flag, previously folded into the
    # single free-text `rera` string (e.g. "RERA Approved · P02400005678").
    # No default — existing rows simply start blank rather than being
    # silently backfilled with a guessed status.
    alter_table(:communities) do
      add_column :rera_status, String
    end
  end
end

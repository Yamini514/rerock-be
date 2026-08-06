Sequel.migration do
  change do
    # Free-text locality (e.g. "Kondapur") replaces the admin form's old
    # granular Location dropdown — Area stays a real, required dropdown
    # (it's load-bearing elsewhere: public/RAM Properties filters, map pin
    # grouping, Pricing Trends' "By Location" table all group by area_id),
    # but Location was never used as a filter anywhere, only ever to build
    # a display caption. `location_id` is relaxed to nullable since the
    # admin form no longer supplies one for new rows — existing rows keep
    # theirs untouched, and every card/detail page still resolves it for
    # older records (see PropertyCard.js/CommunityCard.js's locationLabel
    # fallback).
    alter_table(:properties) do
      add_column :locality, String
      set_column_allow_null :location_id
    end

    alter_table(:communities) do
      add_column :locality, String
      set_column_allow_null :location_id
    end
  end
end

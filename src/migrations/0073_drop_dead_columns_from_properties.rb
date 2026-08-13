Sequel.migration do
  change do
    # Four columns dropped as part of the Property module cleanup — none of
    # them had any admin UI reading/writing them going forward, and each
    # duplicated something that already lives elsewhere:
    #   - pricing_trend: Property never had a form field for this; the real,
    #     admin-maintained price history now lives on Community
    #     (price_histories table, see services/communities.rb), which is the
    #     correct level for project-wide pricing trend anyway.
    #   - investment_score: same story — Community already has its own real
    #     investment_score column with its own admin field; Property never
    #     needs an independent one (services/properties.rb's own
    #     min_investment_score filter already queried Community's, not
    #     Property's, even before this migration).
    #   - created_date: pure duplicate of the real `created_at` timestamp
    #     Sequel already maintains; nothing in the admin UI ever read or
    #     wrote this second column.
    #   - rera: a lone boolean on Property that duplicated Community's own
    #     (now much richer) rera_status/rera columns — RERA information
    #     belongs to the Community/project, not the individual unit.
    alter_table(:properties) do
      drop_column :pricing_trend
      drop_column :investment_score
      drop_column :created_date
      drop_column :rera
    end
  end
end

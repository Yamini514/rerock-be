Sequel.migration do
  change do
    # Community-level "explore by configuration" floor plans — distinct from
    # Property#floor_plans (migrations/0012), which represents a single
    # listed unit's plan. This is a project-wide gallery: one master plan
    # image plus a jsonb array of `{id, configuration, name, area, image,
    # active}` rows, same array-column-on-parent convention already used for
    # Community#gallery/#documents/#nearby (no join table, no child table —
    # see ARCHITECTURE.md / services/base.rb's comments on why). `configuration`
    # is validated in models/community.rb against the community's own
    # `unit_types`, same convention as Property#configuration.
    alter_table(:communities) do
      add_column :master_plan_image, String
      add_column :floor_plans, :jsonb, default: '[]'
    end
  end
end

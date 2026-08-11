Sequel.migration do
  change do
    # Community `type` (Apartment/Villa/Commercial) dropped — a community can
    # hold properties of multiple types, and this static field was never
    # linked to Property's real property_type_id; not shown anywhere on the
    # public site (only the admin Communities list/filter and add/edit form
    # read it, both updated to stop referencing it before this migration).
    alter_table(:communities) do
      drop_column :type
    end
  end
end

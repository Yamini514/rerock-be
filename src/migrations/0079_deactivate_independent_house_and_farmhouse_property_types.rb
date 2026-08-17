Sequel.migration do
  # Independent House and Farmhouse move to inactive by default in the admin's
  # property type taxonomy (sample_data.rb's PROPERTY_TYPES seeds them
  # `active: false` too, but `find_or_create` only sets attributes the very
  # first time a row is created — this is what actually flips the two rows on
  # any environment that already seeded them before this change). Rows are
  # deactivated, not deleted: existing Property records may already reference
  # either type via `property_type_id`, and PropertyTypes#destroy (see
  # services/property_types.rb) already refuses to delete a type with
  # listings attached.
  up do
    from(:property_types).where(name: ['Independent House', 'Farmhouse']).update(active: false)
  end

  down do
    from(:property_types).where(name: ['Independent House', 'Farmhouse']).update(active: true)
  end
end

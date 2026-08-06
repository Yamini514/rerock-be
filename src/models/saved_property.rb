class App::Models::SavedProperty < Sequel::Model
  many_to_one :client
  many_to_one :property
end

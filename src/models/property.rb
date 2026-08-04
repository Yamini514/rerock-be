class App::Models::Property < Sequel::Model
  many_to_one :community
  many_to_one :builder
  many_to_one :area
  many_to_one :location
  many_to_one :property_type
end

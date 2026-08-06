class App::Models::Lead < Sequel::Model
  many_to_one :property
  many_to_one :community
  many_to_one :area
  many_to_one :client
end

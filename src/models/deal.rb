class App::Models::Deal < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :site_visit
end

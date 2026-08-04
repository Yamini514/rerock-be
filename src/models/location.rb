class App::Models::Location < Sequel::Model
  many_to_one :area
end

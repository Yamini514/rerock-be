class App::Models::Community < Sequel::Model
  many_to_one :builder
  many_to_one :area
  many_to_one :location
end

class App::Models::Area < Sequel::Model
  one_to_many :locations
end

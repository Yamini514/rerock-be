class App::Models::Review < Sequel::Model
  many_to_one :client
end

class App::Models::Payment < Sequel::Model
  many_to_one :deal
  many_to_one :client
end

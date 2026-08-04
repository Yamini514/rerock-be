class App::Models::Tax < Sequel::Model
  many_to_one :deal
end

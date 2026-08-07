class App::Models::PriceHistory < Sequel::Model
  many_to_one :community
end

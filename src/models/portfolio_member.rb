class App::Models::PortfolioMember < Sequel::Model
  many_to_one :ram_member
end

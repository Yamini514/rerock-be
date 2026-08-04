class App::Models::SiteVisit < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :community
end

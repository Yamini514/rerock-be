class App::Models::ReferralLink < Sequel::Model
  many_to_one :property
end

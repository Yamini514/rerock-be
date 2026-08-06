class App::Models::NotificationRead < Sequel::Model
  many_to_one :notification
end

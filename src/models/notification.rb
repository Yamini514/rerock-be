class App::Models::Notification < Sequel::Model
  one_to_many :notification_reads
end

class App::Models::Role < Sequel::Model
  one_to_many :users

  def permission_flags
    permissions || []
  end
end

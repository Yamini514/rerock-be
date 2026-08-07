class App::Models::Builder < Sequel::Model
  # Defense-in-depth under BuilderForm.js's own client-side checks. `slug`
  # uniqueness mirrors the already-existing DB unique index
  # (migrations/0005).
  def validate
    super
    validates_presence [:name, :slug]
    validates_unique :slug
  end
end

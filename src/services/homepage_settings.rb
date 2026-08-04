class App::Services::HomepageSettings < App::Services::Base
  def model; HomepageSetting; end

  # Singleton settings row — see migrations/0034_create_homepage_settings.rb.
  # Overrides Base#item entirely: there's exactly one row, found (or
  # lazily created with blank defaults) on first access, so neither the
  # route nor the frontend ever needs to know/pass an id. Base's inherited
  # #get/#update both just call `item` with no arguments, so this override
  # is all that's needed for both to work against the singleton.
  def item
    @item ||= model.first || model.create(investors_label: '', rating_label: '')
  end

  def self.fields
    {
      save: [
        :investors_label, :rating_label
      ]
    }
  end
end

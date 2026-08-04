class App::Services::HeroStats < App::Services::Base
  def model; HeroStat; end

  # Mirrors lib/data/homeContent.js's heroStats[]: the hero section renders
  # these in sequence (stat1..stat4), and the mock has no separate
  # display_order concept — it's just the literal array order. Ordering by
  # :id ascending reproduces that (new stats append at the end, matching
  # insertion order) without adding a dead display_order column, same
  # judgment call as Amenities/Property Tags skipping it.
  def list
    return_success(model.order(:id).all.map(&:to_pos))
  end

  # No archive/restore/status concept — every field rides the standard
  # PUT/update, same as FAQs/SEO Pages.
  def self.fields
    {
      save: [
        :label, :value, :suffix
      ]
    }
  end
end

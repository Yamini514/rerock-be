class App::Services::Blogs < App::Services::Base
  def model; Blog; end

  # Mirrors lib/data/blogs.js: newest-first (publish date is what the
  # Journal's own ordering cares about, same reasoning as Leads' recency
  # order), search by title OR category, plus an exact status filter for the
  # admin page's Draft/Published toggle.
  def list
    ds = model.order(Sequel.desc(:date), Sequel.desc(:id))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      # NOTE: deliberately NOT services/users.rb's `.where(a).or(b)` idiom —
      # see services/leads.rb's comment. `Dataset#or` ORs against the whole
      # existing WHERE clause, which would swallow the status filter above
      # whenever a search term is also present. Combining the two LIKEs with
      # `|` first, then ANDing the combined expression in, keeps both.
      ds = ds.where(
        Sequel.like(:title, term, case_insensitive: true) | Sequel.like(:category, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore concept here (same as Leads/Blogs' own mock — just a
  # plain delete). Draft/Published status changes and content edits all ride
  # the standard PUT/update below; `content`/`author` are whitelisted like any
  # other saveable field — the frontend sends the whole array/object back on
  # every change, same "no per-entry whitelisting" convention as
  # Property#floor_plans / Lead#timeline.
  def self.fields
    {
      save: [
        :slug, :title, :excerpt, :image, :category, :date, :read_time,
        :author, :content, :status
      ]
    }
  end
end

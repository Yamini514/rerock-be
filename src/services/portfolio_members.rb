class App::Services::PortfolioMembers < App::Services::Base
  def model; PortfolioMember; end

  # Mirrors lib/data/staff.js's portfolioMembers: search by name/email, plus
  # an exact filter for ram_member_id (RAM detail page's "Portfolio Members"
  # tab, matching the assignment made real by migrations/0021).
  SORTABLE_COLUMNS = %w[name email clients_managed aum rating created_at].freeze

  def list
    ds = model
    ds = ds.where(ram_member_id: qs[:ram_member_id]) if qs[:ram_member_id].present?
    if qs[:search].present?
      # Same fix as ram_members.rb/agents.rb/leads.rb/etc.: `Dataset#or` ORs
      # the new condition against the dataset's *entire* existing WHERE
      # clause, which would swallow the ram_member_id filter above whenever a
      # search term is also present. Combine the two LIKEs with `|` first,
      # then AND the combined expression in with `where`.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) | Sequel.like(:email, term, case_insensitive: true)
      )
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  # Assigning/reassigning a RAM (ram_member_id) and every other field all ride
  # the standard PUT/update below, whitelisted like any other saveable column.
  def self.fields
    {
      save: [
        :name, :email, :avatar, :clients_managed, :aum, :rating, :ram_member_id
      ]
    }
  end
end

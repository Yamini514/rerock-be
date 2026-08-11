class App::Services::RamMembers < App::Services::Base
  def model; RamMember; end

  # Mirrors lib/data/staff.js's ramTeam: search by name/email, plus exact
  # filters for status/region.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(region: qs[:region]) if qs[:region].present?
    if qs[:search].present?
      # Same fix as agents.rb/leads.rb/clients.rb/etc.: `Dataset#or` ORs the
      # new condition against the dataset's *entire* existing WHERE clause,
      # which would swallow the status/region filters above whenever a search
      # term is also present. Combine the two LIKEs with `|` first, then AND
      # the combined expression in with `where`.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) | Sequel.like(:email, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Admin-invite path — second way to get a RAM account, alongside the
  # existing self-registration flow (RamAuth#register, which lands as
  # `status: "Pending"` awaiting approval). An admin-created account is
  # already vetted by the admin creating it, so this skips that gate
  # entirely: real password, generated here, never typed by the admin and
  # never shown in the admin UI — same exact pattern as
  # Client#send_temporary_password_email (services/clients.rb#create).
  # `must_change_password` forces one real password change before the temp
  # one can be reused indefinitely (RamAuth#update_password/#reset_password
  # clear the flag once that happens).
  def create
    ram = RamMember.new(data_for(:save))
    ram.status = "Active" if ram.status.blank?

    temp_password = SecureRandom.alphanumeric(10)
    ram.password = temp_password
    ram.must_change_password = true

    save(ram) do |o|
      o.send_temporary_password_email(temp_password)
      return_success(o.to_pos)
    end
  end

  # Status changes (Active/Pending/Inactive, including the "Approve" row
  # action), profile edits, and every jsonb array (recommendations, reports,
  # activities, documents) all ride the standard PUT/update below,
  # whitelisted like any other saveable column — frontend sends each array
  # back whole, already-appended, same convention as Agent#tasks/
  # #activity_log. `profile_extra` (contact/professional/bank/KYC, including
  # `phone`) was previously write-only from the RAM's own self-service portal
  # (RamAuth#update_profile) — added here so the RAM Details page's admin
  # Edit drawer can set/update it too (e.g. for admin-provisioned accounts
  # that never went through self-registration's own phone-collecting form).
  #
  # The old free-entry "Performance Metrics" fields (deals_this_quarter,
  # satisfaction, renewal_rate, avg_response_time_hours, experience_years,
  # revenue_managed, conversion_rate_pct, referral_generated, performance)
  # are intentionally no longer admin-writable here — they were never real
  # referral-derived numbers (see #stats below for the real equivalent) and
  # the RAM Portal spec wants them replaced entirely by one real setting:
  # `default_commission_rate`, the % Deal#ensure_commission_for_closure!
  # applies to this RAM's future closed deals.
  # Overridden (rather than left as Base#update) only to let the RAM know
  # their own record changed — same "notify the person whose data it is"
  # convention as Client#update's "Your profile was updated". Fires on any
  # admin edit here (status/Approve toggles included), same "any change to
  # your own record is worth a notice" scope as the Client-side equivalent.
  def update(data = nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |o|
      Notification.create(
        audience: 'ram',
        recipient_id: o.id,
        type: 'profile',
        icon: 'UserCog',
        title: 'Your profile was updated',
        message: 'Your account details were updated by our team.'
      )
      return_success(o.to_pos)
    end
  end

  def self.fields
    {
      save: [
        :slug, :name, :email, :avatar, :designation, :builder_ids, :region,
        :status, :default_commission_rate, :profile_extra,
        :recommendations, :reports, :activities, :documents
      ]
    }
  end

  # RAM Details page's top 3 stat tiles — three cheap aggregate queries
  # scoped to this RAM's real referrals/commissions (both keyed by
  # RamMember#slug, the established deferred-FK convention — see
  # migrations/0059/0060's own comments), never the jsonb `revenue_managed`/
  # `referral_generated` columns above (those are legacy free-entry KPI
  # fields off the old ramTeam mock, not real referral-derived numbers).
  # `referralsByStatus` backs the Overview tab's summary card.
  def stats
    ram = item
    referral_ds = Referral.where(ram_id: ram.slug)
    commission_ds = Commission.where(ram_id: ram.slug)

    return_success(
      'referralsCount' => referral_ds.exclude(archived: true).count,
      'revenue' => (commission_ds.sum(:sale_amount) || 0).to_i,
      'commissionEarned' => (commission_ds.where(status: %w[APPROVED PROCESSING PAID]).sum(:commission_amount) || 0).to_i,
      'referralsByStatus' => referral_ds.exclude(archived: true).group_and_count(:status).to_hash(:status, :count)
    )
  end

  # Admin-triggered password reset for an existing RAM account — the same
  # generate-and-email-a-temp-password flow #create already uses for brand
  # new accounts (RamMember#send_temporary_password_email), just re-run
  # on-demand. Never returns the password to the admin UI; the RAM changes it
  # via the portal's own existing Update Password flow (RamAuth#update_password),
  # which clears must_change_password once they do.
  def reset_password
    ram = item
    temp_password = SecureRandom.alphanumeric(10)
    ram.password = temp_password
    ram.must_change_password = true

    save(ram) do |o|
      o.send_temporary_password_email(temp_password)
      return_success('sent' => true)
    end
  end
end

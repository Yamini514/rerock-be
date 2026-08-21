class App::Services::RamMembers < App::Services::Base
  def model; RamMember; end

  # Mirrors lib/data/staff.js's ramTeam: search by name/email, plus exact
  # filters for status/region.
  #
  # `clientsManaged`/`portfolioValue` (the admin list page's other two
  # sortable columns) are deliberately NOT here — they aren't real columns
  # on this table at all, just client-computed joins against Clients'
  # invested_properties. Sorting on them would need a new aggregate query;
  # out of scope for this pass, so those two stay display-only/client-sorted.
  SORTABLE_COLUMNS = %w[name email designation region status created_at].freeze

  def list
    ds = model
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
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  # Admin-invite path — second way to get a RAM account, alongside the
  # existing self-registration flow (RamAuth#register, which lands as
  # `status: "Pending"` awaiting approval). An admin-created account is
  # already vetted by the admin creating it, so this skips that gate
  # entirely: real password, generated here, emailed the same way
  # Client#send_temporary_password_email does (services/clients.rb#create),
  # and also handed back once in this response so the admin can copy/share
  # it themselves without having to go dig it out of the RAM's inbox — it's
  # never persisted anywhere in plaintext and never returned again after
  # this one response (a later `get`/`list` never includes it). `must_change_
  # password` forces one real password change before the temp one can be
  # reused indefinitely (RamAuth#update_password/#reset_password clear the
  # flag once that happens).
  def create
    ram = RamMember.new(data_for(:save))
    ram.status = "Active" if ram.status.blank?

    temp_password = SecureRandom.alphanumeric(10)
    ram.password = temp_password
    ram.must_change_password = true

    save(ram) do |o|
      # See Clients#create's identical rescue: the row is already committed
      # by this point, so a slow/failed SMTP send must never turn into a
      # false "RAM member creation failed" response.
      begin
        o.send_temporary_password_email(temp_password)
      rescue => e
        App.logger.error("[RamMembers#create] temp password email failed for ram_member ##{o.id}: #{e.message}")
        App.logger.error(e.backtrace)
      end
      return_success(o.to_pos.merge('temp_password' => temp_password))
    end
  end

  # Dry-run validation (POST /ram/validate, routes.rb) — runs
  # RamMember#validate against whatever's been typed so far without ever
  # saving, so the Admin Portal's Add RAM modal can surface a real,
  # backend-sourced error the moment a field is blurred instead of only
  # after the full #create round-trip. Same error shape as a failed
  # #create (`return_errors!(obj.errors, 400)`, mirroring Base#save's own
  # failure branch) so the frontend's existing handleApiError needs no
  # special-casing for this vs. a real create failure.
  def validate_only
    obj = model.new(data_for(:save))
    return return_errors!(obj.errors, 400) unless obj.valid?

    return_success({})
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
        :slug, :name, :email, :avatar, :designation, :region,
        :profession, :date_of_birth,
        :status, :default_commission_rate, :profile_extra,
        :recommendations, :reports, :activities, :documents
      ]
    }
  end

  # RAM Details page's stat tiles — cheap aggregate queries scoped to this
  # RAM's real referrals/commissions/leads (all keyed by RamMember#slug, the
  # established deferred-FK convention — see migrations/0059/0060's own
  # comments), never the jsonb `revenue_managed`/`referral_generated`
  # columns above (those are legacy free-entry KPI fields off the old
  # ramTeam mock, not real referral-derived numbers). `referralsByStatus`
  # backs the Overview tab's summary card; `activeLeads`/`clients`/
  # `conversions` mirror services/ram_portal.rb#my_stats' own identical
  # computation exactly, so the admin sees the same numbers the RAM sees on
  # their own dashboard.
  def stats
    ram = item
    referral_ds = Referral.where(ram_id: ram.slug)
    commission_ds = Commission.where(ram_id: ram.slug)
    lead_ds = Lead.where(ram_id: ram.slug)

    return_success(
      'referralsCount' => referral_ds.exclude(archived: true).count,
      'revenue' => (commission_ds.sum(:sale_amount) || 0).to_i,
      'commissionEarned' => (commission_ds.where(status: %w[APPROVED PROCESSING PAID]).sum(:commission_amount) || 0).to_i,
      'referralsByStatus' => referral_ds.exclude(archived: true).group_and_count(:status).to_hash(:status, :count),
      'activeLeads' => lead_ds.where(archived: false).exclude(status: Lead::TERMINAL_STATUSES).count,
      'clients' => referral_ds.exclude(client_id: nil).select(:client_id).distinct.count,
      'conversions' => lead_ds.where(status: 'Closed').count
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
      # See Clients#create's identical rescue: the row is already committed
      # by this point, so a slow/failed SMTP send must never turn into a
      # false "reset failed" response.
      begin
        o.send_temporary_password_email(temp_password)
      rescue => e
        App.logger.error("[RamMembers#reset_password] temp password email failed for ram_member ##{o.id}: #{e.message}")
        App.logger.error(e.backtrace)
      end
      return_success('sent' => true)
    end
  end
end

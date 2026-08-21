# Client Portal's own "who have I referred" view — replaces the old
# lib/data/portfolio.js#referralSummary / lib/data/profile.js#referralHistory
# mocks, which showed the same fixed demo persona's data to every logged-in
# client (see components/portal/referrals/ReferralsClient.js). Reads the
# real self-join already on Client (referred_by_id, migrations/0017) rather
# than the separate admin-only `referrals` table (services/referrals.rb),
# whose `referrer`/`referred` columns are free-text names entered by staff
# for the CRM referral program and aren't reliably linkable back to a real
# Client row. Reward/earnings totals therefore aren't included here yet —
# only the real, verifiable "who signed up with my code" list/count.
class App::Services::ClientReferrals < App::Services::Base
  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    referred = Client.where(referred_by_id: client.id).order(Sequel.desc(:created_at)).all

    return_success(
      'referralCode' => client.referral_code,
      'referralsCount' => referred.size,
      'referrals' => referred.map { |c| referral_brief(c) }
    )
  end

  # Direct "Invite a Friend" — the client personally sourcing a new
  # prospect into the business (name/email/phone, no click/link needed at
  # all), same shape as RamPortal#create_my_referral's own direct referral
  # but without a property/community picker — an invite isn't about a
  # specific property. Shares the exact same Base#create_referral_with_lead!
  # (dedupe + Lead + Referral, one transaction) every other referral path
  # uses.
  def invite
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    name = params[:name]&.strip
    email = params[:email]&.strip&.downcase
    phone = params[:phone]&.strip

    return_errors!("Their name is required.", 400) if name.blank?
    return_errors!("Their phone number is required.", 400) if phone.blank?

    lead, = create_referral_with_lead!(
      name: name, phone: phone, email: email.presence,
      property_id: nil, referrer_client_id: client.id, referrer_name: client.name,
      type: "Client Referral", source: "Client Referral"
    )

    Notification.create(
      audience: "admin",
      type: "referral",
      icon: "Gift",
      title: "New referral",
      message: "#{client.name} referred a new prospect: #{name}."
    )

    return_success("Invite sent — we'll be in touch with #{name} shortly.")
  end

  # Read-only — reward/payout/status transitions all stay admin-only via
  # services/commissions.rb; this just re-exposes the client's own slice of
  # that real table, same convention as RamPortal#my_commissions. Unlike
  # that RAM version, this merges in the linked Deal's own `property_name`
  # server-side (a client has no `useMyDeals` of their own to resolve it
  # from, unlike RAM's IncomeClient.js, which cross-references its own
  # my_referrals/usePublicProperties lists client-side instead).
  def commissions
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    rows = Commission.where(client_id: client.id).order(Sequel.desc(:created_at)).all
    return_success(rows.map { |c| c.to_pos.merge('property_name' => c.deal&.property_name) })
  end

  private

  # Safe-fields only — a client can see that someone joined using their code,
  # never that client's email/phone/password/etc (same "safe directory"
  # convention as services/public_agents.rb/public_ram.rb).
  def referral_brief(referred_client)
    {
      'id' => referred_client.id,
      'name' => referred_client.name,
      'joined' => referred_client.created_at,
      'status' => referred_client.status
    }
  end
end

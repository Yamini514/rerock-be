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

  private

  # Safe-fields only — a client can see that someone joined using their code,
  # never that client's email/phone/password/etc (same "safe directory"
  # convention as services/public_agents.rb/public_ram.rb).
  def referral_brief(referred_client)
    {
      'name' => referred_client.name,
      'joined' => referred_client.created_at,
      'status' => referred_client.status
    }
  end
end

require"roda"
class App::Routes < Roda
  include App::Router::AllPlugins
  plugin :not_found do
    { status: 'error', data: 'Not Found' }
  end

  # Maps a do_crud'd resource's class name to the real permission-module key
  # already defined and assignable via the Roles admin UI (frontend's
  # lib/data/staff.js#permissionModules) — NOT a mechanical klass.name
  # derivation, since several backend resource names don't match their real
  # module key 1:1 (MediaItems -> "mediaLibrary", Agents -> "agentNetwork",
  # Blogs/Testimonials -> the combined "marketing" bucket that role's own
  # description groups them under). Resources with NO entry here are
  # deliberately left unenforced (product decision, not an oversight) rather
  # than guessed at or blocked outright — many do_crud'd resources (Reviews,
  # Approvals, SeoPages, HeroStats, Invoices, Payments, Refunds, Taxes,
  # FollowUps, Leads, Clients, Deals, Collections, Amenities, PropertyTags,
  # ...) have no corresponding module in the taxonomy at all yet, and a
  # mechanical "block everyone but super admin" default would lock out real
  # staff using those features today.
  RESOURCE_PERMISSION_MODULES = {
    'Communities' => 'communities',
    'Properties' => 'properties',
    'PropertyTypes' => 'propertyTypes',
    'Builders' => 'builders',
    'Locations' => 'locations',
    'Areas' => 'areas',
    'Agents' => 'agentNetwork',
    'MediaItems' => 'mediaLibrary',
    'Notifications' => 'notifications',
    'Users' => 'users',
    'Roles' => 'roles',
    'ActivityLogs' => 'activityLogs',
    'AuditLogs' => 'auditLogs',
    'Blogs' => 'marketing',
    'Testimonials' => 'marketing',
    'PriceHistories' => 'pricing',
    # CRM — the real taxonomy has one flat `crm` module (not a per-resource
    # one), covering all five CRM sub-resources.
    'Leads' => 'crm',
    'Clients' => 'crm',
    'FollowUps' => 'crm',
    'SiteVisits' => 'crm',
    'Referrals' => 'crm',
  }.freeze

  ACTION_FLAGS = { 'C' => 'create', 'R' => 'view', 'L' => 'view', 'U' => 'edit', 'D' => 'delete' }.freeze

  def do_crud(klass, r, only='CRUDL', opts = {})
    module_key = RESOURCE_PERMISSION_MODULES[klass.name.split('::').last]
    r.post { require_permission!(module_key, ACTION_FLAGS['C']); klass[r, opts].create } if only.include?('C')
    r.get(Integer) {|id| require_permission!(module_key, ACTION_FLAGS['R']); klass[r, opts.merge(id: id)].get} if only.include?('R')
    r.get { require_permission!(module_key, ACTION_FLAGS['L']); klass[r, opts].list } if only.include?('L')
    r.put(Integer) {|id| require_permission!(module_key, ACTION_FLAGS['U']); klass[r, opts.merge(id: id)].update } if only.include?('U')
    r.delete(Integer) {|id| require_permission!(module_key, ACTION_FLAGS['D']); klass[r, opts.merge(id: id)].delete } if only.include?('D')
  end

  # Dark-launched on purpose: fully inert (returns immediately) unless
  # ENV['ENFORCE_PERMISSIONS'] is explicitly set to 'true'. `has_permission?`
  # (helpers/current_user.rb) already short-circuits true for a super admin
  # and false for a nil user, so this only ever needs to check the flag
  # itself. `module_key` is nil for every resource not in
  # RESOURCE_PERMISSION_MODULES above — deliberately a no-op for those,
  # matching the "leave unmapped resources unenforced" decision.
  #
  # Rollout, when this environment is ready to flip the switch: backfill
  # every existing seeded Role's `permissions` array (cross-referenced
  # against real audit-log activity, which already records who did what) so
  # no currently-working staff user loses access on cutover, verify in
  # staging, THEN set ENFORCE_PERMISSIONS=true. Until that backfill happens,
  # leave this unset/false — flipping it on a live system with unaudited
  # role permissions risks locking out real staff.
  def require_permission!(module_key, action)
    return unless ENV['ENFORCE_PERMISSIONS'] == 'true'
    return if module_key.nil?

    flag = "#{module_key}.#{action}"
    unless App.cu.has_permission?(flag)
      request.halt(403, {'Content-Type' => 'application/json'}, { status: 'error', data: "Missing permission: #{flag}" }.to_json)
    end
  end

  route do |r|
    r.public

    r.root do
      File.read(File.join(App.root, 'public', 'index.html'))
    end

    r.on 'admin' do
      r.get do
        File.read(File.join(App.root, 'public', 'index.html'))
      end
    end

    r.on 'api' do
      r.response['Content-Type'] = 'application/json'
      
      # Public endpoints (no auth required)
      r.post('login') { Session[r].login }
      r.post('forgot-password') { Users[r].forgot_password }
      r.post('validate-password-token') { Users[r].validate_password_token }
      r.post('reset-password') { Users[r].reset_password }

      r.get 'version' do
        { status: 'success', version: 1 }
      end

      # RAM Portal — the self-service member portal's own auth (register/
      # login/forgot-password/reset-password), wholly separate from the
      # Admin Portal's `users`-based login above. RAM members aren't `users`
      # rows (no role_id/is_super_admin/staff?), so this can't ride
      # Session/Users/auth_required! — it has its own JWT (CurrentRam,
      # helpers/current_ram.rb) and its own guard (ram_auth_required!,
      # below). `/api/ram` (admin-only RamMembers CRUD, further down) is
      # untouched by any of this.
      r.on 'ram-portal' do
        r.post('register') { RamAuth[r].register }
        r.post('login') { RamAuth[r].login }
        r.post('forgot-password') { RamAuth[r].forgot_password }
        r.post('validate-password-token') { RamAuth[r].validate_password_token }
        r.post('reset-password') { RamAuth[r].reset_password }

        ram_auth_required!

        r.on 'me' do
          r.get('info') { RamAuth[r].info }
          r.put('update') { RamAuth[r].update_profile }
          r.put('update-password') { RamAuth[r].update_password }

          # Admin-broadcast notifications targeted at audience "ram" — see
          # services/ram_notifications.rb. Read state is per-RAM-member
          # (notification_reads join table), not a shared column.
          r.on 'notifications' do
            r.get { RamNotifications[r].mine }
            r.post('mark-all-read') { RamNotifications[r].mark_all_read }
            r.post(Integer) { |id| RamNotifications[r, id: id].mark_read }
          end

          # The RAM's own assigned clients — see services/ram_portal.rb.
          r.on 'clients' do
            r.get { RamPortal[r].my_clients }
          end

          # Create-only: capture a brand-new contact (no portal account yet)
          # as a real Lead — see services/ram_portal.rb#create_my_lead.
          r.on 'leads' do
            r.post { RamPortal[r].create_my_lead }
          end

          # The RAM's own referral-program entries — see
          # services/ram_portal.rb#my_referrals/#create_my_referral/
          # #update_my_referral. Status-only update; reward/payout stay
          # admin-set via the real (admin) Referrals CRUD further down.
          r.on 'referrals' do
            r.get { RamPortal[r].my_referrals }
            r.post { RamPortal[r].create_my_referral }
            r.put(Integer) { |id| RamPortal[r, id: id].update_my_referral }
          end

          # "Recommend Property" to one of the RAM's own assigned clients —
          # see services/ram_recommendations.rb. Backs the real "My
          # Recommendations" page (previously lib/data/recommendations.js's
          # in-memory mock).
          r.on 'recommendations' do
            r.post { RamRecommendations[r].create }
            r.get('mine') { RamRecommendations[r].mine }
            r.put(Integer) { |id| RamRecommendations[r, id: id].update }
          end
        end
      end

      # Client Portal — the self-service retail-investor portal's own auth
      # (register/verify-otp/resend-otp/login/forgot-password/reset-password),
      # wholly separate from both the Admin Portal's `users`-based login and
      # the RAM Portal's `ram-portal` block above. Clients aren't `users` or
      # `ram_members` rows, so this has its own JWT (CurrentClient,
      # helpers/current_client.rb) and its own guard (client_auth_required!,
      # below). `/api/clients` (admin-only Clients CRM CRUD, further down) is
      # untouched by any of this.
      r.on 'client-portal' do
        r.post('register') { ClientAuth[r].register }
        r.post('verify-otp') { ClientAuth[r].verify_otp }
        r.post('resend-otp') { ClientAuth[r].resend_otp }
        r.post('login') { ClientAuth[r].login }
        r.post('forgot-password') { ClientAuth[r].forgot_password }
        r.post('validate-password-token') { ClientAuth[r].validate_password_token }
        r.post('reset-password') { ClientAuth[r].reset_password }

        client_auth_required!

        r.on 'me' do
          r.get('info') { ClientAuth[r].info }
          r.put('update') { ClientAuth[r].update_profile }
          r.put('update-password') { ClientAuth[r].update_password }

          # A minimal, safe-fields directory (never the sensitive admin
          # #to_pos shape) so the portal can resolve the client's own
          # assigned agent/RAM to a name/avatar/contact — see
          # components/portal/AdvisorCard.js and services/public_agents.rb
          # / public_ram.rb's own comments on why this isn't reused from the
          # fully-open 'public' block below.
          r.get('agents') { PublicAgents[r].list }
          r.get('ram') { PublicRam[r].list }

          # Client-submitted ratings/reviews on the client's own assigned
          # agent/RAM or a property/builder/community they've actually
          # purchased into — see services/client_reviews.rb for the
          # ownership checks. Every fresh submission is Pending until an
          # admin approves it (/admin/reviews).
          r.on 'reviews' do
            r.post { ClientReviews[r].create }
            r.get('mine') { ClientReviews[r].mine }
          end

          # Admin-broadcast notifications targeted at audience "client" —
          # see services/client_notifications.rb. Read state is
          # per-client (notification_reads join table), not a shared column.
          r.on 'notifications' do
            r.get { ClientNotifications[r].mine }
            r.post('mark-all-read') { ClientNotifications[r].mark_all_read }
            r.post(Integer) { |id| ClientNotifications[r, id: id].mark_read }
          end

          # Logged-in-client "Book a Site Visit" — see
          # services/client_site_visits.rb (the guest counterpart is the
          # public services/public_site_visits.rb).
          r.on 'site-visits' do
            r.post { ClientSiteVisits[r].create }
            r.get { ClientSiteVisits[r].mine }
          end

          # Document upload — see services/client_documents.rb.
          r.on 'documents' do
            r.post { ClientDocuments[r].create }
            r.get { ClientDocuments[r].mine }
          end

          # Client's "Saved" (uncapped) and "Shortlist" (capped at 2,
          # comparison) property lists — see
          # services/client_saved_properties.rb. Row existence in a single
          # table (distinguished by `kind`) is membership; `create`/`destroy`
          # are both idempotent, matching the Heart/Shortlist buttons' own
          # fire-and-forget sync.
          r.on 'saved-properties' do
            r.get { ClientSavedProperties[r].mine }
            r.post { ClientSavedProperties[r].create }
            r.post('remove') { ClientSavedProperties[r].destroy }
          end

          # The client's own referral code + who has signed up using it — see
          # services/client_referrals.rb for why this reads the real
          # Client#referred_by_id self-join instead of the separate,
          # name-matched admin `referrals` table.
          r.get('referrals') { ClientReferrals[r].mine }
        end
      end

      # Agent Portal — the sales-agent self-service portal's own auth
      # (register/login/forgot-password/reset-password), wholly separate
      # from the Admin/RAM/Client Portal auth blocks above. Registration
      # lands as status "Pending" and needs admin approval (/admin/agents)
      # before login succeeds — see services/agent_auth.rb. Its own JWT
      # (CurrentAgent, helpers/current_agent.rb) and its own guard
      # (agent_auth_required!, below). `/api/agents` (admin-only Agents CRUD,
      # further down) is untouched by any of this.
      r.on 'agent-portal' do
        r.post('register') { AgentAuth[r].register }
        r.post('login') { AgentAuth[r].login }
        r.post('forgot-password') { AgentAuth[r].forgot_password }
        r.post('validate-password-token') { AgentAuth[r].validate_password_token }
        r.post('reset-password') { AgentAuth[r].reset_password }

        agent_auth_required!

        r.on 'me' do
          r.get('info') { AgentAuth[r].info }
          r.put('update') { AgentAuth[r].update_profile }
          r.put('update-password') { AgentAuth[r].update_password }

          # Scoped CRM data — an agent's own book of business, filtered
          # server-side to their own agent_slug/assigned_agent_slug on every
          # read, with an ownership check on every write (see
          # services/agent_portal.rb). Deals/Leads/SiteVisits/Clients are
          # all real, already-built Admin Portal resources
          # (services/deals.rb, leads.rb, site_visits.rb, clients.rb) — this
          # doesn't duplicate their logic, just re-exposes a scoped slice of
          # the same tables to a non-admin (agent) token.
          r.on 'deals' do
            r.get { AgentPortal[r].my_deals }
            r.put(Integer) { |id| AgentPortal[r, id: id].update_my_deal }
          end

          r.on 'leads' do
            r.get { AgentPortal[r].my_leads }
            r.put(Integer) { |id| AgentPortal[r, id: id].update_my_lead }
          end

          r.on 'site-visits' do
            r.get { AgentPortal[r].my_site_visits }
            r.post { AgentPortal[r].create_my_site_visit }
            r.put(Integer) { |id| AgentPortal[r, id: id].update_my_site_visit }
          end

          r.on 'clients' do
            r.get { AgentPortal[r].my_clients }
          end

          # Admin-assigned Follow Ups scoped to this agent (real agent_id
          # FK, unlike deals/leads/site-visits' agent_slug above) — see
          # services/agent_portal.rb#my_follow_ups/#update_my_follow_up.
          r.on 'follow-ups' do
            r.get { AgentPortal[r].my_follow_ups }
            r.put(Integer) { |id| AgentPortal[r, id: id].update_my_follow_up }
          end

          # Admin-broadcast notifications targeted at audience "agent" —
          # see services/agent_notifications.rb. Read state is per-agent
          # (notification_reads join table), not a shared column.
          r.on 'notifications' do
            r.get { AgentNotifications[r].mine }
            r.post('mark-all-read') { AgentNotifications[r].mark_all_read }
            r.post(Integer) { |id| AgentNotifications[r, id: id].mark_read }
          end

          # "Recommend Property" to one of the agent's own assigned clients
          # — see services/agent_recommendations.rb. Replaces
          # components/agent/RecommendModal.js's old toast-only stub.
          r.on 'recommendations' do
            r.post { AgentRecommendations[r].create }
            r.get('mine') { AgentRecommendations[r].mine }
          end

          # Client documents awaiting the agent's verification — see
          # services/agent_portal.rb#my_documents/#verify_my_document.
          r.on 'documents' do
            r.get { AgentPortal[r].my_documents }
            r.put(Integer) { |id| AgentPortal[r, id: id].verify_my_document }
          end

          # Performance page — YTD summary tiles (agent's own real aggregate
          # columns) plus a 6-month trend computed from this agent's own
          # Leads/Deals/SiteVisits/Reviews. See services/agent_portal.rb#my_performance.
          r.on 'performance' do
            r.get { AgentPortal[r].my_performance }
          end
        end
      end

      # Public, read-only catalog browsing — no auth at all. Used by the RAM
      # Portal's Properties browse + "Recommend Property" flow (which has no
      # admin session to spend) and, eventually, the public (site) app.
      # Reuses the exact same Properties/Builders services/models as the
      # Admin Portal's own CRUD below — Read + List only ('RL'), no
      # create/update/delete route is ever registered here.
      r.on 'public' do
        r.on 'properties' do
          do_crud(Properties, r, 'RL')
        end

        r.on 'builders' do
          do_crud(Builders, r, 'RL')
        end

        # Curated property groupings for the public site — see
        # services/collections.rb. The frontend always passes `active=true`
        # so inactive/draft collections never leak publicly; the "Featured
        # Properties" virtual collection is never a real row here (see that
        # service's own comment) and is synthesized client-side from
        # Properties' `featured` column instead.
        r.on 'collections' do
          do_crud(Collections, r, 'RL')
        end

        # Lookup tables needed to render/filter the properties list above
        # (community/area/location/type names) without an admin session —
        # same reuse-the-existing-service, Read+List-only pattern.
        r.on 'communities' do
          do_crud(Communities, r, 'RL')
        end

        r.on 'areas' do
          do_crud(Areas, r, 'RL')
        end

        r.on 'locations' do
          do_crud(Locations, r, 'RL')
        end

        r.on 'property-types' do
          do_crud(PropertyTypes, r, 'RL')
        end

        r.on 'amenities' do
          do_crud(Amenities, r, 'RL')
        end

        # Property tag library (colour-coded badges on property cards) — a
        # flat, uncategorised list with nothing sensitive in it, same
        # reuse-the-existing-service pattern as the lookup tables above.
        r.on 'property-tags' do
          do_crud(PropertyTags, r, 'RL')
        end

        # Approved reviews for a given entity — always forces status:
        # "Approved" server-side regardless of query params (see
        # services/public_reviews.rb), so this is safe to leave fully open.
        r.on 'reviews' do
          r.get { PublicReviews[r].list }
        end

        # Published-only blog posts (never Draft) and Approved-only
        # testimonials — dedicated services that force the status filter
        # server-side (services/public_blogs.rb / public_testimonials.rb),
        # unlike the plain do_crud reuse above.
        r.on 'blogs' do
          r.get { PublicBlogs[r].list }
        end

        r.on 'testimonials' do
          r.get { PublicTestimonials[r].list }
        end

        # FAQs / Career listings & benefits / homepage hero stats — plain
        # content with no status/moderation concept and nothing sensitive in
        # their #to_pos, so these reuse the Admin Portal's own services
        # directly (same as Properties/Builders/etc. above).
        r.on 'faqs' do
          do_crud(Faqs, r, 'RL')
        end

        r.on 'job-openings' do
          do_crud(JobOpenings, r, 'RL')
        end

        r.on 'career-benefits' do
          do_crud(CareerBenefits, r, 'RL')
        end

        r.on 'hero-stats' do
          do_crud(HeroStats, r, 'RL')
        end

        # Singleton marketing-copy row (investor/rating labels) — read-only
        # here; #update stays admin-only (routes.rb's admin block).
        r.on 'homepage-settings' do
          r.get { HomepageSettings[r].get }
        end

        # Minimal safe-fields agent directory (see services/public_agents.rb
        # — never Agents' own #to_pos, which dumps encoded_password/
        # commission data) — needed by the property-detail and Contact
        # pages' "Talk to an Advisor" cards. Same service already mounted
        # under client-portal/me/agents; publicly showing an agent's name/
        # phone/WhatsApp is the intended lead-gen UX here, not a leak.
        r.on 'agents' do
          r.get { PublicAgents[r].list }
        end

        # Public contact-form submission — creates a real Lead (source:
        # "Website") instead of the old frontend-only fake toast. See
        # services/public_contact.rb.
        r.on 'contact' do
          r.post { PublicContact[r].create }
        end

        # Public "Book a Site Visit" submission — creates a real Lead +
        # SiteVisit (source: "Website") instead of BookVisitModal's old
        # toast-only fake submit. See services/public_site_visits.rb.
        r.on 'site-visits' do
          r.post { PublicSiteVisits[r].create }
        end
      end

      # Authentication required for all routes below
      auth_required!

      # User profile routes
      r.on 'me' do
        r.get('info') { Users[r].info }
        r.put('update') { Users[r].update_profile }
        r.put('update-password') { Users[r].update_password }
      end

      # Admin-only routes
      admin_required!
      
      # Wrap all admin routes in error handling
      begin
        r.on 'users' do
          do_crud(Users, r, 'CRUDL')
        end

        r.on 'builders' do
          do_crud(Builders, r, 'CRUDL')
        end

        r.on 'property-types' do
          do_crud(PropertyTypes, r, 'CRUDL')
        end

        r.on 'areas' do
          do_crud(Areas, r, 'CRUDL')
        end

        r.on 'locations' do
          do_crud(Locations, r, 'CRUDL')
        end

        r.on 'amenities' do
          do_crud(Amenities, r, 'CRUDL')
        end

        r.on 'property-tags' do
          do_crud(PropertyTags, r, 'CRUDL')
        end

        r.on 'communities' do
          # Bulk Pricing Update — see services/communities.rb#bulk_price_update.
          # Registered before the generic do_crud catch-all so this literal
          # path matches first, same convention as notifications' own
          # 'mark-all-read' route. Gated on "pricing.edit" specifically
          # rather than "communities.edit" — Pricing is its own module in
          # the real permission taxonomy (a Finance-type role can have
          # pricing.edit without general communities.edit).
          r.post('bulk-price-update') { require_permission!('pricing', 'edit'); Communities[r].bulk_price_update }
          do_crud(Communities, r, 'CRUDL')
        end

        # Read-only Community price-change ledger — see
        # services/price_histories.rb. Rows are written only from
        # Communities#update/#bulk_price_update, never directly.
        r.on 'price-histories' do
          do_crud(PriceHistories, r, 'RL')
        end

        r.on 'properties' do
          do_crud(Properties, r, 'CRUDL')
        end

        r.on 'collections' do
          do_crud(Collections, r, 'CRUDL')
        end

        r.on 'leads' do
          do_crud(Leads, r, 'CRUDL')
        end

        r.on 'site-visits' do
          do_crud(SiteVisits, r, 'CRUDL')
        end

        r.on 'referrals' do
          do_crud(Referrals, r, 'CRUDL')
        end

        r.on 'clients' do
          do_crud(Clients, r, 'CRUDL')
        end

        r.on 'deals' do
          do_crud(Deals, r, 'CRUDL')
        end

        r.on 'agents' do
          do_crud(Agents, r, 'CRUDL')
        end

        # RAM (Relationship Advisory Members) — table/class are RamMembers/
        # ram_members (avoiding an awkward bare `ram` SQL identifier), but the
        # URL path stays 'ram' to match the frontend's existing /admin/ram route.
        r.on 'ram' do
          do_crud(RamMembers, r, 'CRUDL')
        end

        r.on 'portfolio-members' do
          do_crud(PortfolioMembers, r, 'CRUDL')
        end

        r.on 'expenses' do
          do_crud(Expenses, r, 'CRUDL')
        end

        r.on 'invoices' do
          do_crud(Invoices, r, 'CRUDL')
        end

        r.on 'payments' do
          do_crud(Payments, r, 'CRUDL')
        end

        r.on 'refunds' do
          do_crud(Refunds, r, 'CRUDL')
        end

        r.on 'taxes' do
          do_crud(Taxes, r, 'CRUDL')
        end

        # Commission and Revenue are NOT tables — computed-report endpoints
        # over the real Agents table (see services/reports.rb), mirroring
        # lib/data/finance.js's getCommissionRows()/getRevenueByAgent() etc.
        # but reading real agents.commission_earned/revenue/commission_monthly
        # instead of the mock array.
        r.get 'reports/commission' do
          Reports[r].commission
        end

        r.get 'reports/revenue' do
          Reports[r].revenue
        end

        r.on 'blogs' do
          do_crud(Blogs, r, 'CRUDL')
        end

        r.on 'testimonials' do
          do_crud(Testimonials, r, 'CRUDL')
        end

        # Moderation queue for client-submitted ratings/reviews on
        # Agents/RAM/Properties/Builders/Communities — approve/reject ride
        # the standard PUT/update like Testimonials above (services/reviews.rb).
        r.on 'reviews' do
          do_crud(Reviews, r, 'CRUDL')
        end

        r.on 'faqs' do
          do_crud(Faqs, r, 'CRUDL')
        end

        # Careers is two small resources per lib/data/careers.js
        # (openRoles[] + benefits[]), both surfaced on one combined admin
        # page — no single "Careers" table/model/service.
        r.on 'job-openings' do
          do_crud(JobOpenings, r, 'CRUDL')
        end

        r.on 'career-benefits' do
          do_crud(CareerBenefits, r, 'CRUDL')
        end

        r.on 'seo-pages' do
          do_crud(SeoPages, r, 'CRUDL')
        end

        r.on 'hero-stats' do
          do_crud(HeroStats, r, 'CRUDL')
        end

        # Homepage Content's other piece — heroSocialProof — is a singleton
        # config object (no natural "many rows" shape), not a CRUD list, so
        # it's a plain GET/PUT pair rather than do_crud: no id segment at
        # all, since HomepageSettings#item always resolves to the one
        # existing row (creating it on first access). See
        # services/homepage_settings.rb for the full reasoning.
        r.on 'homepage-settings' do
          r.get { HomepageSettings[r].get }
          r.put { HomepageSettings[r].update }
        end

        # Activity Logs — read-only: logs are system-generated, so only
        # Read + List are wired (no r.post/r.put/r.delete block is ever
        # registered for this resource, per do_crud's 'RL' arg above).
        r.on 'activity-logs' do
          do_crud(ActivityLogs, r, 'RL')
        end

        # Audit Logs — read-only, same reasoning as Activity Logs: this is a
        # polymorphic database change log (old value -> new value per
        # entity), system-generated, so only Read + List are wired (no
        # r.post/r.put/r.delete block is ever registered for this resource,
        # per do_crud's 'RL' arg above).
        r.on 'audit-logs' do
          do_crud(AuditLogs, r, 'RL')
        end

        # Notifications — the admin's own notification feed. Full CRUD
        # (unlike Activity/Audit Logs' read-only 'RL'): an admin can manually
        # create/broadcast, edit, and delete notifications from this page,
        # not just read system-generated ones. `mark-all-read` is a small
        # custom action outside do_crud's CRUDL set (backs the page's "Mark
        # all as read" button with one real UPDATE instead of the frontend
        # firing one PUT per unread row) — registered before do_crud so the
        # literal 'mark-all-read' path segment is matched first; do_crud's
        # r.put(Integer)/r.delete(Integer) only match numeric id segments, so
        # there's no conflict either way.
        r.on 'notifications' do
          r.post 'mark-all-read' do
            Notifications[r].mark_all_read
          end
          do_crud(Notifications, r, 'CRUDL')
        end

        # Media Library — metadata rows only (name/tags/uploaded_by/src as a
        # URL string). Full CRUD, same as Notifications: an admin can
        # register/edit/delete media metadata directly, not just read
        # system-generated rows. `src` is now populated from a real S3
        # upload via 'uploads/presign' below rather than a base64 data URL.
        r.on 'media-items' do
          do_crud(MediaItems, r, 'CRUDL')
        end

        # Real S3 uploads — see services/uploads.rb. One shared presign
        # endpoint for every upload surface (property images/floor
        # plans/documents, community gallery/documents, builder logos,
        # media library) rather than a route per module, since each target
        # column is just a plain string regardless of which model eventually
        # stores it. Deliberately not permission-gated per-purpose here:
        # presigning + uploading a file to S3 doesn't attach it to any
        # record by itself — the actual attach happens via that record's own
        # create/update call (e.g. Properties#update), which IS gated by
        # do_crud above. Any authenticated admin session can obtain a
        # presigned URL; only saving the resulting URL onto a real row is
        # permission-checked.
        r.on 'uploads' do
          r.post('presign') { Uploads[r].presign }
        end

        # RBAC admin pages — Roles. `users` (above) already existed pre-Foundation;
        # this is the last resource of the last roadmap phase. Permissions has
        # no route/table of its own — the fixed module x action taxonomy
        # (lib/data/staff.js's permissionModules/ALL_FLAGS) stays a frontend
        # constant, and the actual granted flags per role live on this
        # resource's own `permissions` column (see services/roles.rb).
        r.on 'roles' do
          do_crud(Roles, r, 'CRUDL')
        end

        # Follow Ups — real backing table (migrations/0040) for what was
        # previously lib/data/admin.js's local-only mock, used by both the
        # standalone /admin/follow-ups page and the Dashboard's Follow Ups
        # widget/Calendar entries. Full CRUD: an admin logs, edits
        # (reschedule/reprioritize), completes, and deletes their own
        # follow-up tasks.
        r.on 'follow-ups' do
          do_crud(FollowUps, r, 'CRUDL')
        end

        # Approvals — real backing table (migrations/0041) for the
        # Dashboard's Pending Approvals widget, previously a local-only mock
        # with no persistence (approve/reject just spliced the item out of
        # React state). Full CRUD: approve/reject ride the standard PUT as a
        # `status` transition, same convention as Testimonials.
        r.on 'approvals' do
          do_crud(Approvals, r, 'CRUDL')
        end

        # Full roadmap complete — every module above is real, migrated
        # (pending the user's own db:migrate/db:seed run), and wired to live
        # CRUD. No further placeholder comment: there is no next module.
      rescue => e
        App.logger.error("API Error: #{e.message}")
        App.logger.error(e.backtrace)
        { status: 'error', message: "An error occurred: #{e.message}" }
      end
    end

    # Fallback route
    r.get do
      File.read(File.join(App.root, 'public', 'index.html'))
    end
  end

  before do
    @time = Time.now
    App::Helpers::Before.run!(request)
  end

  after do |res|
    rtype = request.request_method
    App.logger.info("→ [#{Time.now - @time} seconds] - [#{rtype}]#{request.path}")
  end

  def auth_required!
    unless App.cu.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
    # CurrentUser#user_obj re-raises these rather than swallowing them into a
    # false "invalid session" — surface as a real 503, not a 401, so the
    # frontend doesn't treat a momentary DB hiccup as a real logout.
    App.logger.error("Auth check failed, DB unavailable: #{e.message}")
    request.halt(503, {'Content-Type' => 'application/json'}, { status: 'error', data: 'Service temporarily unavailable' }.to_json)
  end

  def admin_required!
    unless App.cu.staff?
      request.halt(403, {'Content-Type' => 'application/json'},{ status: 'Forbidden!' }.to_json)
    end
  end

  # RAM Portal's own auth gate — parallel to auth_required! above, but
  # against App::Helpers::CurrentRam (a RAM member's own JWT) instead of
  # App.cu/App::Helpers::CurrentUser (an admin/staff `users` session). A
  # valid admin token does NOT satisfy this, and a valid RAM token does not
  # satisfy auth_required!/admin_required! — the two identities are fully
  # independent, by design (see current_ram.rb's SECRET comment).
  def ram_auth_required!
    unless App::Helpers::CurrentRam.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
    App.logger.error("RAM auth check failed, DB unavailable: #{e.message}")
    request.halt(503, {'Content-Type' => 'application/json'}, { status: 'error', data: 'Service temporarily unavailable' }.to_json)
  end

  # Client Portal's own auth gate — parallel to ram_auth_required! above, but
  # against App::Helpers::CurrentClient (a client's own JWT). Independent of
  # auth_required!/admin_required!/ram_auth_required! — none of the four
  # tokens satisfy any of the others' checks.
  def client_auth_required!
    unless App::Helpers::CurrentClient.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
    App.logger.error("Client auth check failed, DB unavailable: #{e.message}")
    request.halt(503, {'Content-Type' => 'application/json'}, { status: 'error', data: 'Service temporarily unavailable' }.to_json)
  end

  # Agent Portal's own auth gate — parallel to ram_auth_required!/
  # client_auth_required! above, against App::Helpers::CurrentAgent (an
  # agent's own JWT). Fully independent of the other three guards.
  def agent_auth_required!
    unless App::Helpers::CurrentAgent.valid?
      request.halt(401, {'Content-Type' => 'application/json'},{ status: 'Unauthorized!' }.to_json)
    end
  rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
    App.logger.error("Agent auth check failed, DB unavailable: #{e.message}")
    request.halt(503, {'Content-Type' => 'application/json'}, { status: 'error', data: 'Service temporarily unavailable' }.to_json)
  end
end

App.require_blob('services/base.rb')
App.require_blob('services/*.rb')

App::Routes.send(:include, App::Services)
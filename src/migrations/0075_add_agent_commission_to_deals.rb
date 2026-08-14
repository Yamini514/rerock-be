Sequel.migration do
  change do
    # Per-agent analogue of `commissions.commission_rate`/`commission_amount`
    # (the existing RAM/referral ledger, migrations/0059) — but stamped
    # directly onto the deal itself rather than a separate table, since
    # there's no per-agent commission workflow (eligible/approved/paid) to
    # track, just the one rate/amount used at closure. Both columns are set
    # exactly once, by Deal#ensure_agent_commission_for_closure!, the moment
    # a deal tied to a real agent (`agent_slug`) first reaches `stage:
    # "Closed"` — so a later edit to Agent#commission_rate never rewrites a
    # deal's own historical commission (Agent#live_stats reads these instead
    # of recomputing from the agent's *current* rate).
    alter_table(:deals) do
      add_column :agent_commission_rate, Float
      add_column :agent_commission_amount, Integer
    end
  end
end

Sequel.migration do
  change do
    # Public Contact form submissions used to become a real Lead (see
    # services/public_contact.rb's old comment) — that mixed every "just
    # asking a question" message into the same CRM/Enquiries pipeline as
    # actual sales prospects. This table is the deliberately separate,
    # lightweight inbox instead: no status workflow, no agent/RAM
    # assignment, no Referral — just what was submitted.
    create_table(:contact_messages) do
      primary_key :id

      String :name, null: false
      String :phone
      String :email
      String :message, text: true
      # Raw referral code the visitor's browser had attributed at submit
      # time, kept only for reference — no Referral/commission tracking is
      # created from this table (services/public_contact.rb no longer calls
      # create_referral_with_lead!; that shared method is still used by
      # BookVisitModal/RAM Portal's own referral capture, untouched here).
      String :referral_code
      Boolean :read, default: false

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :created_at
      index :read
    end
  end
end

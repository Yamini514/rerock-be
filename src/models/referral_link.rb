class App::Models::ReferralLink < Sequel::Model
  many_to_one :property
  many_to_one :ram_member

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_ram_reference! — see that file's comment.
  def before_validation
    if new?
      if ram_member_id.present?
        self.ram_id = App::Models::RamMember[ram_member_id]&.slug
      elsif ram_id.present?
        self.ram_member_id = App::Models::RamMember.where(slug: ram_id).first&.id
      end
    elsif column_changed?(:ram_member_id)
      self.ram_id = ram_member_id.present? ? App::Models::RamMember[ram_member_id]&.slug : nil
    elsif column_changed?(:ram_id)
      self.ram_member_id = ram_id.present? ? App::Models::RamMember.where(slug: ram_id).first&.id : nil
    end
    super
  end
end

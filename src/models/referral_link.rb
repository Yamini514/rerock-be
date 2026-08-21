class App::Models::ReferralLink < Sequel::Model
  many_to_one :property
  many_to_one :ram_member
  many_to_one :client

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

  # A link is owned by exactly one of a RAM member or a Client — never both,
  # never neither. Enforced here rather than a DB constraint (migrations/
  # 0104's own comment on why).
  def validate
    super
    if ram_member_id.blank? && client_id.blank?
      errors.add(:base, 'must belong to either a RAM member or a client')
    elsif ram_member_id.present? && client_id.present?
      errors.add(:base, 'cannot belong to both a RAM member and a client')
    end
  end
end

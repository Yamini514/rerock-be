class App::Services::PublicReviews < App::Services::Base
  def model; Review; end

  # Unauthenticated, read-only — always forces status: "Approved" regardless
  # of any query param, so a Pending/Rejected review (which may contain a
  # not-yet-moderated complaint) can never leak publicly. Requires an exact
  # reviewable_type/reviewable_id pair rather than allowing an unscoped dump
  # of every review in the system.
  def list
    return_errors!("reviewable_type and reviewable_id are required.", 400) if qs[:reviewable_type].blank? || qs[:reviewable_id].blank?

    ds = model.where(
      status: 'Approved',
      reviewable_type: qs[:reviewable_type],
      reviewable_id: qs[:reviewable_id].to_i
    ).order(Sequel.desc(:created_at))
    return_success(ds.all.map(&:to_pos))
  end
end

# Client Portal's "Saved" (uncapped favorites) and "Shortlist" (capped at
# SHORTLIST_LIMIT, side-by-side comparison) property lists — replaces
# lib/store/savedPropertiesStore.js's and lib/store/shortlistStore.js's old
# localStorage-only persistence (nothing was ever sent to the backend, so
# neither list survived a different browser/device — see clientApiClient.js's
# own comment on that gap). Same table for both, distinguished by `kind`; row
# existence = "in this list", same convention as ClientNotifications'
# NotificationRead. `create`/`destroy` are both idempotent (not
# add-only/404-on-missing) since the frontend stores call these best-effort,
# fire-and-forget, with no per-call error-handling UI — ClientAuthContext.js's
# login-time hydration is what corrects any drift a failed call leaves behind.
class App::Services::ClientSavedProperties < App::Services::Base
  def model; SavedProperty; end

  SHORTLIST_LIMIT = 2
  KINDS = %w[saved shortlist]

  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    kind = params[:kind].presence
    return_errors!("Invalid kind.", 400) if kind.present? && !KINDS.include?(kind)

    return_success(scope(client.id, kind).map { |sp| property_brief(sp) })
  end

  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    kind = params[:kind].presence || "saved"
    return_errors!("Invalid kind.", 400) unless KINDS.include?(kind)

    property_slug = params[:property_slug]&.strip
    return_errors!("A property is required.", 400) if property_slug.blank?

    property = Property.first(slug: property_slug)
    return_errors!("Property not found.", 404) if property.nil?

    unless SavedProperty.where(client_id: client.id, property_id: property.id, kind: kind).first
      if kind == "shortlist" && SavedProperty.where(client_id: client.id, kind: "shortlist").count >= SHORTLIST_LIMIT
        return_errors!("Shortlist is full (#{SHORTLIST_LIMIT}/#{SHORTLIST_LIMIT}). Remove one to add another.", 400)
      end
      SavedProperty.create(client_id: client.id, property_id: property.id, kind: kind)
    end

    return_success(scope(client.id, kind).map { |sp| property_brief(sp) })
  end

  def destroy
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    kind = params[:kind].presence || "saved"
    property_slug = params[:property_slug]&.strip
    return_errors!("A property is required.", 400) if property_slug.blank?

    property = Property.first(slug: property_slug)
    SavedProperty.where(client_id: client.id, property_id: property.id, kind: kind).delete if property

    return_success(scope(client.id, kind).map { |sp| property_brief(sp) })
  end

  private

  def scope(client_id, kind)
    ds = SavedProperty.where(client_id: client_id)
    ds = ds.where(kind: kind) if kind.present?
    ds.order(Sequel.desc(:created_at)).all
  end

  def property_brief(saved_property)
    property = saved_property.property
    {
      'slug' => property&.slug,
      'title' => property&.title,
      'image' => property&.images&.first,
      'price' => property&.price,
    }
  end
end

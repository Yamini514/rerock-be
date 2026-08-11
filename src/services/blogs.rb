class App::Services::Blogs < App::Services::Base
  def model; Blog; end

  # Mirrors lib/data/blogs.js: newest-first (publish date is what the
  # Journal's own ordering cares about, same reasoning as Leads' recency
  # order), search by title OR category, plus an exact status filter for the
  # admin page's Draft/Published toggle.
  def list
    ds = model.order(Sequel.desc(:date), Sequel.desc(:id))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      # NOTE: deliberately NOT services/users.rb's `.where(a).or(b)` idiom —
      # see services/leads.rb's comment. `Dataset#or` ORs against the whole
      # existing WHERE clause, which would swallow the status filter above
      # whenever a search term is also present. Combining the two LIKEs with
      # `|` first, then ANDing the combined expression in, keeps both.
      ds = ds.where(
        Sequel.like(:title, term, case_insensitive: true) | Sequel.like(:category, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore concept here (same as Leads/Blogs' own mock — just a
  # plain delete). Draft/Published status changes and content edits all ride
  # the standard PUT/update below; `content`/`author` are whitelisted like any
  # other saveable field — the frontend sends the whole array/object back on
  # every change, same "no per-entry whitelisting" convention as
  # Property#floor_plans / Lead#timeline.
  def self.fields
    {
      save: [
        :slug, :title, :excerpt, :image, :category, :date, :read_time,
        :author, :content, :status
      ]
    }
  end

  # `content` is real HTML now (the admin rich text editor), not plain
  # paragraph strings — sanitized here before it ever reaches the database,
  # on top of the frontend's own sanitize-before-render pass on the public
  # blog page. Same "never trust what a browser sent, even from an
  # authenticated admin" posture as everywhere else input reaches storage.
  def create
    data = data_for(:save)
    data[:content] = sanitize_html(data[:content]) if data.key?(:content)
    save(model.new(data))
  end

  def update(data = nil)
    data ||= data_for(:save)
    data[:content] = sanitize_html(data[:content]) if data.key?(:content)
    item.set_fields(data, data.keys)
    save(item)
  end

  private

  DANGEROUS_TAGS = %w[script style iframe object embed form input button link meta].freeze
  ALLOWED_TAGS = %w[p br strong em b i u a ul ol li h2 h3 h4 blockquote img hr].freeze
  ALLOWED_ATTRS = { 'a' => %w[href target rel], 'img' => %w[src alt] }.freeze

  def sanitize_html(html)
    fragment = Nokogiri::HTML::DocumentFragment.parse(html.to_s)

    fragment.traverse do |node|
      next unless node.element?

      if DANGEROUS_TAGS.include?(node.name)
        node.remove
        next
      end

      unless ALLOWED_TAGS.include?(node.name)
        node.replace(node.children)
        next
      end

      allowed_attrs = ALLOWED_ATTRS[node.name] || []
      node.attribute_nodes.each { |attr| attr.remove unless allowed_attrs.include?(attr.name) }

      href = node['href']
      node.remove_attribute('href') if node.name == 'a' && href && href.strip =~ /\A(javascript|data):/i

      src = node['src']
      node.remove_attribute('src') if node.name == 'img' && src && src.strip =~ /\Ajavascript:/i
    end

    fragment.to_html
  end
end

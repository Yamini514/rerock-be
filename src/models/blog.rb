class App::Models::Blog < Sequel::Model
  # Was fully unvalidated before (no validate method at all). `image` is
  # required so every public blog post always has one to render — lib/seo.js's
  # absoluteUrl() (rerock-frontend) crashes if ever called with a null path,
  # and the blog detail page's own JSON-LD passes `post.image` straight into
  # it with no guard of its own.
  def validate
    super
    validates_presence [:image], message: 'is required'
  end
end

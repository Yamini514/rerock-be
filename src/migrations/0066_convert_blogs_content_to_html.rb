Sequel.migration do
  # Blog content was a text[] of plain paragraph strings (admin's "leave a
  # blank line between paragraphs" textarea, rendered as one <p> per array
  # entry with zero HTML support — no bold/links/images). The new admin rich
  # text editor produces real HTML instead, so this converts existing rows
  # in place: each stored paragraph becomes an HTML-escaped <p>, preserving
  # every existing post's text with no data loss (formatting-wise it's a
  # no-op — plain paragraphs stay plain paragraphs, just as HTML now).
  up do
    alter_table(:blogs) { add_column :content_html, String, text: true, default: '' }

    from(:blogs).each do |row|
      paragraphs = Array(row[:content])
      html = paragraphs.map do |p|
        escaped = p.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
        "<p>#{escaped}</p>"
      end.join
      from(:blogs).where(id: row[:id]).update(content_html: html)
    end

    alter_table(:blogs) { drop_column :content }
    alter_table(:blogs) { rename_column :content_html, :content }
  end

  # Best-effort only — HTML formatting (bold/links/images/lists) can't
  # round-trip back into plain paragraph strings, so this strips tags rather
  # than preserving them. Not expected to be run outside local dev.
  down do
    alter_table(:blogs) { add_column :content_array, 'text[]', default: '{}' }

    from(:blogs).each do |row|
      html = row[:content].to_s
      paragraphs = html.split(/<\/p>/i).map { |p| p.gsub(/<[^>]*>/, '').strip }.reject(&:empty?)
      from(:blogs).where(id: row[:id]).update(content_array: paragraphs)
    end

    alter_table(:blogs) { drop_column :content }
    alter_table(:blogs) { rename_column :content_array, :content }
  end
end

# Incoming HTML is hostile (A7). Safe subset for display; scripts, styles,
# forms and event handlers are gone. cid:/data: image sources survive for
# inline attachments (A20).
class HtmlSanitizer
  ALLOWED_TAGS = %w[
    a p br div span strong em b i u s ul ol li blockquote pre code
    h1 h2 h3 h4 h5 h6 table thead tbody tr td th hr img
  ].freeze
  ALLOWED_ATTRIBUTES = %w[href src alt title width height colspan rowspan].freeze

  def self.call(html)
    return "" if html.blank?
    # Prune first: the safelist strips tags but keeps their text; script/style
    # bodies must go entirely.
    pruned = Nokogiri::HTML5.fragment(html)
    pruned.css("script, style, iframe, object, embed, form, svg, math").each(&:remove)
    sanitized = Rails::HTML5::SafeListSanitizer.new.sanitize(
      pruned.to_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )
    # SafeListSanitizer already strips javascript: hrefs; also drop non-http(s)/mailto links.
    fragment = Nokogiri::HTML5.fragment(sanitized)
    fragment.css("a[href]").each do |a|
      a.remove_attribute("href") unless a["href"].match?(%r{\A(https?:|mailto:)}i)
    end
    fragment.css("img[src]").each do |img|
      img.remove_attribute("src") unless img["src"].match?(%r{\A(https?:|cid:|data:image/)}i)
    end
    fragment.to_html
  end
end

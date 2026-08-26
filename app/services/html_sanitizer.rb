# Incoming HTML is hostile (A7). Safe subset for display; scripts, styles,
# forms and event handlers are gone. cid:/data: image sources survive for
# inline attachments (A20).
class HtmlSanitizer
  ALLOWED_TAGS = %w[
    a p br div span strong em b i u s ul ol li blockquote pre code
    h1 h2 h3 h4 h5 h6 table thead tbody tr td th hr img
  ].freeze
  # `style` is CSS-sanitized by the safelist scrubber (colors/fonts survive,
  # url()/expression/position tricks do not) — styled newsletters and Outlook
  # mail keep their look without becoming an attack surface.
  ALLOWED_ATTRIBUTES = %w[href src alt title width height colspan rowspan
                          style align valign bgcolor border cellpadding cellspacing data-flow-cid].freeze

  def self.call(html)
    return "" if html.blank?
    # Prune first: the safelist strips tags but keeps their text; script/style
    # bodies must go entirely.
    pruned = Nokogiri::HTML5.fragment(html)
    pruned.css("script, style, iframe, object, embed, form, svg, math").each(&:remove)
    # The safelist's protocol filter would drop cid: srcs (A20); carry them
    # through a data attribute and restore after.
    pruned.css("img[src]").each do |img|
      if (cid = img["src"][/\Acid:(.+)\z/i, 1])
        img["data-flow-cid"] = cid
        img.remove_attribute("src")
      end
    end
    sanitized = Rails::HTML5::SafeListSanitizer.new.sanitize(
      pruned.to_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    )
    # SafeListSanitizer already strips javascript: hrefs; also drop non-http(s)/mailto links.
    fragment = Nokogiri::HTML5.fragment(sanitized)
    fragment.css("a[href]").each do |a|
      a.remove_attribute("href") unless a["href"].match?(%r{\A(https?:|mailto:)}i)
    end
    fragment.css("img").each do |img|
      if (cid = img.remove_attribute("data-flow-cid")&.value)
        img["src"] = "cid:#{cid}"
      elsif img["src"] && !img["src"].match?(%r{\A(?:https?:|data:image/(?:gif|jpeg|png)(?:;[^,]*)?,)}i)
        img.remove_attribute("src")
      end
    end
    fragment.to_html
  end
end

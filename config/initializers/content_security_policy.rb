# Strict CSP (I2): the SPA is a local bundle; nothing loads from elsewhere.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline # Vue component inline styles
    policy.img_src     :self, :data, :blob
    policy.font_src    :self
    policy.connect_src :self
    policy.object_src  :none
    policy.frame_src   :self # plugin settings pages are same-origin
    policy.frame_ancestors :self
    policy.base_uri    :self
  end
end

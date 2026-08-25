# RFC 6238 TOTP, stdlib only (I8). 6 digits, 30s steps, ±1 step drift.
module Totp
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze
  STEP = 30

  def self.generate_secret
    SecureRandom.bytes(20).unpack1("B*").scan(/.{5}/).map { |bits| ALPHABET[bits.to_i(2)] }.join
  end

  def self.code(secret, timestep: Time.now.to_i / STEP)
    hmac = OpenSSL::HMAC.digest("SHA1", base32_decode(secret), [ timestep ].pack("Q>"))
    offset = hmac.bytes.last & 0xf
    ((hmac[offset, 4].unpack1("N") & 0x7fffffff) % 1_000_000).to_s.rjust(6, "0")
  end

  def self.valid?(secret, candidate)
    candidate = candidate.to_s.strip
    return false unless candidate.match?(/\A\d{6}\z/)
    now = Time.now.to_i / STEP
    (-1..1).any? do |drift|
      ActiveSupport::SecurityUtils.secure_compare(code(secret, timestep: now + drift), candidate)
    end
  end

  def self.provisioning_uri(secret, account:, issuer: "Flow")
    "otpauth://totp/#{ERB::Util.url_encode(issuer)}:#{ERB::Util.url_encode(account)}" \
      "?secret=#{secret}&issuer=#{ERB::Util.url_encode(issuer)}"
  end

  def self.base32_decode(str)
    bits = str.upcase.chars.map { |c| ALPHABET.index(c).to_s(2).rjust(5, "0") }.join
    bits[0, bits.length - bits.length % 8].scan(/.{8}/).map { |b| b.to_i(2) }.pack("C*")
  end
end

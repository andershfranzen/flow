# Development seed data: a ready-to-use inbox so bin/setup lands you in a
# working app. Production seeds nothing — bin/create-admin makes the first
# admin there. Idempotent: skips entirely once any agent exists.
#
# Machine-specific overlays (real mailboxes, company plugins, credentials)
# belong in db/seeds.local.rb — untracked, loaded after these seeds.
return unless Rails.env.development?

local_seeds = Rails.root.join("db/seeds.local.rb")
if Agent.exists?
  load local_seeds if File.exist?(local_seeds)
  return
end

puts "Seeding development demo data…"

admin = Agent.create!(email: "admin@flow.local", name: "Ada Admin",
                      password: "flowdev123", role: "admin")
sam = Agent.create!(email: "sam@flow.local", name: "Sam Support",
                    password: "flowdev123", role: "user")

support = Mailbox.create!(address: "support@flow.local", name: "Support",
                          smtp_host: "smtp.flow.local")
sales = Mailbox.create!(address: "sales@flow.local", name: "Sales",
                        smtp_host: "smtp.flow.local")
[ support, sales ].each { |m| MailboxAccess.create!(agent: sam, mailbox: m) }

billing = Tag.create!(name: "billing")
bug = Tag.create!(name: "bug")

def seed_conversation(mailbox, name:, email:, subject:, status: "active", assignee: nil, tags: [], messages:)
  customer = Customer.find_or_create_by!(email: email) { |c| c.name = name }
  conversation = Conversation.create!(mailbox: mailbox, customer: customer, subject: subject,
                                      status: status, assignee: assignee)
  conversation.tags = tags
  messages.each_with_index do |m, i|
    sent_at = m.fetch(:at)
    conversation.messages.create!(
      kind: m.fetch(:kind), body_text: m.fetch(:body), sent_at: sent_at,
      received_at: (sent_at if m[:kind] == "inbound"),
      status: m[:kind] == "outbound" ? "sent" : "received",
      from_email: m[:kind] == "inbound" ? email : mailbox.address,
      from_name: m[:kind] == "inbound" ? name : nil,
      agent: m[:agent], to: [ m[:kind] == "inbound" ? mailbox.address : email ],
      message_id_header: "seed-#{conversation.id}-#{i}@flow.local"
    )
  end
  conversation
end

seed_conversation(support, name: "Mette Larsen", email: "mette@nordicfoods.dk",
  subject: "Freezer FR-2200 shows error E4", assignee: admin, tags: [ bug ],
  messages: [
    { kind: "inbound", at: 26.hours.ago, body: "Hi, our display freezer FR-2200 started blinking error E4 this morning. The temperature is still holding but the alarm keeps sounding. What does E4 mean?" },
    { kind: "outbound", at: 25.hours.ago, agent: admin, body: "Hi Mette, E4 is the evaporator sensor. Try a power cycle first — if it returns within an hour, the sensor needs replacing. I can ship one today if you send the serial number." },
    { kind: "inbound", at: 2.hours.ago, body: "It came back after 20 minutes. Serial is FR2200-118842. Please send the sensor." }
  ])

seed_conversation(support, name: "John Baker", email: "john@bakerandsons.co.uk",
  subject: "Invoice 4471 charged twice", assignee: sam, tags: [ billing ],
  messages: [
    { kind: "inbound", at: 5.hours.ago, body: "Hello, we were charged twice for invoice 4471 (£1,240). Can you check and refund the duplicate?" }
  ])

seed_conversation(support, name: "Sofia Rossi", email: "sofia@gelateria-rossi.it",
  subject: "Spare shelves for UF 200",
  messages: [
    { kind: "inbound", at: 3.days.ago, body: "Buongiorno, do you sell spare shelves for the UF 200? We need four." },
    { kind: "outbound", at: 3.days.ago, agent: sam, body: "Ciao Sofia — yes, part no. 83-0214. Four shelves come to €96 plus shipping. Shall I place the order?" },
    { kind: "inbound", at: 45.minutes.ago, body: "Yes please, ship to the usual address. Grazie!" }
  ])

seed_conversation(sales, name: "Peter Novak", email: "peter@hotelnovak.cz",
  subject: "Quote for 12 minibar coolers",
  messages: [
    { kind: "inbound", at: 8.hours.ago, body: "We are renovating 12 rooms and need quiet minibar coolers, glass door preferred. Could you quote delivery to Prague?" }
  ])

seed_conversation(support, name: "Anna Berg", email: "anna@bergcatering.se",
  subject: "Thanks for the fast delivery", status: "closed", assignee: admin,
  messages: [
    { kind: "inbound", at: 6.days.ago, body: "The replacement compressor arrived next day and works perfectly. Thanks for the quick help!" },
    { kind: "outbound", at: 6.days.ago, agent: admin, body: "Happy to help, Anna — enjoy!" }
  ])

puts "Seeded #{Conversation.count} conversations. Sign in: admin@flow.local / flowdev123"

# Machine-specific overlay (real mailboxes, company plugins, credentials):
# untracked, idempotent, runs on every db:seed.
load local_seeds if File.exist?(local_seeds)

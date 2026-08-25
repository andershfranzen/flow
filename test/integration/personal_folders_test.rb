require "test_helper"

class PersonalFoldersTest < ActionDispatch::IntegrationTest
  setup do
    @ada = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @bob = Agent.create!(email: "b@example.com", name: "Bob", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    fetcher = ImapFetcher.new(@mailbox)
    [ "One", "Two" ].each_with_index do |subj, i|
      raw = Mail.new do
        from "kunde@example.dk"; to "support@example.com"; subject subj; body "hi"
        message_id "<pf#{i}@x>"
      end.to_s
      fetcher.ingest(raw)
    end
    @one, @two = Conversation.order(:id).to_a
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  def login_bob = post("/api/session", params: { email: "b@example.com", password: "secret123" })

  test "folders are strictly personal: invisible and untouchable across agents" do
    post "/api/personal_folders", params: { name: "Warehouse", color: "#1a7f37" }
    folder_id = response.parsed_body["id"]
    post "/api/personal_folders/#{folder_id}/items", params: { conversation_ids: [ @one.id ] }
    assert_equal 1, response.parsed_body["count"]

    login_bob
    get "/api/personal_folders"
    assert_equal [], response.parsed_body, "Bob must not see Ada's folders"
    post "/api/personal_folders/#{folder_id}/items", params: { conversation_ids: [ @two.id ] }
    assert_response :not_found, "Bob must not modify Ada's folder"
  end

  test "personal folder filters the conversation list regardless of status" do
    post "/api/personal_folders", params: { name: "Chase later" }
    folder_id = response.parsed_body["id"]
    post "/api/personal_folders/#{folder_id}/items", params: { conversation_ids: [ @one.id, @two.id ] }
    @two.set_status!("closed")

    get "/api/conversations", params: { personal_folder_id: folder_id }
    assert_equal [ @one.id, @two.id ].sort, response.parsed_body["conversations"].map { |c| c["id"] }.sort,
                 "closed members still show inside the personal folder"

    delete "/api/personal_folders/#{folder_id}/items/#{@two.id}"
    get "/api/conversations", params: { personal_folder_id: folder_id }
    assert_equal [ @one.id ], response.parsed_body["conversations"].map { |c| c["id"] }
  end

  test "deleting a folder leaves conversations untouched" do
    post "/api/personal_folders", params: { name: "Temp" }
    folder_id = response.parsed_body["id"]
    post "/api/personal_folders/#{folder_id}/items", params: { conversation_ids: [ @one.id ] }
    delete "/api/personal_folders/#{folder_id}"
    assert_response :no_content
    assert Conversation.exists?(@one.id)
  end

  test "stars are per-agent" do
    patch "/api/conversations/#{@one.id}", params: { starred: true }
    assert response.parsed_body["starred"]
    get "/api/conversations", params: { folder: "starred" }
    assert_equal [ @one.id ], response.parsed_body["conversations"].map { |c| c["id"] }

    login_bob
    get "/api/conversations", params: { folder: "starred" }
    assert_equal [], response.parsed_body["conversations"], "Ada's star must be invisible to Bob"
    get "/api/conversations", params: { folder: "unassigned" }
    starred_flags = response.parsed_body["conversations"].map { |c| c["starred"] }
    assert starred_flags.none?, "starred flag is personal in the list too"
  end

  test "bulk remove-from-folder works from a folder view" do
    post "/api/personal_folders", params: { name: "Sorted" }
    folder_id = response.parsed_body["id"]
    post "/api/personal_folders/#{folder_id}/items", params: { conversation_ids: [ @one.id, @two.id ] }
    patch "/api/conversations/bulk", params: { ids: [ @one.id ], remove_from_folder_id: folder_id }
    get "/api/conversations", params: { personal_folder_id: folder_id }
    assert_equal [ @two.id ], response.parsed_body["conversations"].map { |c| c["id"] }
  end
end

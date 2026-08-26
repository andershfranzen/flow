require "test_helper"

class PluginTest < ActiveSupport::TestCase
  teardown do
    DomainEvents.reset!
    PluginRegistry.reset!
  end

  test "subscribers receive domain events alongside webhooks" do
    seen = []
    DomainEvents.subscribe("thread.created") { |p| seen << p }
    DomainEvents.subscribe("*") { |p| seen << p }
    DomainEvents.emit("thread.created", { id: 1 })
    assert_equal 2, seen.size
    assert_equal "thread.created", seen.last[:event]
  end

  test "a raising subscriber does not break emit" do
    DomainEvents.subscribe("*") { raise "boom" }
    assert_nothing_raised { DomainEvents.emit("thread.status", { id: 1 }) }
  end

  test "registered mcp tools appear in the server" do
    tool = Class.new(MCP::Tool) do
      tool_name "plugin_test_tool"
      description "x"
      input_schema(properties: {}, required: [])
      def self.call(server_context:) = MCP::Tool::Response.new([ { type: "text", text: "ok" } ])
    end
    McpTools.register(tool)
    assert_includes McpTools.all, tool
  ensure
    McpTools.unregister(tool)
  end

  test "plugins provide generic conversation insight cards" do
    PluginRegistry.instance_variable_set(:@loading, "example-plugin")
    PluginRegistry.register_conversation_insights { |conversation| [ { id: "example", title: conversation.subject } ] }
    PluginRegistry.instance_variable_set(:@loading, nil)

    cards = PluginRegistry.conversation_insights(Struct.new(:subject).new("Order help"))

    assert_equal [ { id: "example", title: "Order help" } ], cards
  end
end

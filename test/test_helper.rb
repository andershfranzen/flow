ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# FTS index must exist before transactional tests begin (DDL inside a test
# transaction would roll back with it).
SearchIndex.ensure!

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each worker gets its own database; the runtime-managed FTS table must be
    # created in each, outside any test transaction.
    parallelize_setup do |_worker|
      SearchIndex.reset!
      SearchIndex.ensure!
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

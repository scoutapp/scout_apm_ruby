# Most of this was taken from Rails:
# https://github.com/rails/rails/blob/v7.1.3/actionview/test/actionpack/controller/render_test.rb
# https://github.com/rails/rails/blob/v7.1.3/actionview/test/abstract_unit.rb

if (ENV["SCOUT_TEST_FEATURES"] || "").include?("instruments")
  require 'test_helper'
  require 'action_view'
  require 'action_pack'
  require 'action_controller'

  FIXTURE_LOAD_PATH = File.expand_path("fixtures", __dir__)

  include ActionView::Context
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper

  module ActionController

    class Base
      self.view_paths = FIXTURE_LOAD_PATH

      def self.test_routes(&block)
        routes = ActionDispatch::Routing::RouteSet.new
        routes.draw(&block)
        include routes.url_helpers
        routes
      end
    end

    class TestCase
      include ActionDispatch::TestProcess

      def self.with_routes(&block)
        routes = ActionDispatch::Routing::RouteSet.new
        routes.draw(&block)
        include Module.new {
          define_method(:setup) do
            super()
            @routes = routes
            @controller.singleton_class.include @routes.url_helpers if @controller
          end
        }
        routes
      end
    end
  end

  class TestController < ActionController::Base

    def render_test_view
      render template: "test_view"
    end
  end

  class RenderTest < ActionController::TestCase

    tests TestController

    with_routes do
      get :render_test_view, to: "test#render_test_view"
    end

    def setup
      super
      @controller.logger      = ActiveSupport::Logger.new(nil)
      ActionView::Base.logger = ActiveSupport::Logger.new(nil)

      @request.host = "www.scoutapm.com"

      @old_view_paths = ActionController::Base.view_paths
      ActionController::Base.view_paths = FIXTURE_LOAD_PATH
    end

    def teardown
      ActionView::Base.logger = nil

      ActionController::Base.view_paths = @old_view_paths
    end

    def test_partial_instrumentation
      recorder = FakeRecorder.new
      agent_context.recorder = recorder

      instrument = ScoutApm::Instruments::ActionView.new(agent_context)
      instrument.install(prepend: true)

      get :render_test_view
      assert_response :success

      root_layer = recorder.requests.first.root_layer
      children = root_layer.children.to_a
      assert_equal 2, children.size

      partial_layer = children[0]
      collection_layer = children[1]

      assert_equal "test_view/Rendering", root_layer.name
      assert_equal "test/_test_partial/Rendering", partial_layer.name
      assert_equal "test/_test_partial_collection/Rendering", collection_layer.name
    end
  end
end

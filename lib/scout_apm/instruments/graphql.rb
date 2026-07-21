# frozen_string_literal: true

module ScoutApm
  module Instruments
    class GraphQL
      attr_reader :context

      def initialize(context)
        @context = context
        @installed = false
      end

      def logger
        context.logger
      end

      def installed?
        @installed
      end

      def install(prepend: false)
        return unless defined?(::GraphQL::Tracing::ScoutTrace)

        @installed = true
        logger.info "Instrumenting GraphQL::Tracing::ScoutTrace"
        ::GraphQL::Tracing::ScoutTrace.prepend(ScoutApm::Instruments::GraphQLExecuteFieldGuard)
      end
    end

    # Prepended onto GraphQL::Tracing::ScoutTrace to guarantee that every
    # Scout layer opened during a GraphQL multiplex is closed before control
    # returns to the Scout Rack middleware.
    #
    # graphql-ruby's interpreter calls begin_execute_field / end_execute_field
    # around each field resolver. When an unhandled exception causes
    # end_execute_field to be skipped (runtime.rb lines 465-479), the
    # corresponding ScoutApm::Layer is never popped from TrackedRequest#@layers.
    # finalized? never returns true, record! is never called, and
    # Thread.current[:scout_request] accumulates every subsequent request's
    # layers without bound.
    #
    # This guard snapshots the open layer count before executing the multiplex
    # and pops any excess layers in an ensure block, independent of whichever
    # internal trace hooks graphql-ruby happens to use. It has no dependency on
    # MonitorTrace's field-tracing condition or event slot architecture, so it
    # remains correct even if those internals change.
    module GraphQLExecuteFieldGuard
      def execute_multiplex(multiplex:)
        req = ScoutApm::RequestManager.lookup
        layers_before = req.layer_count
        super
      ensure
        extra = req.layer_count - layers_before
        extra.times { req.stop_layer } if extra > 0
      end
    end
  end
end

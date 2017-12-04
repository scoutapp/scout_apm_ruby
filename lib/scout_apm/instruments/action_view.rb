module ScoutApm
  module Instruments
    # instrumentation for Rails 3 and Rails 4 is the same.
    class ActionView
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

      def install
        if defined?(::ActionView) && defined?(::ActionView::PartialRenderer)
          @installed = true

          logger.info "Instrumenting ActionView::PartialRenderer"
          ::ActionView::PartialRenderer.class_eval do
            include ScoutApm::Tracer

            instrument_method :render_partial,
              :type => "View",
              :name => '#{@template.virtual_path rescue "Unknown Partial"}/Rendering',
              :scope => true

            instrument_method :collection_with_template,
              :type => "View",
              :name => '#{@template.virtual_path rescue "Unknown Collection"}/Rendering',
              :scope => true
          end

          logger.info "Instrumenting ActionView::TemplateRenderer"
          ::ActionView::TemplateRenderer.class_eval do
            include ScoutApm::Tracer
            instrument_method :render_template,
              :type => "View",
              :name => '#{args[0].virtual_path rescue "Unknown"}/Rendering',
              :scope => true
          end
        end
      end
    end
  end
end



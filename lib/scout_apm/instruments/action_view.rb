# Note, this instrument has the same logic in both Tracer and Module Prepend
# versions. If you update, be sure you update in both spots.
#
# The prepend version was added for Rails 6 support - ActiveRecord prepends on
# top of PartialRenderer#collection_with_template, which can (and does) cause
# infinite loops with our alias_method approach
module ScoutApm
  module Instruments
    # Instrumentation for Rails 3, 4, 5 is the same, using tracer.
    # Rails 6 switches to using Module#prepend
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
        return unless defined?(::ActionView) && defined?(::ActionView::PartialRenderer)

        if defined?(::Rails) && defined?(::Rails::VERSION) && defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR < 6
          install_using_tracer
        else
          install_using_prepend
        end
        @installed = true
      end

      def install_using_tracer
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

      def install_using_prepend
        logger.info "Instrumenting ActionView::PartialRenderer"
        ::ActionView::PartialRenderer.prepend(ActionViewPartialRendererInstruments)

        logger.info "Instrumenting ActionView::TemplateRenderer"
        ::ActionView::TemplateRenderer.prepend(ActionViewTemplateRendererInstruments)
      end

      module ActionViewPartialRendererInstruments
        def render_partial(*args)
          req = ScoutApm::RequestManager.lookup

          template_name = @template.virtual_path rescue "Unknown Partial"
          layer_name = template_name + "/Rendering"

          layer = ScoutApm::Layer.new("View", layer_name)
          layer.subscopable!

          begin
            req.start_layer(layer)
            super(*args)
          ensure
            req.stop_layer
          end
        end

        def collection_with_template(*args)
          req = ScoutApm::RequestManager.lookup

          template_name = @template.virtual_path rescue "Unknown Collection"
          layer_name = template_name + "/Rendering"

          layer = ScoutApm::Layer.new("View", layer_name)
          layer.subscopable!

          begin
            req.start_layer(layer)
            super(*args)
          ensure
            req.stop_layer
          end
        end
      end

      module ActionViewTemplateRendererInstruments
        def render_template(*args)
          req = ScoutApm::RequestManager.lookup

          template_name = args[0].virtual_path rescue "Unknown"
          layer_name = template_name + "/Rendering"

          layer = ScoutApm::Layer.new("View", layer_name)
          layer.subscopable!

          begin
            req.start_layer(layer)
            super(*args)
          ensure
            req.stop_layer
          end
        end
      end
    end
  end
end

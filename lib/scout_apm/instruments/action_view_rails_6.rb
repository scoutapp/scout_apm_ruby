module ScoutApm
  module Instruments
    class ActionViewRails6
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

        logger.info "Instrumenting ActionView::PartialRenderer"
        ::ActionView::PartialRenderer.prepend(ActionViewPartialRendererInstruments)

        logger.info "Instrumenting ActionView::CollectionRenderer"
        ::ActionView::CollectionRenderer.prepend(ActionViewCollectionRendererInstruments)

        @installed = true
      end

      def install_using_prepend
        logger.info "Instrumenting ActionView::PartialRenderer"

        logger.info "Instrumenting ActionView::TemplateRenderer"
        ::ActionView::TemplateRenderer.prepend(ActionViewTemplateRendererInstruments)
      end

      module ActionViewPartialRendererInstruments
        # render_partial_template(context, @locals, template, layout, block)
        def render_partial_template(*args)
          template = args[2]
          ScoutApm::Agent.instance.context.logger.info("Instrumenting template: #{template.inspect}")

          # Avoid causing issues if args changes in the future
          if template.nil?
            super(*args)
            return
          end

          req = ScoutApm::RequestManager.lookup

          template_name = template.virtual_path rescue "Unknown Partial"
          template_name ||= "Unknown Partial"
          layer_name = template_name + "/Rendering"

          ScoutApm::Agent.instance.context.logger.info("Template Name: #{template_name}")

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

      module ActionViewCollectionRendererInstruments
        # def render_collection(collection, view, path, template, layout, block)
        def render_collection(*args)
          req = ScoutApm::RequestManager.lookup

          template_name = begin
                        @template.virtual_path
                          rescue
                            "Unknown Collection"
                      end
          template_name ||= "Unknown Collection"
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

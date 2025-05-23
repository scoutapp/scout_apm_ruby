module ScoutApm
  module Instruments
    class Mongoid
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

      def install(prepend:)
        @installed = true

        # Mongoid versions that use Moped should instrument Moped.
        ### See moped instrument for Moped driven deploys
        if defined?(::Mongoid) and !defined?(::Moped)
          @installed = true

          if (mongoid_at_least_5?) && defined?(::Mongoid::Contextual::Mongo)
            logger.info "Instrumenting Mongoid"
            # All the public methods from Mongoid::Contextual::Mongo.
            # TODO: Geo and MapReduce support (?). They are in other Contextual::* classes
            methods = [
              :count, :delete, :destroy, :distinct, :each,
              :explain, :find_first, :find_one_and_delete, :find_one_and_replace,
              :find_one_and_update, :first, :geo_near, :initialize, :last,
              :length, :limit, :map, :map_reduce, :pluck,
              :skip, :sort, :update, :update_all,
            ]
            # :exists?,

            methods.each do |method|
              if ::Mongoid::Contextual::Mongo.method_defined?(method)
                with_scout_instruments = %Q[
                def #{method}_with_scout_instruments(*args, &block)
                  req = ScoutApm::RequestManager.lookup
                  *db, collection = view.collection.namespace.split(".")

                  name = collection + "/#{method}"

                  # Between Mongo gem version 2.1 and 2.3, this method name was
                  # changed. Accomodate both.  If for some reason neither is
                  # there, try to continue with an empty "filter" hash.
                  raw_filter = if view.respond_to?(:selector)
                    view.selector
                  elsif view.respond_to?(:filter)
                    view.filter
                  else
                    {}
                  end

                  filter = ScoutApm::Instruments::Mongoid.anonymize_filter(raw_filter)

                  layer = ScoutApm::Layer.new("MongoDB", name)
                  layer.desc = filter.inspect

                  req.start_layer( layer )
                  begin
                    #{method}_without_scout_instruments(*args, &block)
                  ensure
                    req.stop_layer
                  end
                end

                alias_method :#{method}_without_scout_instruments, :#{method}
                alias_method :#{method}, :#{method}_with_scout_instruments
                ]

                ::Mongoid::Contextual::Mongo.class_eval(with_scout_instruments)
              else
                logger.warn "Expected method #{method} not defined in Mongoid::Contextual::Mongo."
              end
            end
          end
        end
      end

      def mongoid_at_least_5?
        if defined?(::Mongoid::VERSION)
          ::Mongoid::VERSION =~ /\A[56789]/
        else
          false
        end
      end

      # Example of what a filter looks like: => {"founded"=>{"$gte"=>"1980-1-1"}, "name"=>{"$in"=>["Tool", "Deftones", "Melvins"]}}
      # Approach: find every leaf-node, clear it. inspect the whole thing when done.
      def self.anonymize_filter(filter)
        Hash[
          filter.map do |k,v|
            if v.is_a? Hash
              [k, anonymize_filter(v)]
            else
              [k, "?"]
            end
          end
        ]
      end
    end
  end
end

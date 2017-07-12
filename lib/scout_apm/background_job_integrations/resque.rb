module ScoutApm
  module BackgroundJobIntegrations
    class Resque
      attr_reader :logger

      def name
        :resque
      end

      def present?
        # defined?(::Sidekiq) && File.basename($PROGRAM_NAME).start_with?('sidekiq')
        true
      end

      # Lies. This forks really aggressively, but we have to do handling
      # of it manually here, rather than via any sort of automatic
      # background worker starting
      def forking?
        false
      end

      def install
        puts "Installing Resque!"

        install_before_fork
        install_after_fork
      end

      def install_before_fork
        puts "Installing Before First Fork!"
        ::Resque.before_first_fork do
          begin
            puts "BEFORE FIRST FORK: #{$$}"
            ScoutApm::Agent.instance.start(:skip_app_server_check => true)
            ScoutApm::Agent.instance.start_background_worker
            ScoutApm::Agent.instance.start_remote_server(bind, port)
          rescue => e
            puts "ERROR ERROR: #{e.inspect}"
          end
        end
      end

      def install_after_fork
        puts "Installing After Fork!"
        ::Resque.after_fork do
          begin
            puts "\n\n***** FORKED, In Worker: #{$$}\n"

            ScoutApm::Agent.instance.init_logger({:force => true})
            ScoutApm::Agent.instance.use_remote_recorder(bind, port)
            inject_job_instrument
          rescue => e
            puts "ERROR ERROR: #{e.inspect}"
          end
        end
      end

      # Insert ourselves into the point when resque turns a string "TestJob"
      # into the class constant TestJob, and insert our instrumentation plugin
      # into that constantized class
      #
      # This automates away any need for the user to insert our instrumentation into
      # each of their jobs
      def inject_job_instrument
        ::Resque::Job.class_eval do
          def payload_class_with_scout_instruments
            klass = payload_class_without_scout_instruments
            klass.extend(ScoutApm::Instruments::Resque)
            klass
          end
          alias_method :payload_class_without_scout_instruments, :payload_class
          alias_method :payload_class, :payload_class_with_scout_instruments
        end
      end

      private

      def bind
        config.value("remote_host").tap{|x| puts "Bind: #{x}"}
      end

      def port
        config.value("remote_port").tap{|x| puts "Port: #{x}"}
      end

      def config
        @config || ScoutApm::Agent.instance.config
      end
    end
  end
end




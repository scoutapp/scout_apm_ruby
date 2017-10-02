module ScoutApm
  module Utils
    class ObjectDump
      TIME_FORMAT = "%Y%m%d%H%M"

      def self.dump_reachable(obj, filename_append = nil)
        require 'objspace' rescue nil
        require 'pp' rescue nil

        if !(defined?(ObjectSpace) && defined?(ObjectSpace.reachable_objects_from)) || !(defined?(PP) && defined?(PP.pp))
          ScoutApm::Agent.instance.logger.debug "ObjectDump: ObjectSpace or PP unavailable."
          return false
        end

        filename = "scout_debug_#{Process.pid}_#{::Time.now.strftime(TIME_FORMAT)}"
        if !filename_append.nil?
          filename = "#{filename}_#{filename_append}"
        end
        filename = "#{filename}.object_dump"

        File.open(File.join('/tmp', filename), 'w+') do |f|
          PP.pp(ObjectSpace.reachable_objects_from(obj), f)
        end

      rescue Exception => e
        ScoutApm::Agent.instance.logger.debug "ObjectDump: Exception when running dump_reachable: #{e.inspect}"
        false
      end
    end
  end
end
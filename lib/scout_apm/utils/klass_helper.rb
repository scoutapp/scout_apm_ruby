module ScoutApm
  module Utils
    module KlassHelper
      # KlassHelper.defined?("ActiveRecord", "Base") #=> true / false
      # KlassHelper.defined?("ActiveRecord::Base")   #=> true / false

      def self.defined?(*names)
        if names.length == 1
          names = names[0].split("::")
        end

        obj = Object

        names.each do |name|
          begin
            obj = obj.const_get(name)
          rescue NameError
            return false
          end
        end

        true
      end
    end
  end
end

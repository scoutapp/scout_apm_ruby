
require 'scout_apm/auto_instrument/layer'
if defined?(Prism)
  require 'scout_apm/auto_instrument/prism'
else
  require 'scout_apm/auto_instrument/parser'
end

module ScoutApm
  module AutoInstrument
    module Rails
      # A general pattern to match Rails controller files:
      CONTROLLER_FILE = /\/app\/controllers\/*\/.*_controller.rb$/.freeze

      # Some gems (Devise) provide controllers that match CONTROLLER_FILE pattern.
      # Try a simple match to see if it's a Gemfile
      GEM_FILE = /\/gems?\//.freeze

      # Whether the given path is likely to be a Rails controller and not provided by a Gem.
      def self.controller_path? path
        CONTROLLER_FILE.match(path) && !GEM_FILE.match(path)
      end

      # Autoinstruments increases overhead when applied to many code expressions that perform little work.
      # You can exclude files from autoinstruments via the `auto_instruments_ignore` option.
      def self.ignore?(path)
        res = false
        ScoutApm::Agent.instance.context.config.value('auto_instruments_ignore').each do |ignored_file_name|
          if path.include?(ignored_file_name)
            res = true
            break
          end
        end
        res
      end

      def self.rewrite(path, code = nil)
        if defined?(Prism)
          PrismImplementation.rewrite(path, code)
        else
          ParserImplementation.rewrite(path, code)
        end
      end
    end
  end
end

# Force any lazy loading to occur here, before we patch iseq_load. Otherwise you might end up in an infinite loop when rewriting code.
ScoutApm::AutoInstrument::Rails.rewrite('(preload)', '')

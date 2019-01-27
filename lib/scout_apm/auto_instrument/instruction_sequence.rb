
require 'scout_apm/auto_instrument/rails'

module ScoutApm
  module AutoInstrument
    module InstructionSequence
      CONTROLLER_PATH_PATTERN = /\/apm\/app\/controllers\/.*_controller.rb$/

      def load_iseq(path)
        if path =~ CONTROLLER_PATH_PATTERN
          new_code = Rails.rewrite(path)

          return compile(new_code, path, filepath)
        else
          return super
        end
      end
    end

    RubyVM::InstructionSequence.prepend(InstructionSequence)
  end
end

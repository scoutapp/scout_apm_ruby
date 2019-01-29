
require 'scout_apm/auto_instrument/rails'

module ScoutApm
  module AutoInstrument
    module InstructionSequence
      CONTROLLER_PATH_PATTERN = /\/app\/controllers\/.*_controller.rb$/

      def load_iseq(path)
        if path =~ CONTROLLER_PATH_PATTERN
          new_code = Rails.rewrite(path)
          return compile(new_code, File.basename(path), path)
        else
          return compile_file(path)
        end
      end
    end
    
    # This should work (https://bugs.ruby-lang.org/issues/15572), but it doesn't.
    # RubyVM::InstructionSequence.extend(InstructionSequence)
    
    # So we do this instead:
    class << ::RubyVM::InstructionSequence
      prepend InstructionSequence
    end
  end
end

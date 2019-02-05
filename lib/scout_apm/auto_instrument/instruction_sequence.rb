
require 'scout_apm/auto_instrument/rails'

module ScoutApm
  module AutoInstrument
    module InstructionSequence
      def load_iseq(path)
        if Rails.controller_path?(path)
          begin
            new_code = Rails.rewrite(path)
            return self.compile(new_code, File.basename(path), path)
          rescue SyntaxError => error
            warn "Failed to apply auto-instrumentation to #{path}: #{error}"
           end
        end
        
        return self.compile_file(path)
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


require 'scout_apm/auto_instrument/rails'

module ScoutApm
  module AutoInstrument
    module InstructionSequence
      def self.load_iseq(path)
        if Rails.controller_path?(path) & !Rails.ignore?(path)
          begin
            new_code = Rails.rewrite(path)
            return ::RubyVM::InstructionSequence.compile(new_code, path, path)
          rescue StandardError, SyntaxError
            warn "Failed to apply auto-instrumentation to #{path}: #{$!}" if ENV['SCOUT_LOG_LEVEL'].to_s.downcase == "debug"
          end
        elsif Rails.ignore?(path)
          warn "AutoInstruments are ignored for path=#{path}." if ENV['SCOUT_LOG_LEVEL'].to_s.downcase == "debug"
        end

        return ::RubyVM::InstructionSequence.compile_file(path)
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

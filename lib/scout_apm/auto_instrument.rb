require 'parser'
require 'rubocop'
require 'scout_apm/utils/rubocop_auto_instruments'

module ScoutApm
  module InstructionSequence
    class SourceRewriter
      def self.rewrite(source_string)
        registry = RuboCop::Cop::Registry.new
        registry.enlist(RuboCop::Cop::ActionController::AddScoutInstruments)

        config = RuboCop::Config.new()
        options = {auto_correct: true}
        team = RuboCop::Cop::Team.new(registry, config, options)

        buffer = Parser::Source::Buffer.new('(string)')
        buffer.source = source_string

        source = RuboCop::ProcessedSource.new(buffer.source, RUBY_VERSION.to_f)
        team.inspect_file(source)
        new_code = team.send(:autocorrect_all_cops, buffer, team.cops)
      end
    end
  end
end

# Must call this once before we hook into RubyVM::InstructionSequence#load_iseq
ScoutApm::InstructionSequence::SourceRewriter.rewrite('')

module ScoutApm
  module InstructionSequence
    def load_iseq(filepath)
      return RubyVM::InstructionSequence.compile(File.read(filepath), filepath, filepath) unless filepath =~ /\/apm\/app\/controllers\/.*_controller.rb$/
      new_code = ScoutApm::InstructionSequence::SourceRewriter.rewrite(File.read(filepath))
      iseq = RubyVM::InstructionSequence.compile(new_code, filepath, filepath)
    end
  end
end

class << RubyVM::InstructionSequence
  prepend ::ScoutApm::InstructionSequence
end

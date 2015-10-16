module ScoutApm
  module Utils
    class UniqueId
      ALPHABET = ('a'..'z').to_a.freeze

      def self.simple(length=16)
        s = ""
        length.times do
            s << ALPHABET[rand(26)]
        end
        s
      end
    end
  end
end

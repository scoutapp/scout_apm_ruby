# Encapsulates adding context to requests. Context is stored via a simple Hash.
#
# There are 2 types of context: User and Extra.
# For user-specific context, use @Context#user@.
# For misc context, use @Context#extra@.
class ScoutApm::Context
  attr_accessor :extra, :user

  def initialize
    @extra = {}
    @user = {}
  end

  # Generates a hash representation of the Context. 
  # Example: {:monthly_spend => 100, :user => {:ip => '127.0.0.1'}}
  def to_hash
    @extra.merge({:user => user})
  end

  def self.current
    Thread.current[:scout_context] ||= new
  end

  def self.clear!
    Thread.current[:scout_context] = nil
  end

  # Convenience accessor so you can just call @ScoutAPM::Context#extra@
  def self.extra
    self.current.extra
  end

  # Convenience accessor so you can just call @ScoutAPM::Context#user@
  def self.user
    self.current.user
  end
end
# Encapsulates adding context to requests. Context is stored via a simple Hash.
#
# There are 2 types of context: User and Extra.
# For user-specific context, use @Context#user@.
# For misc context, use @Context#extra@.
class ScoutApm::Context

  def initialize
    @extra = {}
    @user = {}
  end

  # Generates a hash representation of the Context. 
  # Example: {:monthly_spend => 100, :user => {:ip => '127.0.0.1'}}
  def to_hash
    @extra.merge({:user => @user})
  end

  def self.current
    Thread.current[:scout_context] ||= new
  end

  def self.clear!
    Thread.current[:scout_context] = nil
  end

  # Add extra context
  # ScoutApm::context.extra(account: current_account.name)
  def extra(hash)
    update_context(:extra,hash)
  end

  def user(hash)
    update_context(:user,hash)
  end

  # Convenience accessor so you can just call @ScoutAPM::Context#extra@
  def self.extra(hash)
    self.current.extra(hash)
  end

  # Convenience accessor so you can just call @ScoutAPM::Context#user@
  def self.user(hash)
    self.current.user(hash)
  end

  private

  def update_context(attr,hash)
    valid_hash = Hash.new
    # iterate over the hash of new context, adding to the valid_hash if validation checks pass.
    hash.each do |key,value|
      # does both checks so we can get logging info on the value even if the key is invalid.
      key_valid = key_valid?({key => value})
      value_valid = value_valid?({key => value})
      if key_valid and value_valid
        valid_hash[key] = value
      end
    end

    if valid_hash.any?
      instance_variable_get("@#{attr.to_s}").merge!(valid_hash)
    end
  end

  # Returns true if the obj is one of the provided valid classes.
  def valid_type?(classes, obj)
    valid_type = false
    classes.each do |klass|
      if obj.is_a?(klass)
        valid_type = true
        break
      end
    end
    valid_type
  end

  # take the entire Hash vs. just the value so the logger output is more helpful on error.
  def value_valid?(key_value)
    # ensure one of our accepted types. 
    value = key_value.values.last
    if !valid_type?([String, Symbol, Numeric, Time, Date, TrueClass, FalseClass],value)
      ScoutApm::Agent.instance.logger.warn "The value for [#{key_value.keys.first}] is not a valid type [#{value.class}]."
     false
    else
      true
    end
  end

  # for consistently with #value_valid?, takes a hash eventhough the value isn't yet used.
  def key_valid?(key_value)
    key = key_value.keys.first
    # ensure a string or a symbol
    if !valid_type?([String, Symbol],key)
      ScoutApm::Agent.instance.logger.warn "The key [#{key}] is not a valid type [#{key.class}]."
      return false
    end
    # ensure doesn't contain spaces. 
    if key.to_s.match(/\s/)
      ScoutApm::Agent.instance.logger.warn "They key name [#{key}] is not valid."
      return false
    end
    true
  end
end

class HashShorthandController < ApplicationController
  def hash
    THREAD.current[:ternary_check] = true
    json = {
      static: "static",
      shorthand:,
      longhand: longhand,
      longhand_different_key: longhand,
      :hash_rocket => hash_rocket,
      :hash_rocket_different_key => hash_rocket,
      non_nil_receiver: non_nil_receiver.value,
      nested: {
        shorthand:,
      },
      nested_call: nested_call(params["timestamp"]),
      nested_with_ternaries: {
                            truthy: THREAD.current[:ternary_check] == true ? 1 : 0,
                            falsy: THREAD.current[:ternary_check] == false ? 1 : 0,
                          },
      ternary: ternary ? ternary : nil,
    }
    render json:
  end

  private

  def simple_method
    "simple"
  end

  def inner_method
    "inner"
  end

  def nested_call(noop)
    noop
  end

  def ternary
    true
  end

  def shorthand
    "shorthand"
  end

  def longhand
    "longhand"
  end

  def hash_rocket
    "hash_rocket"
  end

  def non_nil_receiver
    OpenStruct.new(value: "value")
  end
end

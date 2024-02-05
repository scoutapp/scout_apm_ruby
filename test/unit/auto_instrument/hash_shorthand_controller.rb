
class HashShorthandController < ApplicationController
  def hash
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
      nested_call: nested_call(params["timestamp"])
    }
    render json:
  end

  private

  def nested_call(noop)
    noop
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

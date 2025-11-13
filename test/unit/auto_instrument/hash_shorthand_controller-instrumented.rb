
class HashShorthandController < ApplicationController
  def hash
    ::ScoutApm::AutoInstrument("THREAD.current[:ternary_check] = true",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:4:in `hash'"]){THREAD.current[:ternary_check] = true}
    json = {
      static: "static",
      shorthand: ::ScoutApm::AutoInstrument("shorthand:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:7:in `hash'"]){shorthand},
      longhand: ::ScoutApm::AutoInstrument("longhand: longhand",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:8:in `hash'"]){longhand},
      longhand_different_key: ::ScoutApm::AutoInstrument("longhand",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:9:in `hash'"]){longhand},
      hash_rocket: ::ScoutApm::AutoInstrument(":hash_rocket => hash_rocket",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:10:in `hash'"]){hash_rocket},
      :hash_rocket_different_key => ::ScoutApm::AutoInstrument("hash_rocket",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:11:in `hash'"]){hash_rocket},
      non_nil_receiver: ::ScoutApm::AutoInstrument("non_nil_receiver.value",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:12:in `hash'"]){non_nil_receiver.value},
      nested: {
        shorthand: ::ScoutApm::AutoInstrument("shorthand:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:14:in `hash'"]){shorthand},
      },
      nested_call: ::ScoutApm::AutoInstrument("nested_call(params[\"timestamp\"])",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:16:in `hash'"]){nested_call(params["timestamp"])},
      nested_with_ternaries: {
                            truthy: ::ScoutApm::AutoInstrument("THREAD.current[:ternary_check] == true",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:18:in `hash'"]){THREAD.current[:ternary_check] == true} ? 1 : 0,
                            falsy: ::ScoutApm::AutoInstrument("THREAD.current[:ternary_check] == false",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:19:in `hash'"]){THREAD.current[:ternary_check] == false} ? 1 : 0,
                          },
      ternary: ::ScoutApm::AutoInstrument("ternary",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:21:in `hash'"]){ternary} ? ::ScoutApm::AutoInstrument("ternary",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:21:in `hash'"]){ternary} : nil,
    }
    ::ScoutApm::AutoInstrument("render json:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:23:in `hash'"]){render json:}
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
    ::ScoutApm::AutoInstrument("OpenStruct.new(value: \"value\")",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:57:in `non_nil_receiver'"]){OpenStruct.new(value: "value")}
  end
end

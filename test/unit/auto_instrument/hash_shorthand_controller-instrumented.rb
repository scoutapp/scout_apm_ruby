
class HashShorthandController < ApplicationController
  def hash
    json = {
      static: "static",
      shorthand: ::ScoutApm::AutoInstrument("shorthand:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:6:in `hash'"]){shorthand},
      longhand: ::ScoutApm::AutoInstrument("longhand: longhand",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:7:in `hash'"]){longhand},
      longhand_different_key: ::ScoutApm::AutoInstrument("longhand",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:8:in `hash'"]){longhand},
      hash_rocket: ::ScoutApm::AutoInstrument(":hash_rocket => hash_rocket",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:9:in `hash'"]){hash_rocket},
      :hash_rocket_different_key => ::ScoutApm::AutoInstrument("hash_rocket",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:10:in `hash'"]){hash_rocket},
      non_nil_receiver: ::ScoutApm::AutoInstrument("non_nil_receiver.value",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:11:in `hash'"]){non_nil_receiver.value},
      nested: {
        shorthand: ::ScoutApm::AutoInstrument("shorthand:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:13:in `hash'"]){shorthand},
      }
    }
    ::ScoutApm::AutoInstrument("render json:",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:16:in `hash'"]){render json:}
  end

  private

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
    ::ScoutApm::AutoInstrument("OpenStruct.new(value: \"value\")",["ROOT/test/unit/auto_instrument/hash_shorthand_controller.rb:34:in `non_nil_receiver'"]){OpenStruct.new(value: "value")}
  end
end

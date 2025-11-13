
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("params[:status] == \"activated\"",["ROOT/test/unit/auto_instrument/controller.rb:6:in `index'"]){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("Client.activated",["ROOT/test/unit/auto_instrument/controller.rb:7:in `index'"]){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("Client.inactivated",["ROOT/test/unit/auto_instrument/controller.rb:9:in `index'"]){Client.inactivated}
    end
  end

  def new
    ::ScoutApm::AutoInstrument("super do |something|...",["ROOT/test/unit/auto_instrument/controller.rb:14:in `new'"]){super do |something|
      @client = Client.new
    end}
  end

  def create
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["ROOT/test/unit/auto_instrument/controller.rb:20:in `create'"]){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("@client.save",["ROOT/test/unit/auto_instrument/controller.rb:21:in `create'"]){@client.save}
      ::ScoutApm::AutoInstrument("redirect_to @client",["ROOT/test/unit/auto_instrument/controller.rb:22:in `create'"]){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("render \"new\"",["ROOT/test/unit/auto_instrument/controller.rb:26:in `create'"]){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["ROOT/test/unit/auto_instrument/controller.rb:31:in `edit'"]){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("request.post?",["ROOT/test/unit/auto_instrument/controller.rb:33:in `edit'"]){request.post?}
      ::ScoutApm::AutoInstrument("@client.transaction do...",["ROOT/test/unit/auto_instrument/controller.rb:34:in `edit'"]){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("Client.all",["ROOT/test/unit/auto_instrument/controller.rb:41:in `data'"]){Client.all}

    formatter = ::ScoutApm::AutoInstrument("proc do |row|...",["ROOT/test/unit/auto_instrument/controller.rb:43:in `data'"]){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("respond_with @clients.each(&formatter).join(\"\\n\"), :content_type => 'application/json; boundary=NL'",["ROOT/test/unit/auto_instrument/controller.rb:47:in `data'"]){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("'foo'.size",["ROOT/test/unit/auto_instrument/controller.rb:53:in `things'"]){'foo'.size}
  end

  def do_something
    ::ScoutApm::AutoInstrument("wrap_call(\"123\",...",["ROOT/test/unit/auto_instrument/controller.rb:57:in `do_something'"]){wrap_call("123",
              something: -> { puts "Do something" }
            ) do

      raw_data = '{ "key": "123" }'

      payload = begin
                  Marshal.load(raw_data)
                rescue
                  puts 'Failed with bad/unhelpful error message'
                end
    end}
  end

  def wrap_call(*args, **kwargs)
    yield
  end
end

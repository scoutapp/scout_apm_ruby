
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

  def test
    ::ScoutApm::AutoInstrument("wrapper([\"app_server_load\", 123],...",["ROOT/test/unit/auto_instrument/controller.rb:57:in `test'"]){wrapper(["app_server_load", 123],
            period: 60,
            if_limited: -> { puts "Rate limited id=123" }
           ) do

      raw_data = "{ \"git_sha\": \"abc123\", \"value\": 42 }"

      payload = begin
                  # Simulate Marshal failure
                  Marshal.load(raw_data)
                rescue
                  require "json"
                  JSON.parse(raw_data, symbolize_names: true)
                end
    end}
  end

  # Dummy methods so the AST doesn’t reference undefined constants
  def wrapper(*args, **kwargs)
    yield
  end

  def track(id, sha, hostname:)
    ::ScoutApm::AutoInstrument("puts \"Tracking id=\#{id}, sha=\#{sha}, host=\#{hostname}\"",["ROOT/test/unit/auto_instrument/controller.rb:80:in `track'"]){puts "Tracking id=#{id}, sha=#{sha}, host=#{hostname}"}
  end

  def do_work(payload)
    ::ScoutApm::AutoInstrument("puts \"Work = \#{payload.inspect}\"",["ROOT/test/unit/auto_instrument/controller.rb:84:in `do_work'"]){puts "Work = #{payload.inspect}"}
  end
end


class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("params[:status] == \"activated\"",["BACKTRACE"]){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("Client.activated",["BACKTRACE"]){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("Client.inactivated",["BACKTRACE"]){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["BACKTRACE"]){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("@client.save",["BACKTRACE"]){@client.save}
      ::ScoutApm::AutoInstrument("redirect_to @client",["BACKTRACE"]){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("render \"new\"",["BACKTRACE"]){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["BACKTRACE"]){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("request.post?",["BACKTRACE"]){request.post?}
      ::ScoutApm::AutoInstrument("@client.transaction do...",["BACKTRACE"]){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("Client.all",["BACKTRACE"]){Client.all}

    formatter = ::ScoutApm::AutoInstrument("proc do |row|...",["BACKTRACE"]){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("respond_with @clients.each(&formatter).join(\"\\n\"), :content_type => 'application/json; boundary=NL'",["BACKTRACE"]){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("'foo'.size",["BACKTRACE"]){'foo'.size}
  end
end

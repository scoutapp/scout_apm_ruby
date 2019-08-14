
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("ClientsController\#index:6", "params[:status] == \"activated\""){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("ClientsController\#index:7", "Client.activated"){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("ClientsController\#index:9", "Client.inactivated"){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument("ClientsController\#create:14", "Client.new(params[:client])"){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("ClientsController\#create:15", "@client.save"){@client.save}
      ::ScoutApm::AutoInstrument("ClientsController\#create:16", "redirect_to @client"){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("ClientsController\#create:20", "render \"new\""){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("ClientsController\#edit:25", "Client.new(params[:client])"){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("ClientsController\#edit:27", "request.post?"){request.post?}
      ::ScoutApm::AutoInstrument("ClientsController\#edit:28", "@client.transaction do..."){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("ClientsController\#data:35", "Client.all"){Client.all}

    formatter = ::ScoutApm::AutoInstrument("ClientsController\#data:37", "proc do |row|..."){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("ClientsController\#data:41", "respond_with @clients.each(&formatter).join(\"\\n\"), :content_type => 'application/json; boundary=NL'"){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("ClientsController\#things:47", "'foo'.size"){'foo'.size}
  end
end

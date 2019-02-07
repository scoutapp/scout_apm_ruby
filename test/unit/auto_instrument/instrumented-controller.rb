
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("#{self.class}\#index:6", "params[:status] == \"activated\""){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("#{self.class}\#index:7", "Client.activated"){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("#{self.class}\#index:9", "Client.inactivated"){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument("#{self.class}\#create:14", "Client.new(params[:client])"){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("#{self.class}\#create:15", "@client.save"){@client.save}
      ::ScoutApm::AutoInstrument("#{self.class}\#create:16", "redirect_to @client"){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("#{self.class}\#create:20", "render \"new\""){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("#{self.class}\#edit:25", "Client.new(params[:client])"){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("#{self.class}\#edit:27", "request.post?"){request.post?}
      ::ScoutApm::AutoInstrument("#{self.class}\#edit:28", "@client.transaction do..."){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("#{self.class}\#data:35", "Client.all"){Client.all}

    formatter = ::ScoutApm::AutoInstrument("#{self.class}\#data:37", "proc do |row|..."){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("#{self.class}\#data:41", "respond_with @clients.each(&formatter).join(\"\\n\"), :content_type => 'application/json; boundary=NL'"){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("#{self.class}\#things:47", "'foo'.size"){'foo'.size}
  end
end

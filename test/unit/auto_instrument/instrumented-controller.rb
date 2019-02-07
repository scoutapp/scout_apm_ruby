
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("#{self.class}\#==:L6:C7"){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("#{self.class}\#activated:L7:C17"){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("#{self.class}\#inactivated:L9:C17"){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument("#{self.class}\#new:L14:C14"){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("#{self.class}\#save:L15:C7"){@client.save}
      ::ScoutApm::AutoInstrument("#{self.class}\#redirect_to:L16:C6"){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("#{self.class}\#render:L20:C6"){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("#{self.class}\#new:L25:C14"){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("#{self.class}\#post?:L27:C7"){request.post?}
      ::ScoutApm::AutoInstrument("#{self.class}\#transaction:L28:C6"){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("#{self.class}\#all:L35:C15"){Client.all}

    formatter = ::ScoutApm::AutoInstrument("#{self.class}\#proc:L37:C16"){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("#{self.class}\#respond_with:L41:C4"){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("#{self.class}\#size:L47:C17"){'foo'.size}
  end
end

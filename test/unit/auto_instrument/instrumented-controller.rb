
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument('==:L6:C7'){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument('activated:L7:C17'){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument('inactivated:L9:C17'){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument('new:L14:C14'){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument('save:L15:C7'){@client.save}
      ::ScoutApm::AutoInstrument('redirect_to:L16:C6'){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument('render:L20:C6'){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument('new:L25:C14'){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument('post?:L27:C7'){request.post?}
      ::ScoutApm::AutoInstrument('transaction:L28:C6'){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument('all:L35:C15'){Client.all}

    formatter = ::ScoutApm::AutoInstrument('proc:L37:C16'){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument('respond_with:L41:C4'){respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument('size:L47:C17'){'foo'.size}
  end
end


class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument("params[:status] == \"activated\"",["BACKTRACE"],'FILE_NAME'){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument("Client.activated",["BACKTRACE"],'FILE_NAME'){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument("Client.inactivated",["BACKTRACE"],'FILE_NAME'){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["BACKTRACE"],'FILE_NAME'){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument("@client.save",["BACKTRACE"],'FILE_NAME'){@client.save}
      ::ScoutApm::AutoInstrument("redirect_to @client",["BACKTRACE"],'FILE_NAME'){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument("render \"new\"",["BACKTRACE"],'FILE_NAME'){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument("Client.new(params[:client])",["BACKTRACE"],'FILE_NAME'){Client.new(params[:client])}

    if ::ScoutApm::AutoInstrument("request.post?",["BACKTRACE"],'FILE_NAME'){request.post?}
      ::ScoutApm::AutoInstrument("@client.transaction do...",["BACKTRACE"],'FILE_NAME'){@client.transaction do
        @client.update_attributes(params[:client])
      end}
    end
  end

  def data
    @clients = ::ScoutApm::AutoInstrument("Client.all",["BACKTRACE"],'FILE_NAME'){Client.all}

    formatter = ::ScoutApm::AutoInstrument("proc do |row|...",["BACKTRACE"],'FILE_NAME'){proc do |row|
      row.to_json
    end}

    ::ScoutApm::AutoInstrument("respond_with @clients.each(&formatter).join(\"\\n\"), :content_type => 'FILE_NAME'}
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= ::ScoutApm::AutoInstrument("'FILE_NAME'.size}
  end
end

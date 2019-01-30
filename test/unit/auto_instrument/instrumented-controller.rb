
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::AutoInstrument('==:l6:c7'){params[:status] == "activated"}
      @clients = ::ScoutApm::AutoInstrument('activated:l7:c17'){Client.activated}
    else
      @clients = ::ScoutApm::AutoInstrument('inactivated:l9:c17'){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::AutoInstrument('new:l14:c14'){Client.new(params[:client])}
    if ::ScoutApm::AutoInstrument('save:l15:c7'){@client.save}
      ::ScoutApm::AutoInstrument('redirect_to:l16:c6'){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::AutoInstrument('render:l20:c6'){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::AutoInstrument('new:l25:c14'){Client.new(params[:client])}
    
    if ::ScoutApm::AutoInstrument('post?:l27:c7'){request.post?}
      @client.transaction do
        @client.update_attributes(params[:client])
      end
    end
  end
end

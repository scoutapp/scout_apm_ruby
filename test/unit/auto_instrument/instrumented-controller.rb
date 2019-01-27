
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('==:l6:c7'){params[:status] == "activated"}
      @clients = ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('activated:l7:c17'){Client.activated}
    else
      @clients = ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('inactivated:l9:c17'){Client.inactivated}
    end
  end

  def create
    @client = ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('new:l14:c14'){Client.new(params[:client])}
    if ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('save:l15:c7'){@client.save}
      ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('redirect_to:l16:c6'){redirect_to @client}
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('render:l20:c6'){render "new"}
    end
  end

  def edit
    @client = ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('new:l25:c14'){Client.new(params[:client])}
    
    if ::ScoutApm::Instruments::AutoInstruments.dynamic_layer('post?:l27:c7'){request.post?}
      @client.transaction do
        @client.update_attributes(params[:client])
      end
    end
  end
end

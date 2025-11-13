
class ClientsController < ApplicationController
  before_action :check_authorization

  def index
    if params[:status] == "activated"
      @clients = Client.activated
    else
      @clients = Client.inactivated
    end
  end

  def new
    super do |something|
      @client = Client.new
    end
  end

  def create
    @client = Client.new(params[:client])
    if @client.save
      redirect_to @client
    else
      # This line overrides the default rendering behavior, which
      # would have been to render the "create" view.
      render "new"
    end
  end

  def edit
    @client = Client.new(params[:client])

    if request.post?
      @client.transaction do
        @client.update_attributes(params[:client])
      end
    end
  end

  def data
    @clients = Client.all

    formatter = proc do |row|
      row.to_json
    end

    respond_with @clients.each(&formatter).join("\n"), :content_type => 'application/json; boundary=NL'
  end
  
  def things
    x = {}
    x[:this] ||= 'foo'
    x[:that] &&= 'foo'.size
  end

  def test
    wrapper(["app_server_load", 123],
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
    end
  end

  # Dummy methods so the AST doesn’t reference undefined constants
  def wrapper(*args, **kwargs)
    yield
  end

  def track(id, sha, hostname:)
    puts "Tracking id=#{id}, sha=#{sha}, host=#{hostname}"
  end

  def do_work(payload)
    puts "Work = #{payload.inspect}"
  end
end

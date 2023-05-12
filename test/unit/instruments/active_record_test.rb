require 'test_helper'
require 'sqlite3'
require 'active_record'

begin
  require 'octoshark'
rescue LoadError
  # Ignore
end

class ActiveRecordTest < Minitest::Test
  def database_path
    File.expand_path('test.sqlite3', DATA_FILE_DIR)
  end

  def setup
    database = SQLite3::Database.new(database_path)
    database.execute("DROP TABLE IF EXISTS users;")
    database.execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(100));")

    ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => database_path)
  end

  class User < ActiveRecord::Base
  end

  class DumbRailsConfig
    def self.after_initialize; end
  end

  def test_old_rails_initialization
    recorder = FakeRecorder.new
    agent_context.recorder = recorder
    old_rails_version = (1..2).to_a.sample
    fake_rails(old_rails_version)

    ::Rails.expects(:configuration).never

    instrument = ScoutApm::Instruments::ActiveRecord.new(agent_context)
    instrument.install(prepend: false)
    clean_fake_rails
  end

  def test_modern_rails_initialization
    recorder = FakeRecorder.new
    agent_context.recorder = recorder
    modern_rails_version = (3..7).to_a.sample
    fake_rails(modern_rails_version)

    ::Rails.expects(:configuration).returns(DumbRailsConfig).once

    instrument = ScoutApm::Instruments::ActiveRecord.new(agent_context)
    instrument.install(prepend: false)
    clean_fake_rails
  end

  def test_instrumentation
    recorder = FakeRecorder.new
    agent_context.recorder = recorder

    instrument = ScoutApm::Instruments::ActiveRecord.new(agent_context)
    instrument.install(prepend: false)

    ScoutApm::Tracer.instrument("Controller", "foo/bar") do
      user = User.create
    end

    assert 1, recorder.requests.size
  end
end

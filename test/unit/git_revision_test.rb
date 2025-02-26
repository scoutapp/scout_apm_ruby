require 'test_helper'

require 'scout_apm/git_revision'

class GitRevisionTest < Minitest::Test
  def setup
    @env = ENV.to_h
  end

  def teardown
    ENV.replace(@env)
  end

  def test_sha_detected_once
    ENV['HEROKU_SLUG_COMMIT'] = 'initial_slug'
    revision = ScoutApm::GitRevision.new(ScoutApm::AgentContext.new)
    assert_equal 'initial_slug', revision.sha

    ENV['HEROKU_SLUG_COMMIT'] = 'new_slug'
    assert_equal 'initial_slug', revision.sha
  end

  def test_sha_from_config
    config = make_fake_config('revision_sha' => 'config_sha')
    context = ScoutApm::AgentContext.new().tap { |c| c.config = config }
    revision = ScoutApm::GitRevision.new(context)

    assert_equal 'config_sha', revision.sha
  end

  def test_sha_from_heroku
    ENV['HEROKU_SLUG_COMMIT'] = 'heroku_slug'
    revision = ScoutApm::GitRevision.new(ScoutApm::AgentContext.new)
    assert_equal 'heroku_slug', revision.sha
  end

  def test_sha_from_capistrano
    Dir.mktmpdir do |dir|
      context = context_with_file_in_root(File.join(dir, 'REVISION'), 'capistrano_sha')
      revision = ScoutApm::GitRevision.new(context)
      assert_equal 'capistrano_sha', revision.sha
    end
  end

  def test_sha_from_kamal
    ENV['KAMAL_VERSION'] = 'kamal_sha'
    revision = ScoutApm::GitRevision.new(ScoutApm::AgentContext.new)
    assert_equal 'kamal_sha', revision.sha
  end


  def test_sha_from_mina
    Dir.mktmpdir do |dir|
      context = context_with_file_in_root(File.join(dir, '.mina_git_revision'), 'mina_sha')
      revision = ScoutApm::GitRevision.new(context)
      assert_equal 'mina_sha', revision.sha
    end
  end

  def test_sha_from_git
    short_sha = `git rev-parse --short HEAD`.strip
    skip 'git not installed or not in a git repository' if short_sha.empty?

    revision = ScoutApm::GitRevision.new(ScoutApm::AgentContext.new)
    assert_equal short_sha, revision.sha
  end

  private

  def context_with_file_in_root(file_name, contents)
    config = make_fake_config({})
    env = make_fake_environment(root: File.dirname(file_name))
    File.write(file_name, contents)

    ScoutApm::AgentContext.new().tap { |c| c.config = config; c.environment = env }
  end
end

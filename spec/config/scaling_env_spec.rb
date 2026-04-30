# frozen_string_literal: true

require 'erb'
require 'yaml'

RSpec.describe 'runtime scaling configuration' do
  around do |example|
    with_env(
      'DATABASE_URL' => nil,
      'POSTGRES_URL' => nil,
      'PORT' => nil,
      'RAILS_DB_POOL' => nil,
      'RAILS_ENV' => nil,
      'RAILS_MAX_THREADS' => nil,
      'RAILS_MIN_THREADS' => nil,
      'SIDEKIQ_CONCURRENCY' => nil,
      'WEB_CONCURRENCY' => nil
    ) { example.run }
  end

  it 'configures Puma workers and threads from environment variables' do
    with_env(
      'PORT' => '4001',
      'RAILS_ENV' => 'production',
      'RAILS_MAX_THREADS' => '7',
      'RAILS_MIN_THREADS' => '2',
      'WEB_CONCURRENCY' => '4'
    ) do
      config = evaluate_puma_config

      expect(config.fetch(:threads)).to eq(%w[2 7])
      expect(config.fetch(:workers)).to eq('4')
      expect(config.fetch(:preload_app)).to be(true)
      expect(config.fetch(:port)).to eq('4001')
      expect(config.fetch(:environment)).to eq('production')
      expect(config.fetch(:plugin)).to eq(:tmp_restart)
    end
  end

  it 'uses safe Puma defaults' do
    config = evaluate_puma_config

    expect(config.fetch(:threads)).to eq([5, 5])
    expect(config.fetch(:workers)).to eq(2)
    expect(config.fetch(:port)).to eq(3000)
    expect(config.fetch(:environment)).to eq('production')
  end

  it 'configures the production database pool from RAILS_DB_POOL' do
    with_env(
      'DATABASE_URL' => 'postgres://turniere:secret@postgres/turniere',
      'RAILS_DB_POOL' => '9',
      'RAILS_MAX_THREADS' => '7'
    ) do
      config = database_config.fetch('production')

      expect(config.fetch('adapter')).to eq('postgresql')
      expect(config.fetch('encoding')).to eq('unicode')
      expect(config.fetch('url')).to eq('postgres://turniere:secret@postgres/turniere')
      expect(config.fetch('pool')).to eq(9)
    end
  end

  it 'falls back to RAILS_MAX_THREADS for the database pool and POSTGRES_URL for legacy deployments' do
    with_env(
      'POSTGRES_URL' => 'postgres://turniere:secret@legacy-postgres/turniere',
      'RAILS_MAX_THREADS' => '6'
    ) do
      config = database_config.fetch('production')

      expect(config.fetch('url')).to eq('postgres://turniere:secret@legacy-postgres/turniere')
      expect(config.fetch('pool')).to eq(6)
    end
  end

  it 'configures Sidekiq concurrency from SIDEKIQ_CONCURRENCY' do
    with_env('SIDEKIQ_CONCURRENCY' => '10') do
      expect(sidekiq_config).to include(':concurrency: 10')
    end

    expect(sidekiq_config).to include(':concurrency: 5')
  end

  def evaluate_puma_config
    probe = puma_config_probe_class.new
    probe.instance_eval(File.read(File.join(root, 'config/puma.rb')), File.join(root, 'config/puma.rb'))
    probe.config
  end

  def database_config
    YAML.safe_load(ERB.new(File.read(File.join(root, 'config/database.yml'))).result, aliases: true)
  end

  def sidekiq_config
    ERB.new(File.read(File.join(root, 'config/sidekiq.yml'))).result
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [key, ENV.fetch(key, nil)] }
    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def root
    File.expand_path('../..', __dir__)
  end

  def puma_config_probe_class
    Class.new do
      attr_reader :config

      def initialize
        @config = {}
      end

      def threads(min_threads, max_threads)
        @config[:threads] = [min_threads, max_threads]
      end

      def workers(count)
        @config[:workers] = count
      end

      def preload_app!
        @config[:preload_app] = true
      end

      def port(value)
        @config[:port] = value
      end

      def environment(value)
        @config[:environment] = value
      end

      def plugin(name)
        @config[:plugin] = name
      end
    end
  end
end

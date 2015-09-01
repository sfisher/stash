require 'spec_helper'

module Stash
  module Harvester
    describe Config do
      describe '#new' do
        it 'requires db, source, and index config'
      end

      describe '#from_yaml' do

        before(:each) do
          yml = File.read('spec/data/config.yml')
          expect(yml).not_to be_nil
          @config = Config.from_yaml(yml)
        end

        it 'extracts the DB connection info' do
          connection_info = @config.connection_info
          expect(connection_info['adapter']).to eq('sqlite3')
          expect(connection_info['database']).to eq(':memory:')
          expect(connection_info['pool']).to eq(5)
          expect(connection_info['timeout']).to eq(5000)
        end

        it 'extracts the IndexConfig' do
          index_config = @config.index_config
          expect(index_config).to be_a(Solr::SolrIndexConfig)
          expect(index_config.uri).to eq(URI('http://solr.example.org/'))
          expect(index_config.proxy_uri).to eq(URI('http://foo:bar@proxy.example.com/'))

          opts = index_config.opts
          expect(opts[:url]).to eq('http://solr.example.org/')
          expect(opts[:proxy]).to eq('http://foo:bar@proxy.example.com/')
          expect(opts[:open_timeout]).to eq(120)
          expect(opts[:read_timeout]).to eq(300)
          expect(opts[:retry_503]).to eq(3)
          expect(opts[:retry_after_limit]).to eq(20)
        end

        it 'extracts the SourceConfig' do
          source_config = @config.source_config
          expect(source_config).to be_a(OAI::OAISourceConfig)
          expect(source_config.source_uri).to eq(URI('http://oai.example.org/oai'))
          expect(source_config.metadata_prefix).to eq('some_prefix')
          expect(source_config.set).to eq('some_set')
          expect(source_config.seconds_granularity).to be true
        end

        it 'provides appropriate error messages for bad config factories'
      end
    end
  end
end

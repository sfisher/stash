require 'db_spec_helper'
require 'webmock/rspec'

module StashEngine
  
  describe Identifier do
    attr_reader :identifier
    attr_reader :usage1
    attr_reader :usage2
    attr_reader :res1
    attr_reader :res2
    attr_reader :res3

    before(:each) do
      @identifier = Identifier.create(identifier_type: 'DOI', identifier: '10.123/456')
      @res1 = Resource.create(identifier_id: identifier.id)
      @res2 = Resource.create(identifier_id: identifier.id)
      @res3 = Resource.create(identifier_id: identifier.id)

      WebMock.disable_net_connect!
    end
        
    describe '#to_s' do
      it 'returns something useful' do
        expect(identifier.to_s).to eq('doi:10.123/456')
      end
    end
    
    describe 'versioning' do
      before(:each) do
        res1.current_state = 'submitted'
        Version.create(resource_id: res1.id, version: 1)

        res2.current_state = 'submitted'
        Version.create(resource_id: res2.id, version: 2)

        res3.current_state = 'in_progress'
        Version.create(resource_id: res3.id, version: 3)

        identifier.save!
      end

      describe '#first_submitted_resource' do
        it 'returns the first submitted version' do
          lsv = identifier.first_submitted_resource
          expect(lsv.id).to eq(res1.id)
        end
      end

      describe '#last_submitted_resource' do
        it 'returns the last submitted version' do
          lsv = identifier.last_submitted_resource
          expect(lsv.id).to eq(res2.id)
        end
      end

      describe '#latest_resource' do
        it 'returns the latest resource' do
          #expect(identifier.latest_resource).to eq(1)
        end
      end

      
      describe '#in_progress_resource' do
        it 'returns the in-progress version' do
          ipv = identifier.in_progress_resource
          expect(ipv.id).to eq(res3.id)
        end
      end

      describe '#in_progress?' do
        it 'returns true if an in-progress version exists' do
          expect(identifier.in_progress?).to eq(true)
        end
        it 'returns false if no in-progress version exists' do
          res3.current_state = 'submitted'
          expect(identifier.in_progress?).to eq(false)
        end
      end

      describe '#processing_resource' do
        before(:each) do
          res2.current_state = 'processing'
        end

        it 'returns the "processing" version' do
          pv = identifier.processing_resource
          expect(pv.id).to eq(res2.id)
        end
      end

      describe '#processing?' do
        it 'returns false if no "processing" version exists' do
          expect(identifier.processing?).to eq(false)
        end

        it 'returns true if a "processing" version exists' do
          res2.current_state = 'processing'
          expect(identifier.processing?).to eq(true)
        end
      end

      describe '#error?' do
        it 'returns false if no "error" version exists' do
          expect(identifier.error?).to eq(false)
        end

        it 'returns true if a "error" version exists' do
          res2.current_state = 'error'
          expect(identifier.error?).to eq(true)
        end
      end

      # TODO: in progress is just the in-progress state itself of the group of in_progress states.  We need to fix our terminology.
      describe '#in_progress_only?' do
        it 'returns false if no "in_progress_only" version exists' do
          res3.current_state = 'submitted'
          expect(identifier.in_progress_only?).to eq(false)
        end

        it 'returns true if a "in_progress_only" version exists' do
          res2.current_state = 'error'
          expect(identifier.in_progress_only?).to eq(true)
        end
      end

      describe '#resources_with_file_changes' do
        before(:each) do
          FileUpload.create(resource_id: res1.id, upload_file_name: 'cat', file_state: 'created')
          FileUpload.create(resource_id: res2.id, upload_file_name: 'cat', file_state: 'copied')
          FileUpload.create(resource_id: res3.id, upload_file_name: 'cat', file_state: 'copied')
        end

        it 'returns the version that changed' do
          resources = identifier.resources_with_file_changes
          expect(resources.first.id).to eq(res1.id)
          expect(resources.count).to eq(1)
        end
      end

      describe '#latest_resource_with_public_metadata' do
        before(:each) do
          @user = User.new
          allow_any_instance_of(CurationActivity).to receive(:update_solr).and_return(true)
          allow_any_instance_of(CurationActivity).to receive(:submit_to_stripe).and_return(true)
          allow_any_instance_of(CurationActivity).to receive(:submit_to_datacite).and_return(true)
        end

        it 'finds the last published resource' do
          @res1.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res1.curation_activities << CurationActivity.create(status: 'published', user: @user)
          @res2.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res2.curation_activities << CurationActivity.create(status: 'published', user: @user)
          @res3.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          expect(@identifier.latest_resource_with_public_metadata).to eql(@res2)
        end

        it 'finds embargoed published resource' do
          @res1.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res1.curation_activities << CurationActivity.create(status: 'published', user: @user)
          @res2.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res2.curation_activities << CurationActivity.create(status: 'embargoed', user: @user)
          @res3.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          expect(@identifier.latest_resource_with_public_metadata).to eql(@res2)
        end

        it 'finds no published resource' do
          @res1.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res2.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          @res3.curation_activities << CurationActivity.create(status: 'curation', user: @user)
          expect(@identifier.latest_resource_with_public_metadata).to eql(nil)
        end

      end

      describe '#update_search_words!' do
        before(:each) do
          @identifier2 = Identifier.create(identifier_type: 'DOI', identifier: '10.123/450')
          @res5 = Resource.create(identifier_id: @identifier2.id, title: 'Frolicks with the seahorses')
          @identifier2.save!
          Author.create(author_first_name: 'Joanna', author_last_name: 'Jones', author_orcid: '33-22-4838-3322', resource_id: @res5.id)
          Author.create(author_first_name: 'Marcus', author_last_name: 'Lee', author_orcid: '88-11-1138-2233', resource_id: @res5.id)
        end

        it 'has concatenated all the search fields' do
          @identifier2.reload
          @identifier2.update_search_words!
          expect(@identifier2.search_words.strip).to eq('doi:10.123/450 Frolicks with the seahorses ' \
            'Joanna Jones  33-22-4838-3322 Marcus Lee  88-11-1138-2233')
        end
      end
    end

    describe '#payment' do
      it 'defaults to user pay' do
        expect(identifier.user_must_pay?).to eq(true)
      end

      it 'does not make user pay when journal pays' do
        fake_issn = 'some-bogus-value'
        int_datum = InternalDatum.new(identifier_id: identifier.id, data_type: 'publicationISSN', value: fake_issn)
        int_datum.save!
        stub_request(:any, /journals\/#{fake_issn}/).
          to_return(body: '{"paymentPlanType":"SUBSCRIPTION"}',
                    status: 200,
                    headers: {"Content-Type"=> "application/json"})
        
        expect(identifier.journal_will_pay?).to eq(true)
        expect(identifier.user_must_pay?).to eq(false)
      end

      it 'makes the user pay when journal does not pay' do
        fake_issn = 'some-bogus-value2'
        int_datum = InternalDatum.new(identifier_id: identifier.id, data_type: 'publicationISSN', value: fake_issn)
        int_datum.save!
        stub_request(:any, /journals\/#{fake_issn}/).
          to_return(body: '{"paymentPlanType":"NONE"}',
                    status: 200,
                    headers: {"Content-Type"=> "application/json"})
        
        expect(identifier.journal_will_pay?).to eq(false)
        expect(identifier.user_must_pay?).to eq(true)
      end

      it 'does not make user pay when institution pays' do
#        res1.current_state = 'submitted'
#        Version.create(resource_id: res1.id, version: 1)
#        res1.save!
        
#        expect(identifier.institution_will_pay?).to eq(true)
#        expect(identifier.user_must_pay?).to eq(false)
      end
    end

  end
end

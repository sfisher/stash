require 'spec_helper'

module Stash
  module Indexer
    module DataciteGeoblacklight
      describe Mapper do
        describe '#to_index_document' do
          DM = Datacite::Mapping
          SW = Stash::Wrapper

          before(:each) do

            @doi_value = '10.14749/1407399498'
            @default_title = 'An Account of a Very Odd Monstrous Calf'
            @creator_names = ['Hedy Lamarr', 'Herschlag, Natalie']
            @resource_type_value = 'Other'
            @publisher = 'California Digital Library'
            @subjects = [
              'Assessment',
              'Information Literacy',
              'Engineering',
              'Undergraduate Students',
              'CELT',
              'Purdue University'
            ]
            @places = {
              'Hogwarts' => DM::GeoLocationPoint.new(57.1267878, -3.8796586),
              'Uagadou' => DM::GeoLocationPoint.new(0.3127848, 29.7234399),
              'Ilvermorny' => DM::GeoLocationPoint.new(46.2992002, -74.0356198),
              'Castelobruxo' => DM::GeoLocationPoint.new(-8.1466343, -60.3444434)
            }
            locations = @places.map { |plc, pt| DM::GeoLocation.new(place: plc, point: pt) }

            @boxes = [
              DM::GeoLocationBox.new(56.7843, -3.8727, 57.1497, -3.1641),
              DM::GeoLocationBox.new(0.357869, 29.873028, 0.385076, 29.903498),
              DM::GeoLocationBox.new(46.5456, -73.9478, 47.087, -72.9272),
              DM::GeoLocationBox.new(-8.9773, -61.2817, -5.7854, -57.7551)
            ]
            locations.push(*(@boxes.map { |box| DM::GeoLocation.new(box: box) }))

            @points = [
              DM::GeoLocationPoint.new(56.97, -3.52),
              DM::GeoLocationPoint.new(0.37, 29.89),
              DM::GeoLocationPoint.new(46.82, -73.43),
              DM::GeoLocationPoint.new(-7.38, -59.52)
            ]
            @dates = ['2000', '2001-02-03', '2010-10-01/2011-02-15', '2012/2015', '2010', '2011',
                      '2012', '2013', '2014', '2015']

            @descriptions = [DM::Description.new(
              value: 'Your cat has fleas. Now you get to learn to eradicate them.',
              type: DM::DescriptionType.find_by_value('Abstract')
            )]

            locations.push(*(@points.map { |pt| DM::GeoLocation.new(point: pt) }))

            id = DM::Identifier.new(value: @doi_value)
            creators = [
              DM::Creator.new(
                name: @creator_names[0],
                identifier: DM::NameIdentifier.new(scheme: 'ISNI', scheme_uri: URI('http://isni.org/'), value: '0000-0001-1690-159X'),
                affiliations: ['United Artists', 'Metro-Goldwyn-Mayer']
              ),
              DM::Creator.new(
                name: @creator_names[1],
                identifier: DM::NameIdentifier.new(scheme: 'ISNI', scheme_uri: URI('http://isni.org/'), value: '0000-0001-0907-8419'),
                affiliations: ['Gaumont Buena Vista International', '20th Century Fox']
              )
            ]
            titles = [
              DM::Title.new(value: @default_title, language: 'en-emodeng'),
              DM::Title.new(
                type: DM::TitleType::SUBTITLE,
                value: 'And a Contest between Two Artists about Optick Glasses, &c',
                language: 'en-emodeng'
              )
            ]
            pub_year = 2015
            dates = [
              DM::Date.new(type: DM::DateType.find_by_value('Accepted'), value: '2000'),
              DM::Date.new(type: DM::DateType.find_by_value('Created'), value: Date.new(2001, 2, 3)),
              DM::Date.new(type: DM::DateType.find_by_value('Collected'), value: '2010-10-01/2011-02-15'),
              DM::Date.new(type: DM::DateType.find_by_value('Submitted'), value: '2012/2015')
            ]

            @resource = DM::Resource.new(
              identifier: id,
              creators: creators,
              titles: titles,
              publisher: @publisher,
              publication_year: pub_year,
              resource_type: DM::ResourceType.new(resource_type_general: DM::ResourceTypeGeneral::DATASET, value: @resource_type_value),
              subjects: @subjects.map { |s| DM::Subject.new(value: s) },
              geo_locations: locations,
              dates: dates,
              descriptions: @descriptions
            )

            payload_xml = @resource.save_to_xml

            @wrapper = SW::StashWrapper.new(
              identifier: SW::Identifier.new(type: SW::IdentifierType::DOI, value: @doi_value),
              version: SW::Version.new(number: 1, date: Date.new(2013, 8, 18), note: 'Sample wrapped Datacite document'),
              license: SW::License::CC_BY,
              embargo: SW::Embargo.new(
                type: SW::EmbargoType::DOWNLOAD,
                period: '1 year',
                start_date: Date.new(2013, 8, 18),
                end_date: Date.new(2014, 8, 18)
              ),
              inventory: SW::Inventory.new(
                files: [
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.dat', size_bytes: 12_345, mime_type: 'text/plain'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.csv', size_bytes: 67_890, mime_type: 'text/csv'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.sas7bdat', size_bytes: 123_456, mime_type: 'application/x-sas-data'),
                  SW::StashFile.new(pathname: 'formats.sas7bcat', size_bytes: 78_910, mime_type: 'application/x-sas-catalog'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.sas', size_bytes: 11_121, mime_type: 'application/x-sas'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.sav', size_bytes: 31_415, mime_type: 'application/x-sav'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.sps', size_bytes: 16_171, mime_type: 'application/x-spss'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.dta', size_bytes: 81_920, mime_type: 'application/x-dta'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.dct', size_bytes: 212_223, mime_type: 'application/x-dct'),
                  SW::StashFile.new(pathname: 'HSRC_MasterSampleII.do', size_bytes: 242_526, mime_type: 'application/x-do')
                ]
              ),
              descriptive_elements: [payload_xml]
            )

            @index_document = Mapper.new.to_index_document(@wrapper)
          end

          it 'formats the identifier as a DOI' do
            expect(@index_document[:dc_identifier_s]).to eq("doi:#{@doi_value}")
          end

          it 'extracts the title' do
            expect(@index_document[:dc_title_s]).to eq(@default_title)
          end

          it 'extracts the creator names' do
            expect(@index_document[:dc_creator_sm]).to eq(@creator_names)
          end

          it 'extracts the resource type' do
            expect(@index_document[:dc_type_s]).to eq(DM::ResourceTypeGeneral::DATASET.value)
          end

          it 'extracts the subjects' do
            expect(@index_document[:dc_subject_sm]).to eq(@subjects)
          end

          it 'extracts the places' do
            expect(@index_document[:dct_spatial_sm]).to eq(@places.keys)
          end

          it 'extracts the bounding box' do
            expected_box = @resource.calc_bounding_box
            expect(@index_document[:georss_box_s]).to eq(expected_box)
          end

          it 'extracts the bounding box as an envelope' do
            envelope = @resource.bounding_box_envelope
            expect(@index_document[:solr_geom]).to eq(envelope)
          end

          it 'extracts the issue date' do
            d = @wrapper.embargo_end_date
            embargo_end_date = Time.utc(d.year, d.month, d.day).xmlschema
            expect(@index_document[:dct_issued_dt]).to eq(embargo_end_date)
          end

          it 'extracts the publication year' do
            expected_year = @resource.publication_year
            expect(@index_document[:solr_year_i]).to eq(expected_year)
          end

          it 'extracts the rights' do
            expect(@index_document[:dc_rights_s]).to eq(@wrapper.license.name)
          end

          it 'extracts the publisher' do
            expect(@index_document[:dc_publisher_s]).to eq(@publisher)
          end

          it 'extracts and calculates dates (years)' do
            expect(@index_document[:dct_temporal_sm]).to eq(@dates)
          end

          it 'expects abstract (description) to be present' do
            expect(@index_document[:dc_description_s]).to eq(@descriptions.first.value)
          end
        end

        describe '#desc_from' do
          it 'returns a description' do
            mapper = Mapper.new
            expect(mapper.desc_from).to be_a(String)
          end
        end

        describe '#desc_to' do
          it 'returns a description' do
            mapper = Mapper.new
            expect(mapper.desc_to).to be_a(String)
          end
        end

      end
    end
  end
end

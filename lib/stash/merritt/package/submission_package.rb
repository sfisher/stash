require 'fileutils'
require 'tmpdir'
require 'stash_engine'
require 'stash_datacite'
require 'datacite/mapping/datacite_xml_factory'
require 'stash/merritt/package/data_one_manifest_builder'
require 'stash/merritt/package/merritt_datacite_builder'
require 'stash/merritt/package/merritt_delete_builder'
require 'stash/merritt/package/merritt_oaidc_builder'
require 'stash/merritt/package/stash_wrapper_builder'

module Stash
  module Merritt
    module Package
      class SubmissionPackage
        attr_reader :resource
        attr_reader :tenant

        def initialize(resource_id:, tenant:)
          @resource = SubmissionPackage.ensure_resource(resource_id)
          @tenant = SubmissionPackage.ensure_tenant(tenant)
        end

        def resource_id
          resource.id
        end

        def dc3_xml
          @dc3_xml ||= begin
            datacite_xml_factory.build_datacite_xml(datacite_3: true)
          end
        end

        def zipfile
          @zipfile ||= begin
            zipfile_path = File.join(workdir, "#{resource_id}_archive.zip")
            Zip::File.open(zipfile_path, Zip::File::CREATE) do |zipfile|
              builders.each { |builder| add_to_zipfile(zipfile, builder) }
              uploads.each { |upload| zipfile.add(upload[:name], upload[:path]) }
            end
            zipfile_path
          end
        end

        def add_to_zipfile(zipfile, builder)
          return unless (file = builder.write_file(workdir))
          zipfile.add(builder.file_name, file)
        end

        def cleanup!
          FileUtils.remove_dir(workdir)
          @zipfile = nil
        end

        def to_s
          "#{self.class}: submission package for resource #{resource_id}"
        end

        def self.ensure_tenant(tenant)
          return tenant if tenant
          fail ArgumentError, 'Tenant cannot be nil'
        end

        def self.ensure_resource(resource_id)
          resource = StashEngine::Resource.find(resource_id)
          fail ArgumentError, "Resource (#{resource_id}) must have an identifier before submission" unless resource.identifier_str
          resource
        end

        private

        def builders
          [stash_wrapper_builder, mrt_datacite_builder, mrt_oaidc_builder, mrt_dataone_manifest_builder, mrt_delete_builder]
        end

        def stash_wrapper_builder
          @stash_wrapper_builder ||= begin
            Stash::Wrapper::StashWrapperBuilder.new(
              dcs_resource: dc4_resource,
              version_number: version_number,
              uploads: uploads
            )
          end
        end

        def mrt_datacite_builder
          @mrt_datacite_builder ||= MerrittDataciteBuilder.new(datacite_xml_factory)
        end

        def mrt_oaidc_builder
          @mrt_oaidc_builder ||= MerrittOAIDCBuilder.new(resource_id: resource_id, tenant: tenant)
        end

        def mrt_dataone_manifest_builder
          @mrt_dataone_manifest_builder ||= DataONEManifestBuilder.new(uploads)
        end

        def mrt_delete_builder
          @mrt_delete_builder ||= MerrittDeleteBuilder.new(resource_id: resource_id)
        end

        def total_size_bytes
          @total_size_bytes ||= uploads.inject(0) { |sum, upload| sum + upload[:size] }
        end

        def version_number
          @version_number ||= resource.version_number
        end

        def uploads # TODO: something less messy than this map
          @uploads ||= begin
            resource.current_file_uploads.map do |u|
              {
                name: u.upload_file_name,
                type: u.upload_content_type,
                size: u.upload_file_size,
                path: File.join(resource.upload_dir, u.upload_file_name) # TODO: is this right?
              }
            end
          end
        end

        def datacite_xml_factory
          @datacite_xml_factory ||= begin
            Datacite::Mapping::DataciteXMLFactory.new(
              doi_value: resource.identifier_value,
              se_resource_id: resource_id,
              total_size_bytes: total_size_bytes,
              version: version_number
            )
          end
        end

        def dc4_resource
          @dc4_resource ||= datacite_xml_factory.build_resource
        end

        def workdir
          @workdir ||= begin
            path = resource.upload_dir
            FileUtils.mkdir_p(path)
            tmpdir = Dir.mktmpdir('uploads', path)
            File.absolute_path(tmpdir)
          end
        end

      end
    end
  end
end

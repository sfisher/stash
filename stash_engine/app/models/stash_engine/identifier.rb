require 'httparty'

module StashEngine
  # rubocop:disable Metrics/ClassLength
  class Identifier < ActiveRecord::Base
    has_many :resources, class_name: 'StashEngine::Resource', dependent: :destroy
    has_many :orcid_invitations, class_name: 'StashEngine::OrcidInvitation', dependent: :destroy
    has_one :counter_stat, class_name: 'StashEngine::CounterStat', dependent: :destroy
    has_many :internal_data, class_name: 'StashEngine::InternalDatum', dependent: :destroy
    has_one :latest_resource,
            class_name: 'StashEngine::Resource',
            primary_key: 'latest_resource_id',
            foreign_key: 'id'

    # has_many :counter_citations, class_name: 'StashEngine::CounterCitation', dependent: :destroy
    # before_create :build_associations

    # used to build counter stat if needed, trickery to be sure one always exists to begin with
    # https://stackoverflow.com/questions/3808782/rails-best-practice-how-to-create-dependent-has-one-relations
    def counter_stat
      super || build_counter_stat(citation_count: 0, unique_investigation_count: 0, unique_request_count: 0,
                                  created_at: Time.new - 1.day, updated_at: Time.new - 1.day)
    end

    # gets citations for this identifier w/ citation class
    def citations
      CounterCitation.citations(stash_identifier: self)
    end

    # finds by an ID that is full id, not the broken apart stuff
    def self.find_with_id(full_id)
      prefix, i = CGI.unescape(full_id).split(':', 2)
      Identifier.where(identifier_type: prefix, identifier: i).try(:first)
    end

    def identifier_id
      id
    end

    def view_count
      ResourceUsage.joins(resource: :identifier)
        .where('stash_engine_identifiers.identifier = ? AND stash_engine_identifiers.identifier_type = ?',
               identifier, identifier_type).sum(:views)
    end

    def download_count
      ResourceUsage.joins(resource: :identifier)
        .where('stash_engine_identifiers.identifier = ? AND stash_engine_identifiers.identifier_type = ?',
               identifier, identifier_type).sum(:downloads)
    end

    def resources_with_file_changes
      Resource.distinct.where(identifier_id: id)
        .joins(:file_uploads)
        .where(stash_engine_file_uploads: { file_state: %w[created deleted] })
    end

    # these are items that are embargoed or published and can show metadata
    def latest_resource_with_public_metadata
      resources.with_public_metadata.by_version_desc.first
    end

    def last_submitted_version_number
      (lsv = last_submitted_resource) && lsv.version_number
    end

    # this returns a resource object for the last version in Merritt, caching in instance variable for repeated calls
    def last_submitted_resource
      return @last_submitted_resource unless @last_submitted_resource.blank?
      submitted = resources.submitted
      @last_submitted_resource = submitted.by_version_desc.first
    end

    def first_submitted_resource
      submitted = resources.submitted
      submitted.by_version.first
    end

    # @return Resource the current 'processing' resource
    def processing_resource
      processing = resources.processing
      processing.by_version_desc.first
    end

    # @return true if there's a 'processing' version
    def processing?
      resources.processing.count > 0
    end

    # return true if there's an 'error' version
    def error?
      resources.error.count > 0
    end

    def in_progress_only?
      resources.in_progress_only.count > 0
    end

    # @return Resource the current in-progress resource
    def in_progress_resource
      in_progress = resources.in_progress
      in_progress.first
    end

    # @return true if there is an in progress version
    def in_progress?
      resources.in_progress.count > 0
    end

    def to_s
      # TODO: Make sure this is correct for all identifier types
      "#{identifier_type&.downcase}:#{identifier}"
    end

    # the landing URL seems like a view component, but really it's given to people as data outside the view by way of
    # logging, APIs as a target
    #
    # also couldn't calculate this easily in the past because url had some problems with user calculations for tenant
    # but now tenant gets tied to the dataset (resource) for easier and consistent lookup of the domain.
    #
    # TODO: modify all code that calculates the target to use this method if possible/feasible.
    def target
      return @target unless @target.blank?
      r = resources.by_version_desc.first
      tenant = r.tenant
      @target = tenant.full_url(StashEngine::Engine.routes.url_helpers.show_path(to_s))
    end

    # the search words is a special MySQL search field that concatenates the following fields required to be searched over
    # https://github.com/CDL-Dryad/dryad-product-roadmap/issues/125
    # doi (from this model), latest_resource.title, latest_resource.authors (names, emails, orcids), dcs_descriptions of type abstract
    def update_search_words!
      my_string = to_s
      if latest_resource
        my_string << " #{latest_resource.title}"
        my_string << ' ' << latest_resource.authors.map do |author|
          "#{author.author_first_name} #{author.author_last_name} #{author.author_email} #{author.author_orcid}"
        end.join(' ')
        my_string << abstracts
      end
      self.search_words = my_string
      # this updates without futher callbacks on me
      update_column :search_words, my_string
    end

    # Check if the user must pay for this identifier, or if payment is
    # otherwise covered
    def user_must_pay?
      !journal_will_pay? &&
        !institution_will_pay? &&
        !fee_waiver_country?
    end

    def publication_data(field_name)
      return nil if publication_issn.nil?
      url = APP_CONFIG.old_dryad_url + '/api/v1/journals/' + publication_issn
      results = HTTParty.get(url,
                             query: { access_token: APP_CONFIG.old_dryad_access_token },
                             headers: { 'Content-Type' => 'application/json' })
      results.parsed_response[field_name]
    end

    def publication_issn
      internal_data.find_by(data_type: 'publicationISSN')&.value
    end

    def publication_name
      publication_data('fullName')
    end

    def journal_will_pay?
      plan_type = publication_data('paymentPlanType')
      plan_type == 'SUBSCRIPTION' ||
        plan_type == 'PREPAID' ||
        plan_type == 'DEFERRED'
    end

    def institution_will_pay?
      latest_resource&.tenant&.covers_dpc == true
    end

    def fee_waiver_country?
      APP_CONFIG.fee_waiver_countries&.include?(submitter_country)
    end

    # Retrieves the country associated with the submitter's institution
    # using the ROR API: https://github.com/ror-community/ror-api/blob/master/api_documentation.md
    #
    # This is code-smell-ish right now but we have a ticket to rework when Ryan comes back and will get us by for now
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    def submitter_country
      affil = latest_resource&.authors&.first&.affiliation&.long_name
      return if affil.nil?
      url = 'https://api.ror.org/organizations'
      results = HTTParty.get(url,
                             query: { query: affil },
                             headers: { 'Content-Type' => 'application/json' })
      if results.code < 200 || results.code > 299
        logger.error("unable to get results from ROR: #{results.code} returned for #{affil}")
        return nil
      end
      parsed_response = results.parsed_response['items']
      return nil if parsed_response.blank? || parsed_response.first['country'].blank?
      parsed_response.first['country']['country_name']
    rescue HTTParty::Error, SocketError => ex
      logger.error("ROR returned an error attempting organization query #{affil}: #{ex}")
      nil
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

    private

    def abstracts
      return '' unless latest_resource.respond_to?(:descriptions)
      ' ' << latest_resource.descriptions.where(description_type: 'abstract').map do |description|
        ActionView::Base.full_sanitizer.sanitize(description.description)
      end.join(' ')
    end

    # it's ok to defer adding this unless someone asks for the counter_stat
    # def build_associations
    #   counter_stat || true
    # end
  end
  # rubocop:enable Metrics/ClassLength
end

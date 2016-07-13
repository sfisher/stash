module StashDatacite
  class Contributor < ActiveRecord::Base
    self.table_name = 'dcs_contributors'
    belongs_to :resource, class_name: StashDatacite.resource_class.to_s
    belongs_to :name_identifier
    
    ContributorTypes = %w(ContactPerson DataCollector DataCurator DataManager Distributor Editor Funder
          HostingInstitution Other Producer ProjectLeader ProjectManager ProjectMember RegistrationAgency
          RegistrationAuthority RelatedPerson ResearchGroup RightsHolder Researcher Sponsor Supervisor
          WorkPackageLeader)

    ContributorTypesEnum = ContributorTypes.map{|i| [i.downcase.to_sym, i.downcase]}.to_h
    ContributorTypesStrToFull = ContributorTypes.map{|i| [i.downcase, i]}.to_h

    enum contributor_type: ContributorTypesEnum

    before_save :strip_whitespace

    def contributor_type_friendly=(type)
      # self required here to work correctly
      self.contributor_type = type.to_s.downcase unless type.blank?
    end

    def contributor_type_friendly
      return nil if contributor_type.blank?
      ContributorTypesStrToFull[contributor_type]
    end

    private
    def strip_whitespace
      self.contributor_name = self.contributor_name.strip unless self.contributor_name.nil?
      self.award_number =  self.award_number.strip unless self.award_number.nil?
    end
  end
end

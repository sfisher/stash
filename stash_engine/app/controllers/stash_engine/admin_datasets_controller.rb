require_dependency 'stash_engine/application_controller'

module StashEngine
  # rubocop:disable Metrics/ClassLength
  class AdminDatasetsController < ApplicationController

    include SharedSecurityController
    include StashEngine::Concerns::Sortable

    before_action :require_admin
    before_action :setup_paging, only: [:index]
    before_action :setup_ds_sorting, only: [:index]

    TENANT_IDS = Tenant.all.map(&:tenant_id)

    # the admin datasets main page showing users and stats, but slightly different in scope for superusers vs tenant admins
    def index
      my_tenant_id = (current_user.role == 'admin' ? current_user.tenant_id : nil)
      @all_stats = Stats.new
      @seven_day_stats = Stats.new(tenant_id: my_tenant_id, since: (Time.new - 7.days))

      @resources = build_table_query
      respond_to do |format|
        format.html
        format.csv
      end
    end

    # Unobtrusive Javascript (UJS) to do AJAX by running javascript
    def data_popup
      respond_to do |format|
        @identifier = Identifier.find(params[:id])
        @internal_datum = if params[:internal_datum_id]
                            InternalDatum.find(params[:internal_datum_id])
                          else
                            InternalDatum.new(identifier_id: @identifier.id)
                          end
        setup_internal_data_list
        format.js
      end
    end

    # Unobtrusive Javascript (UJS) to do AJAX by running javascript
    def note_popup
      respond_to do |format|
        resource = Resource.includes(:identifier, :current_curation_activity).find(params[:id])
        @curation_activity = CurationActivity.new(
          resource_id: resource.id,
          status: resource.current_curation_activity.status
        )
        format.js
      end
    end

    # Unobtrusive Javascript (UJS) to do AJAX by running javascript
    def curation_activity_popup
      respond_to do |format|
        @resource = Resource.includes(:identifier, :current_curation_activity).find(params[:id])
        @curation_activity = StashEngine::CurationActivity.new(resource_id: @resource.id)
        format.js
      end
    end

    def curation_activity_change
      respond_to do |format|
        format.js do
          @resource = Resource.find(params[:id])
          decipher_curation_activity
          @resource.update(publication_date: @pub_date)
          CurationActivity.create(resource_id: @resource.id, user_id: current_user.id,
                                  status: @status, note: params[:resource][:curation_activity][:note])
          @resource.reload
        end
      end
    end

    # show curation activities for this item
    def activity_log
      @identifier = Identifier.find(params[:id])
      created_at = SortableTable::SortColumnDefinition.new('created_at')
      sort_table = SortableTable::SortTable.new([created_at])
      @sort_column = sort_table.sort_column(params[:sort], params[:direction])
      resource_ids = @identifier.resources.collect(&:id)
      @curation_activities = CurationActivity.where(resource_id: resource_ids).order(@sort_column.order, id: :asc)
      @internal_data = InternalDatum.where(identifier_id: @identifier.id)
    end

    private

    def setup_paging
      if request.format.csv?
        @page = 1
        @page_size = 2_000
        return
      end
      @page = params[:page] || '1'
      @page_size = (params[:page_size].blank? || params[:page_size] != '1000000' ? '10' : '1000000')
    end

    # rubocop:disable Metrics/MethodLength
    def setup_ds_sorting
      sort_table = SortableTable::SortTable.new(
        [sort_column_definition('title', 'stash_engine_resources', %w[title]),
         sort_column_definition('status', 'stash_engine_curation_activities', %w[status]),
         sort_column_definition('author', 'stash_engine_authors', %w[author_last_name author_first_name]),
         sort_column_definition('doi', 'stash_engine_identifiers', %w[identifier]),
         sort_column_definition('last_modified', 'stash_engine_curation_activities', %w[updated_at]),
         sort_column_definition('modified_by', 'stash_engine_users', %w[last_name first_name]),
         sort_column_definition('size', 'stash_engine_identifiers', %w[storage_size]),
         sort_column_definition('publication_date', 'stash_engine_resources', %w[publication_date])]
      )
      @sort_column = sort_table.sort_column(params[:sort], params[:direction])
    end
    # rubocop:enable Metrics/MethodLength

    def build_table_query
      # Retrieve the ids of the all the latest Resources
      resource_ids = Resource.latest_per_dataset.pluck(:id)

      resources = Resource.joins(:identifier, :authors, :current_resource_state, :current_curation_activity)
        .includes(:identifier, :authors, :current_resource_state, current_curation_activity: :user)
        .where(stash_engine_resources: { id: resource_ids })

      # If the user is not a super_admin restrict their access to their tenant
      resources = resources.where(stash_engine_resources: { tenant_id: current_user.tenant_id }) unless current_user.role == 'superuser'

      # Add any filters, sorots, searches and pagination
      resources = add_searches(query_obj: resources)
      resources = add_filters(query_obj: resources)
      resources.order(@sort_column.order).page(@page).per(@page_size)
    end

    def add_searches(query_obj:)
      # We'll have to play with this search to get it to be reasonable with the insane interface so that it narrows to a small enough
      # set so that it is useful to people for finding something and a large enough set to have what they want without hunting too long.
      # It doesn't really support sorting by relevance because of the other sorts.
      query_obj = query_obj.where('MATCH(stash_engine_identifiers.search_words) AGAINST(?) > 0.5', params[:q]) unless params[:q].blank?
      query_obj
    end

    def add_filters(query_obj:)
      if TENANT_IDS.include?(params[:tenant]) && current_user.role == 'superuser'
        query_obj = query_obj.where(stash_engine_resources: { tenant_id: params[:tenant] })
      end
      if CurationActivity.statuses.include?(params[:curation_status])
        query_obj = query_obj.where(stash_engine_curation_activities: { status: params[:curation_status] })
      end
      query_obj
    end

    # this sets up the select list for internal data and will not offer options for items that are only allowed once and one is present
    def setup_internal_data_list
      @options = StashEngine::InternalDatum.validators_on(:data_type).first.options[:in].dup
      return if params[:internal_datum_id] # do not winnow list if doing update since it's read-only and just changes the value on update

      # Get options that are only allow one item rather than multiple
      only_one_options = @options.dup
      only_one_options.delete_if { |i| StashEngine::InternalDatum.allows_multiple(i) }

      StashEngine::InternalDatum.where(identifier_id: @internal_datum.identifier_id).where(data_type: only_one_options).each do |existing_item|
        @options.delete(existing_item.data_type)
      end
    end

    # rubocop:disable Metrics/MethodLength
    def decipher_curation_activity
      @status = params[:resource][:curation_activity][:status]
      @pub_date = params[:resource][:publication_date]
      # If the status was nil then we are just adding a note so get the prior status
      @status = @resource.current_curation_activity.status unless @status.present?
      case @status
      when 'published'
        publish
      when 'embargoed'
        embargo
      else
        # The user selected a different status so clear the publication date
        @pub_date = nil
      end
    end
    # rubocop:enable Metrics/MethodLength

    def publish
      # If the user selected published but the publication date is in the future
      # revert to embargoed status. The item will publish when the date is reached
      @status = 'embargoed' if @pub_date.present? && @pub_date > Date.today.to_s
      # If the user published but did not provide a publication date then default to today
      @pub_date = Date.today.to_s unless @pub_date.present?
    end

    def embargo
      # If the user also provided a publication date and the date is today then
      # revert to published status
      @status = 'published' if @pub_date.present? && @pub_date <= Date.today.to_s
    end

  end
  # rubocop:enable Metrics/ClassLength
end

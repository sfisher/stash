require_dependency 'stash_engine/application_controller'

module StashEngine
  class DashboardController < ApplicationController
    before_action :require_login

    def show
    end

    def get_started
    end

    def metadata_basics
    end

    def preparing_to_submit
    end

    def upload_basics
    end
  end
end

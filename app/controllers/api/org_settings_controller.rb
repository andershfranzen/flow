class Api::OrgSettingsController < Api::BaseController
  before_action :require_admin!, only: [ :update ]

  def show
    render json: OrgSetting.current.as_json(only: [ :site_name, :base_url, :notify_from ])
  end

  def update
    settings = OrgSetting.current
    settings.update!(params.permit(:site_name, :base_url, :notify_from))
    render json: settings.as_json(only: [ :site_name, :base_url, :notify_from ])
  end
end

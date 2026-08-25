# Reports-lite: enough numbers to run a support team, no BI suite.
class Api::ReportsController < Api::BaseController
  before_action :require_admin!

  def show
    render json: Reports.summary(agent: current_agent, days: params.fetch(:days, 30))
  end
end

class Api::ApiTokensController < Api::BaseController
  def index
    render json: current_agent.api_tokens.order(:id)
                 .as_json(only: [ :id, :name, :scope, :last_used_at, :created_at ])
  end

  def create
    token, raw = ApiToken.issue(agent: current_agent, name: params.require(:name),
                                scope: params[:scope].presence || "read")
    render json: token.as_json(only: [ :id, :name, :scope ]).merge(token: raw), status: :created
  end

  def destroy
    current_agent.api_tokens.find(params[:id]).destroy!
    head :no_content
  end
end

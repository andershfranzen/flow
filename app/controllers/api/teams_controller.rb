class Api::TeamsController < Api::BaseController
  before_action :require_admin!, except: [ :index ]

  def index
    render json: Team.order(:name).map { |t| team_json(t) }
  end

  def create
    team = Team.create!(params.permit(:name))
    set_members(team)
    render json: team_json(team), status: :created
  end

  def update
    team = Team.find(params[:id])
    team.update!(params.permit(:name))
    set_members(team)
    render json: team_json(team)
  end

  def destroy
    Team.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_members(team)
    return unless params[:agent_ids].is_a?(Array)
    ids = params[:agent_ids].map(&:to_i).reject(&:zero?)
    team.team_members.where.not(agent_id: ids).destroy_all
    ids.each { |id| team.team_members.find_or_create_by!(agent_id: id) }
  end

  def team_json(t)
    t.as_json(only: [ :id, :name ]).merge(agent_ids: t.agent_ids)
  end
end

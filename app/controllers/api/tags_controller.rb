class Api::TagsController < Api::BaseController
  before_action :require_admin!, only: [ :destroy ]

  def index
    render json: Tag.order(:name).as_json(only: [ :id, :name, :color ])
  end

  def create
    tag = Tag.find_or_create_by!(name: params.require(:name)) do |t|
      t.color = params[:color] if params[:color].present?
    end
    render json: tag.as_json(only: [ :id, :name, :color ]), status: :created
  end

  def update
    tag = Tag.find(params[:id])
    tag.update!(params.permit(:name, :color))
    render json: tag.as_json(only: [ :id, :name, :color ])
  end

  def destroy
    Tag.find(params[:id]).destroy!
    head :no_content
  end
end

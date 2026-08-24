class Api::WebhooksController < Api::BaseController
  before_action :require_admin!

  def index
    render json: Webhook.order(:id).as_json(only: [ :id, :url, :secret, :events, :enabled ])
  end

  def create
    webhook = Webhook.create!(params.permit(:url, :enabled, events: []))
    render json: webhook.as_json(only: [ :id, :url, :secret, :events, :enabled ]), status: :created
  end

  def update
    webhook = Webhook.find(params[:id])
    webhook.update!(params.permit(:url, :enabled, events: []))
    render json: webhook.as_json(only: [ :id, :url, :secret, :events, :enabled ])
  end

  def destroy
    Webhook.find(params[:id]).destroy!
    head :no_content
  end
end

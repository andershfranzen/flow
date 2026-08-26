class Api::WebhooksController < Api::BaseController
  before_action :require_admin!

  def index
    render json: Webhook.order(:id).map { |webhook| webhook_json(webhook) }
  end

  def create
    webhook = Webhook.create!(params.permit(:url, :enabled, events: []))
    render json: webhook_json(webhook, include_secret: true), status: :created
  end

  def update
    webhook = Webhook.find(params[:id])
    webhook.update!(params.permit(:url, :enabled, events: []))
    render json: webhook_json(webhook)
  end

  def destroy
    Webhook.find(params[:id]).destroy!
    head :no_content
  end

  private

  def webhook_json(webhook, include_secret: false)
    fields = [ :id, :url, :events, :enabled ]
    fields << :secret if include_secret
    webhook.as_json(only: fields)
  end
end

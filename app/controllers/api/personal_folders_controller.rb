# Personal folders: a private organizational layer, strictly per agent.
class Api::PersonalFoldersController < Api::BaseController
  def index
    folders = current_agent.personal_folders
                           .left_joins(:personal_folder_items)
                           .group(:id).order(:position, :id)
                           .select("personal_folders.*, COUNT(personal_folder_items.id) AS items_count")
    render json: folders.map { |f|
      { id: f.id, name: f.name, color: f.color, count: f.items_count }
    }
  end

  def create
    folder = current_agent.personal_folders.create!(params.permit(:name, :color))
    render json: { id: folder.id, name: folder.name, color: folder.color, count: 0 }, status: :created
  end

  def update
    folder = current_agent.personal_folders.find(params[:id])
    folder.update!(params.permit(:name, :color, :position))
    render json: { id: folder.id, name: folder.name, color: folder.color }
  end

  def destroy
    current_agent.personal_folders.find(params[:id]).destroy!
    head :no_content
  end

  # POST /api/personal_folders/:id/items { conversation_ids: [] }
  def add_items
    folder = current_agent.personal_folders.find(params[:id])
    added = 0
    Array(params.require(:conversation_ids)).each do |cid|
      conversation = Conversation.find_by(id: cid)
      next unless conversation && current_agent.can_access?(conversation.mailbox)
      folder.personal_folder_items.find_or_create_by!(conversation_id: conversation.id)
      added += 1
    end
    render json: { added: added, count: folder.personal_folder_items.count }
  end

  # DELETE /api/personal_folders/:id/items/:conversation_id
  def remove_item
    folder = current_agent.personal_folders.find(params[:id])
    folder.personal_folder_items.where(conversation_id: params[:conversation_id]).delete_all
    head :no_content
  end
end

class Api::WorkflowsController < Api::BaseController
  before_action :require_admin!

  def index
    render json: { workflows: Workflow.order(:position, :id).map { |w| workflow_json(w) },
                   meta: builder_meta }
  end

  def create
    workflow = Workflow.create!(workflow_params)
    render json: workflow_json(workflow), status: :created
  end

  def update
    workflow = Workflow.find(params[:id])
    workflow.update!(workflow_params)
    render json: workflow_json(workflow)
  end

  def destroy
    Workflow.find(params[:id]).destroy!
    head :no_content
  end

  # PATCH /api/workflows/reorder { ids: [...] } — priority order
  def reorder
    Array(params.require(:ids)).each_with_index do |id, index|
      Workflow.where(id: id).update_all(position: index + 1)
    end
    render json: { workflows: Workflow.order(:position, :id).map { |w| workflow_json(w) } }
  end

  private

  def workflow_params
    permitted = params.permit(:name, :enabled, :trigger, :mailbox_id, :match_type)
    permitted[:conditions] = step_list(params[:conditions], :field, :operator, :value) if params.key?(:conditions)
    permitted[:actions] = step_list(params[:actions], :type, :value) if params.key?(:actions)
    permitted
  end

  # Form encodings turn [] into [""]; JSON sends real hashes. Accept both.
  def step_list(raw, *keys)
    Array(raw).filter_map do |step|
      next unless step.respond_to?(:permit)
      step.permit(*keys).to_h
    end
  end

  def workflow_json(w)
    w.as_json(only: [ :id, :name, :enabled, :trigger, :mailbox_id, :match_type,
                      :conditions, :actions, :position, :runs_count, :last_run_at ])
  end

  def builder_meta
    { triggers: Workflow::TRIGGERS, fields: Workflow::CONDITION_FIELDS,
      operators: Workflow::OPERATORS, action_types: Workflow::ACTION_TYPES,
      statuses: Conversation::STATUSES }
  end
end

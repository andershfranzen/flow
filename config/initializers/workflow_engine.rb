# Workflow rules run off the domain-event bus (Settings → Workflows).
Rails.application.config.after_initialize do
  WorkflowEngine.install!
end

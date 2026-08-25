# Workflow rules run off the domain-event bus (Settings → Workflows).
Rails.application.config.after_initialize do
  Regexp.timeout ||= 1.0 # user-authored workflow regexes must never hang the pipeline
  WorkflowEngine.install!
end

require "open3"

# WordPress-style plugin management (admin only): list, toggle, install from
# a git URL, update, uninstall. Installing runs third-party code — the same
# trust model as any self-hosted plugin system; admins choose what they run.
class Api::PluginsController < Api::BaseController
  before_action :require_admin!

  def index
    render json: { plugins: PluginRegistry.discover.map { |p| plugin_json(p) },
                   restart_hint: "New or removed plugin code fully applies to background workers after a restart." }
  end

  def update
    name = params[:id]
    raise ActiveRecord::RecordNotFound unless PluginRegistry.valid_name?(name)
    PluginRegistry.set_enabled(name, ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    render json: { plugins: PluginRegistry.discover.map { |p| plugin_json(p) } }
  end

  # POST /api/plugins/install { git_url }
  def install
    url = params.require(:git_url).to_s.strip
    unless url.match?(%r{\Ahttps://[\w.-]+/\S+\z})
      return render json: { error: "invalid_url", details: [ "Only https:// git URLs are supported" ] },
                    status: :unprocessable_entity
    end
    name = File.basename(url, ".git")
    unless PluginRegistry.valid_name?(name)
      return render json: { error: "invalid_name" }, status: :unprocessable_entity
    end
    target = PluginRegistry.root.join(name)
    if File.exist?(target)
      return render json: { error: "already_installed" }, status: :unprocessable_entity
    end
    FileUtils.mkdir_p(PluginRegistry.root)
    output, status = Open3.capture2e("git", "clone", "--depth", "1", url, target.to_s)
    unless status.success?
      FileUtils.rm_rf(target)
      return render json: { error: "clone_failed", details: [ output.lines.last.to_s.strip ] },
                    status: :unprocessable_entity
    end
    unless File.exist?(target.join("plugin.rb"))
      FileUtils.rm_rf(target)
      return render json: { error: "not_a_plugin", details: [ "Repository has no plugin.rb" ] },
                    status: :unprocessable_entity
    end
    PluginRegistry.load_plugin(name)
    render json: { plugins: PluginRegistry.discover.map { |p| plugin_json(p) } }, status: :created
  end

  # POST /api/plugins/:id/upgrade — git pull
  def upgrade
    name = params[:id]
    dir = plugin_dir!(name)
    output, status = Open3.capture2e("git", "-C", dir.to_s, "pull", "--ff-only")
    render json: { ok: status.success?, output: output.lines.last.to_s.strip,
                   restart_needed: status.success? }
  end

  def destroy
    name = params[:id]
    dir = plugin_dir!(name)
    FileUtils.rm_rf(dir)
    PluginState.where(name: name).delete_all
    render json: { plugins: PluginRegistry.discover.map { |p| plugin_json(p) } }
  end

  private

  def plugin_dir!(name)
    raise ActiveRecord::RecordNotFound unless PluginRegistry.valid_name?(name)
    dir = PluginRegistry.root.join(name)
    raise ActiveRecord::RecordNotFound unless File.directory?(dir)
    dir
  end

  def plugin_json(p)
    { name: p.name, enabled: p.enabled, loaded: p.loaded, error: p.error,
      version: p.manifest["version"], description: p.manifest["description"],
      author: p.manifest["author"], url: p.manifest["url"],
      settings_path: p.manifest["settings_path"],
      manifest_error: p.manifest["error"],
      git: File.directory?(PluginRegistry.root.join(p.name, ".git")) }
  end
end

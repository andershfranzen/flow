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
    if params.key?(:enabled)
      PluginRegistry.set_enabled(name, ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    end
    save_plugin_settings(name) if params[:settings].present?
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

  # POST /api/plugins/install_zip — WordPress-style upload. The zip's single
  # top-level directory (or the zip's own name) becomes the plugin directory.
  # Re-uploading replaces a previous zip install; git installs use Update.
  MAX_ZIP_BYTES = 10.megabytes
  MAX_UNPACKED_BYTES = 30.megabytes
  MAX_ENTRIES = 500

  def install_zip
    file = params.require(:file)
    unless file.respond_to?(:read) && file.size <= MAX_ZIP_BYTES
      return render json: { error: "invalid_zip", details: [ "Upload a .zip up to 10 MB" ] },
                    status: :unprocessable_entity
    end
    Zip::File.open(file.tempfile.path) do |zip|
      name, strip_prefix = zip_plugin_name(zip, file.original_filename)
      unless PluginRegistry.valid_name?(name)
        return render json: { error: "invalid_name" }, status: :unprocessable_entity
      end
      target = PluginRegistry.root.join(name).to_s
      if File.directory?(File.join(target, ".git"))
        return render json: { error: "installed_from_git", details: [ "#{name} was installed from git — use Update or uninstall it first" ] },
                      status: :unprocessable_entity
      end
      unless zip.find_entry("#{strip_prefix}plugin.rb")
        return render json: { error: "not_a_plugin", details: [ "Zip has no plugin.rb" ] },
                      status: :unprocessable_entity
      end
      extract_zip!(zip, target, strip_prefix)
      PluginRegistry.load_plugin(name)
    end
    render json: { plugins: PluginRegistry.discover.map { |p| plugin_json(p) } }, status: :created
  rescue Zip::Error
    render json: { error: "invalid_zip", details: [ "File is not a valid zip archive" ] },
           status: :unprocessable_entity
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

  # Only keys the manifest declares are stored; blank password fields keep
  # their current value (same convention as the org OAuth secrets).
  def save_plugin_settings(name)
    spec = PluginRegistry.discover.find { |p| p.name == name }&.manifest&.dig("settings")
    return unless spec.is_a?(Array)
    state = PluginState.find_or_initialize_by(name: name)
    current = state.settings_hash
    incoming = params[:settings].to_unsafe_h
    spec.each do |field|
      key = field["key"].to_s
      value = incoming[key]
      next if value.nil?
      next if field["type"] == "password" && value.blank? # blank keeps stored secret
      current[key] = value.to_s
    end
    state.settings = current.to_json
    state.save!
  end

  # WordPress convention: a zip wrapping everything in one folder installs as
  # that folder; a flat zip installs under the zip's own (sanitized) name.
  def zip_plugin_name(zip, filename)
    raise Zip::Error, "empty archive" if zip.entries.empty? || zip.entries.size > MAX_ENTRIES
    tops = zip.entries.map { |e| e.name.split("/").first }.uniq
    if tops.size == 1 && zip.entries.all? { |e| e.name.include?("/") }
      [ tops.first, "#{tops.first}/" ]
    else
      [ File.basename(filename.to_s, ".zip"), "" ]
    end
  end

  def extract_zip!(zip, target, strip_prefix)
    unpacked = 0
    staging = "#{target}.staging-#{SecureRandom.hex(4)}"
    FileUtils.mkdir_p(staging)
    zip.each do |entry|
      relative = entry.name.delete_prefix(strip_prefix)
      next if relative.blank? || relative.end_with?("/")
      dest = File.expand_path(File.join(staging, relative))
      # zip-slip: every path must resolve inside the staging directory
      raise Zip::Error, "unsafe path #{entry.name}" unless dest.start_with?("#{File.expand_path(staging)}/")
      unpacked += entry.size
      raise Zip::Error, "archive too large" if unpacked > MAX_UNPACKED_BYTES
      FileUtils.mkdir_p(File.dirname(dest))
      File.binwrite(dest, entry.get_input_stream.read)
    end
    FileUtils.rm_rf(target)
    FileUtils.mv(staging, target)
  ensure
    FileUtils.rm_rf(staging) if staging && File.exist?(staging)
  end

  # Echo values back for the form — but never stored secrets, only a *_set flag.
  def masked_settings(p)
    spec = p.manifest["settings"]
    return nil unless spec.is_a?(Array)
    stored = PluginState.settings_for(p.name)
    spec.each_with_object({}) do |field, out|
      key = field["key"].to_s
      if field["type"] == "password"
        out["#{key}_set"] = stored[key].present?
      else
        out[key] = stored[key]
      end
    end
  end

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
      settings_spec: p.manifest["settings"],
      settings: masked_settings(p),
      manifest_error: p.manifest["error"],
      git: File.directory?(PluginRegistry.root.join(p.name, ".git")) }
  end
end

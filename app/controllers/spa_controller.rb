class SpaController < ActionController::Base
  def index
    send_file Rails.public_path.join("index.html"), type: "text/html", disposition: "inline"
  end
end

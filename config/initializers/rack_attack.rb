# frozen_string_literal: true

# Decidim throttles every request per IP (see throttling_* in
# config/initializers/decidim.rb). Each image or attachment costs one or two
# extra requests through /rails/active_storage (a signed redirect, plus the
# file itself when stored on disk), so a page with 20 images used about half
# of the default 100 requests per minute and visitors got "Retry later".
# Safelisted requests skip all throttles; logins, password resets and the
# /system blocklist are unaffected.
if Rails.env.production?
  require "rack/attack"

  ActiveSupport::Reloader.to_prepare do
    Rack::Attack.safelist("active storage files") do |request|
      request.path.start_with?("/rails/active_storage/")
    end
  end
end

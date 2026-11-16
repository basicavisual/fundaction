# -*- coding: utf-8 -*-
# frozen_string_literal: true

Decidim.configure do |config|
  config.application_name = "FundAction's Assembly"
  config.mailer_sender = %{FundAction's Assembly <assembly@fundaction.eu>}

  # Locales the platform supports. Keep this to the locales organizations
  # actually use: Decidim 0.26 rebuilds component settings on every access and
  # defines every translatable setting once per locale here, so the default
  # (all 47 locales) made the proposals index take ~60s to render.
  # Every organization's available_locales (set in /system) must be in this list.
  config.available_locales = ENV["DECIDIM_AVAILABLE_LOCALES"].presence.to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_sym).presence || [:en]
  config.default_locale = :en

  # Geocoder configuration
  # config.geocoder = {
  #   static_map_url: "https://image.maps.cit.api.here.com/mia/1.6/mapview",
  #   here_app_id: Rails.application.secrets.geocoder[:here_app_id],
  #   here_app_code: Rails.application.secrets.geocoder[:here_app_code]
  # }

  # Custom resource reference generator method
  # config.resource_reference_generator = lambda do |resource, feature|
  #   # Implement your custom method to generate resources references
  #   "1234-#{resource.id}"
  # end

  # Currency unit
  config.currency_unit = "€"

  # The number of reports which an object can receive before hiding it
  # config.max_reports_before_hiding = 3

  config.maximum_attachment_size = 10.megabytes
  config.maximum_avatar_size     = 10.megabytes

  config.enable_html_header_snippets = true

  config.unconfirmed_access_for = 2.days
  config.track_newsletter_links = true

  # Per-IP request throttling (production only): at most MAX requests every
  # PERIOD seconds, then "Retry later". File requests (/rails/active_storage)
  # are not counted, see config/initializers/rack_attack.rb.
  config.throttling_max_requests = ENV.fetch("DECIDIM_THROTTLING_MAX_REQUESTS", 100).to_i
  config.throttling_period = ENV.fetch("DECIDIM_THROTTLING_PERIOD", 60).to_i.seconds
end

Rails.application.config.i18n.available_locales = Decidim.available_locales
Rails.application.config.i18n.default_locale = Decidim.default_locale

Decidim::Verifications.register_workflow(:anybody_authorization_handler) do |workflow|
  workflow.form = "AnybodyAuthorizationHandler"
  workflow.action_authorizer = "AnybodyAuthorizationHandler::AnybodyActionAuthorizer"
  workflow.options do |options|
    options.attribute :allowed_emails, type: :string, required: false
  end
end

Decidim.view_hooks.register(:user_profile_bottom,
                            priority: Decidim::ViewHooks::HIGH_PRIORITY) do |view_context|
  user = view_context.send :profile_user
  # Since this is rendered inside a cell we need to access the parent context in order to render it.
  view_context = view_context.controller.view_context

  view_context.render(
    partial: "fund_action/hooks/user_profile_bottom",
    locals: { user: user }
  )
end

# Inform Decidim about the assets folder
Decidim.register_assets_path File.expand_path("app/packs", Rails.application.root)
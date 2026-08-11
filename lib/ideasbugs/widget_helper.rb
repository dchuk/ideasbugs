# frozen_string_literal: true

module Ideasbugs
  # Included into the host's ActionView. Drop `<%= ideasbugs_tag %>`
  # before </body> in your layout; it renders nothing unless feedback is
  # enabled for the request. This lives under lib and is required before the
  # engine registers its Action View load hook: a host initializer may load
  # Action View before Rails sets up application autoloaders, when an
  # app/helpers constant cannot be resolved yet.
  module WidgetHelper
    def ideasbugs_tag
      return unless Ideasbugs.enabled?(request)

      Widget.snippet(
        endpoint: Ideasbugs.config.feedbacks_endpoint,
        locale: I18n.locale,
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end
  end
end

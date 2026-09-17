# frozen_string_literal: true

module Ideasbugs
  module Seeds
    FEEDBACK = [
      {
        seed_id: 'checkout-error',
        kind: 'bug',
        section: '1. Try triage',
        message: 'Start here: this open bug shows what the widget captures — kind, page URL, ' \
                 'browser context, and an author when you configure one. Move it to Planned as your ' \
                 'first triage action.',
        status: 'under_review',
        page_url: '/checkout?demo=ideasbugs',
        author_label: 'Demo customer · open this first'
      },
      {
        seed_id: 'saved-filters',
        kind: 'feature',
        section: '2. Shape the inbox',
        message: 'This feature request is already Planned so you can compare workflow states. Set ' \
                 'config.current_user and a safe public author_label, adjust config.kinds, then use the board ' \
                 'filters and search to keep recurring themes visible.',
        status: 'planned',
        page_url: '/reports?demo=ideasbugs',
        author_label: 'Demo product manager · compare states'
      },
      {
        seed_id: 'export-confusing',
        kind: 'other',
        section: '3. Ship safely',
        message: 'This completed item is your launch checklist: render ideasbugs_tag, set authorize_admin ' \
                 'before production, and configure current_user plus a safe public author_label for ' \
                 'feedback. Screenshots remain behind the dashboard gate.',
        status: 'complete',
        page_url: '/settings?demo=ideasbugs',
        author_label: 'Demo admin · launch checklist'
      }
    ].freeze

    def self.load!(tenant: nil)
      FEEDBACK.map do |attributes|
        seed_id = attributes.fetch(:seed_id)
        feedback = Ideasbugs::Feedback.find_or_initialize_by(
          author_id: "ideasbugs-demo:#{seed_id}",
          tenant: tenant.presence
        )
        seed_attributes = attributes.except(:seed_id).merge(
          kind: kind_for(attributes.fetch(:kind)),
          tenant: tenant.presence,
          user_agent: 'ideasbugs demo seed'
        )
        feedback.assign_attributes(seed_attributes)
        feedback.save!
        feedback
      end
    end

    def self.kind_for(preferred)
      kinds = Ideasbugs.config.kinds.map(&:to_s)
      return preferred if kinds.include?(preferred)
      return kinds.first if kinds.any?

      preferred
    end
    private_class_method :kind_for
  end
end

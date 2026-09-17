# frozen_string_literal: true

module Ideasbugs
  # One piece of user feedback. Author attribution is optional and stored as
  # loose fields (no foreign key to the host's user table) so the model is
  # portable across apps with different user models.
  class Feedback < ApplicationRecord
    include PublicIdentifier

    # Hand-rolled instead of an AR enum: `open` would collide with Kernel#open
    # as a scope name, and three statuses don't need the machinery anyway.
    STATUSES = %w[under_review planned in_progress in_beta complete not_planned].freeze

    if defined?(::ActiveStorage)
      # Read at class load, after the host's initializer has run. nil falls
      # through to Active Storage's environment default service.
      has_many_attached :screenshots, service: Ideasbugs.config.storage_service
    end

    VISIBILITIES = %w[unlisted listed merged].freeze
    belongs_to :board
    belongs_to :merged_into, class_name: 'Ideasbugs::Feedback', optional: true
    has_many :merged_sources, class_name: 'Ideasbugs::Feedback', foreign_key: :merged_into_id,
                              dependent: :restrict_with_error, inverse_of: :merged_into
    has_many :votes, dependent: :destroy
    has_many :comments, dependent: :destroy
    after_create_commit :notify_submission
    after_update_commit :notify_status_change
    before_validation :assign_default_board, on: :create
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :votes_count, :comments_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :matching_board_tenant
    validate :valid_merge_reference

    def assign_default_board
      self.board ||= Board.default_for(tenant)
    end

    def matching_board_tenant
      errors.add(:board, 'must belong to the same tenant') if board && board.tenant != tenant.presence
    end

    validates :message, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :kind,
              presence: true,
              inclusion: { in: ->(_) { Ideasbugs.config.kinds.map(&:to_s) } }

    # Multi-tenancy: everything is scoped to an opaque tenant key (nil = the
    # single global board). Loose-coupled like author_id — a string, no FK
    # into the host's tables. See Ideasbugs.config.tenant.
    scope :for_tenant, ->(tenant) { where(tenant: tenant.presence) }

    scope :newest_first, -> { order(id: :desc) }

    STATUSES.each do |status|
      scope status, -> { where(status:) }
      define_method(:"#{status}?") { self.status == status }
    end

    def valid_merge_reference
      if visibility == 'merged' && merged_into.nil?
        errors.add(:merged_into, 'is required for merged feedback')
      elsif merged_into && (merged_into == self || merged_into.tenant != tenant || visibility != 'merged')
        errors.add(:merged_into, 'must be another request in this tenant and only set for merged feedback')
      end
    end

    def notify_submission
      Ideasbugs.config.on_submit.call(self)
    rescue StandardError => e
      Rails.logger.error("ideasbugs: on_submit hook raised #{e.class}: #{e.message}")
    end

    def notify_status_change
      return unless previous_changes.key?('status')

      Ideasbugs.config.on_status_change.call(self, previous_changes['status'].first)
    rescue StandardError => e
      Rails.logger.error("ideasbugs: on_status_change hook raised #{e.class}: #{e.message}")
    end

    def screenshots?
      respond_to?(:screenshots) && screenshots.attached?
    end
  end
end

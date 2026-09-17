# frozen_string_literal: true

require 'digest'

module Ideasbugs
  class Board < ApplicationRecord
    include PublicIdentifier

    VISIBILITIES = %w[private public].freeze
    has_many :feedbacks, dependent: :restrict_with_error
    validates :name, presence: true, length: { maximum: 100 }
    validates :visibility, inclusion: { in: VISIBILITIES }
    scope :for_tenant, ->(tenant) { where(tenant: tenant.presence) }
    before_destroy :protect_default

    def self.default_for(tenant)
      tenant = tenant.presence
      key = Digest::SHA256.hexdigest(tenant.nil? ? 'nil' : "tenant:#{tenant}")
      create_or_find_by!(default_key: key) { |board| board.assign_attributes(name: 'Feedback', tenant: tenant) }
    end

    private

    def protect_default
      return unless default_key.present?

      errors.add(:base, 'The default board cannot be deleted')
      throw :abort
    end
  end
end

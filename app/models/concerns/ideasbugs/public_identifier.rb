# frozen_string_literal: true

require 'securerandom'

module Ideasbugs
  module PublicIdentifier
    extend ActiveSupport::Concern

    included do
      before_validation :assign_public_id, on: :create
      validates :public_id, presence: true, uniqueness: true
    end

    def to_param
      Ideasbugs.config.use_public_ids ? public_id : super
    end

    private

    def assign_public_id
      self.public_id ||= SecureRandom.alphanumeric(12)
    end
  end
end

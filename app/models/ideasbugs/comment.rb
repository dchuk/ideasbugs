# frozen_string_literal: true

module Ideasbugs
  class Comment < ApplicationRecord
    belongs_to :feedback
    belongs_to :parent, class_name: 'Ideasbugs::Comment', optional: true
    has_many :replies, class_name: 'Ideasbugs::Comment', foreign_key: :parent_id, dependent: :destroy,
                       inverse_of: :parent
    validates :body, presence: true, length: { maximum: 10_000 }
    validates :author_id, :author_label, presence: true, length: { maximum: 255 }
    validate :one_level_reply
    after_create_commit :notify_host

    private

    def notify_host
      Ideasbugs.config.on_comment.call(self)
    rescue StandardError => e
      Rails.logger.error("ideasbugs: on_comment hook raised #{e.class}: #{e.message}")
    end

    def one_level_reply
      return unless parent

      return unless parent.feedback_id != feedback_id || parent.parent_id.present? || parent == self

      errors.add(:parent,
                 'must be a top-level comment on this feedback')
    end
  end
end

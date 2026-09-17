# frozen_string_literal: true

module Ideasbugs
  class Vote < ApplicationRecord
    belongs_to :feedback
    validates :voter_id, :voter_label, presence: true, length: { maximum: 255 }
    validates :voter_id, uniqueness: { scope: :feedback_id }
  end
end

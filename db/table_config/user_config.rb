# frozen_string_literal: true

require 'aws-record'

module ModelTableConfig
  def self.config
    Aws::Record::TableConfig.define do |t|
      t.model_class User

      t.read_capacity_units 10
      t.write_capacity_units 5
    end
  end
end

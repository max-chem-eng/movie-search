# frozen_string_literal: true

require 'aws-record'

module ModelTableConfig
  def self.config
    Aws::Record::TableConfig.define do |t|
      t.model_class Movie

      t.read_capacity_units 10
      t.write_capacity_units 5
      t.global_secondary_index(:tmdb_index) do |i|
        i.read_capacity_units 12
        i.write_capacity_units 14
      end
    end
  end
end

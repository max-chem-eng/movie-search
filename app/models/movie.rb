require "securerandom"
require "aws-record"

class Movie
  include Aws::Record

  set_table_name "movies"
  string_attr :uuid, hash_key: true
  string_attr :tmdb_id
  string_attr :title, default_value: ""
  string_attr :language, default_value: ""
  string_attr :popularity, default_value: "0"

  boolean_attr :adult, default_value: false
  boolean_attr :video, default_value: false

  global_secondary_index(
    :tmdb_index,
    hash_key: :tmdb_id,
    projection: {
      projection_type: "ALL"
    }
  )
end

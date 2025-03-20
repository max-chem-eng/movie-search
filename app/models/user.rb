require "securerandom"
require "aws-record"

class User
  include Aws::Record
  include ActiveModel::SecurePassword

  set_table_name "users"
  string_attr :uuid, hash_key: true, default: -> { SecureRandom.uuid }
  string_attr :username
  string_attr :email
  string_attr :password_digest
  has_secure_password
end

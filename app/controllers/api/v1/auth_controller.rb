module Api
  module V1
    class AuthController < ApplicationController
      def register
        user = User.new(email: params[:email], uuid: SecureRandom.uuid)
        user.password_digest = BCrypt::Password.create(params[:password])
        if user.save
          render json: { message: "User registered successfully." }, status: :created
        else
          render json: { error: "Registration failed" }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/login
      def login
        user_results = User.scan(
          filter_expression: "email = :email_value",
          expression_attribute_values: { ":email_value" => params[:email] }
        )
        user = user_results.first
        if user && BCrypt::Password.new(user.password_digest) == params[:password]
          token = JwtService.encode({ user_id: user.uuid, jti: SecureRandom.uuid }, 6.hours.from_now)
          render json: { token: token }, status: :ok
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      # POST /api/v1/auth/refresh
      def refresh
        token = JwtService.encode({ user_id: current_user.uuid, jti: SecureRandom.uuid }, 6.hours.from_now)
        render json: { token: token }, status: :ok
      end

      private

      def current_user
        header = request.headers["Authorization"]
        token = header.split(" ").last if header
        decoded = JwtService.decode(token)
        User.find(uuid: decoded[:user_id]) if decoded
      rescue
        nil
      end
    end
  end
end

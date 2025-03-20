module Api
  module V1
    class MoviesController < ApplicationController
      before_action :authenticate_user!, only: %i[ index show ]

      CACHE_EXPIRATION = 3600

      def index
        query = params[:query]
        return render json: { error: "query parameter is required" }, status: :bad_request if query.blank?

        locale = params[:locale]

        filters = {
          title_only: params[:title_only] == "true",
          year_after: params[:year_after],
          year_before: params[:year_before],
          language: params[:language],
          genre: params[:genre]
        }.compact

        sort_by    = params[:sort]  || "relevance"
        sort_order = params[:order] || "desc"
        page       = (params[:page] || 1).to_i
        per_page   = (params[:per_page] || 20).to_i

        # first try from cache
        results = fetch_from_cache(query, locale, filters, sort_by, sort_order, page, per_page)
        if results.present?
          return render json: results
        end

        # then, search via the movie search service
        results = search_movies(query, locale, filters, sort_by, sort_order, page, per_page)
        cache_results(query, locale, filters, sort_by, sort_order, page, per_page, results)
        render json: results
      end

      def show
        tmdb_id = params[:id]
        locale = params[:locale]

        movie_data = fetch_with_tmdb_id_from_cache("movie:#{tmdb_id}:#{locale}")

        if movie_data.blank?
          movie_data = TmdbService.get_movie_details(tmdb_id, locale)
          return render json: { error: "Movie not found" }, status: :not_found if movie_data.blank?
          cache_data("movie:#{tmdb_id}:#{locale}", movie_data)
          store_movie_if_new(movie_data)
        end

        render json: movie_data
      end

      private

      def authenticate_user!
        header = request.headers["Authorization"]
        return unauthorized_error unless header

        token = header.split(" ").last
        begin
          decoded = JwtService.decode(token)
          @current_user = User.find(uuid: decoded[:user_id])
          unauthorized_error unless @current_user
        rescue JWT::DecodeError, JWT::ExpiredSignature
          unauthorized_error
        end
      end

      def unauthorized_error
        render json: { error: "Unauthorized" }, status: :unauthorized and return
      end

      def fetch_with_tmdb_id_from_cache(tmdb_id)
        cached_data = redis_client.get(tmdb_id)
        JSON.parse(cached_data) if cached_data.present?
      rescue Redis::BaseError => e
        Rails.logger.error("Redis error: #{e.message}")
      end

      def cache_with_tmdb_id(tmdb_id, data)
        redis_client.setex(tmdb_id, CACHE_EXPIRATION, data.to_json)
      rescue Redis::BaseError => e
        Rails.logger.error("Redis caching error: #{e.message}")
      end

      def fetch_from_cache(query, locale, filters, sort_by, sort_order, page, per_page)
        cache_key = generate_cache_key(query, locale, filters, sort_by, sort_order, page, per_page)
        begin
          cached_results = redis_client.get(cache_key)
          return JSON.parse(cached_results) if cached_results.present?
        rescue Redis::BaseError => e
          Rails.logger.error("Redis error: #{e.message}")
        end
        nil
      end

      def generate_cache_key(query, locale, filters, sort_by, sort_order, page, per_page)
        filter_string = filters.to_a.sort.map { |k, v| "#{k}:#{v}" }.join("|")
        "movies_search:#{query}:#{locale}:#{filter_string}:#{sort_by}:#{sort_order}:page:#{page}:per_page:#{per_page}"
      end

      def search_movies(query, locale, filters, sort_by, sort_order, page, per_page)
        results = MovieSearchService.search(
          query,
          locale: locale,
          filters: filters,
          sort_by: sort_by,
          sort_order: sort_order,
          page: page,
          per_page: per_page
        )

        if results.empty?
          external_results = fetch_and_store_external_results(query, locale)
          filtered = filter_results(external_results, filters)
          sorted   = sort_results(filtered, sort_by, sort_order)
          paginated = paginate_array(sorted, page, per_page)
          {
            "results"       => paginated,
            "total_results" => sorted.size,
            "total_pages"   => (sorted.size.to_f / per_page).ceil,
            "page"          => page,
            "per_page"      => per_page
          }
        else
          results
        end
      end

      def fetch_and_store_external_results(query, locale)
        begin
          results = TmdbService.search(query, locale)
          results.each { |movie_data| store_movie_if_new(movie_data) }
          results
        rescue => e
          Rails.logger.error("TMDB API error: #{e.message}")
          []
        end
      end

      def paginate_array(array, page, per_page)
        start_index = (page - 1) * per_page
        array[start_index, per_page] || []
      end

      def filter_results(results, filters)
        filtered = results
        if filters[:title_only]
          filtered = filtered.select { |r| r["match_type"] == "title" }
        end
        if filters[:language]
          filtered = filtered.select { |r| r["original_language"] == filters[:language] }
        end
        if filters[:genre]
          filtered = filtered.select { |r| (r["genre_ids"] || []).include?(filters[:genre].to_i) }
        end
        filtered
      end

      def sort_results(results, sort_by, sort_order)
        case sort_by
        when "popularity"
          results.sort_by! { |r| r["popularity"] || 0 }
        when "title"
          results.sort_by! { |r| r["title"] || "" }
        else
          return results
        end
        results.reverse! if sort_order == "desc"
        results
      end

      def store_movie_if_new(movie_data)
        movie_results = Movie.scan(
          filter_expression: "tmdb_id = :tmdb_id_value",
          expression_attribute_values: { ":tmdb_id_value" => movie_data["id"].to_s }
        )
        unless movie_results.first.present?
          movie = Movie.new(
            tmdb_id: movie_data["id"],
            title: movie_data["title"],
            language: movie_data["original_language"]
          )
          if movie.save
            MovieSearchService.index(movie)
          end
        end
      end

      def cache_results(query, locale, filters, sort_by, sort_order, page, per_page, results)
        return if results["results"].empty?
        cache_key = generate_cache_key(query, locale, filters, sort_by, sort_order, page, per_page)
        begin
          redis_client.setex(cache_key, CACHE_EXPIRATION, results.to_json)
        rescue Redis::BaseError => e
          Rails.logger.error("Redis caching error: #{e.message}")
        end
      end

      def redis_client
        @redis_client ||= Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/0")
      end
    end
  end
end

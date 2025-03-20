require "net/http"
require "zlib"
require "stringio"
require "json"

class TmdbExportJob < ApplicationJob
  queue_as :default

  def perform
    date_str = Date.yesterday.strftime("%m_%d_%Y")
    url = "http://files.tmdb.org/p/exports/movie_ids_#{date_str}.json.gz"

    fetch_and_process(url)
  rescue => e
    Rails.logger.error("Error in TmdbExportJob: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end

  private

  def fetch_and_process(url)
    response = Net::HTTP.get_response(URI(url))

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("Failed to download TMDB export file: #{response.message}")
      return
    end

    process_count = 0
    Zlib::GzipReader.wrap(StringIO.new(response.body)) do |gz|
      gz.each_line.with_index do |line, index|
        process_movie_data(line)
        process_count += 1

        # Log progress periodically
        Rails.logger.info("Processed #{process_count} movies") if process_count % 1000 == 0
      end
    end

    Rails.logger.info("TmdbExportJob completed. Processed #{process_count} movies.")
  end

  def process_movie_data(line)
    movie_data = JSON.parse(line)

    # Check if movie already exists
    existing_movie = find_movie_by_tmdb_id(movie_data["id"])
    return if existing_movie.present?

    movie = Movie.new(
      uuid: SecureRandom.uuid,
      tmdb_id: movie_data["id"].to_s,
      title: movie_data["original_title"] || movie_data["title"] || "Untitled",
      language: movie_data["original_language"] || "",
      popularity: (movie_data["popularity"] || 0).to_s,
      adult: movie_data["adult"] || false,
      video: movie_data["video"] || false
    )

    if movie.save
      # Rails.logger.debug("Created movie: #{movie.title} (ID: #{movie.tmdb_id})")
      MovieSearchService.index(movie)
    else
      Rails.logger.error("Failed to save movie: #{movie_data['id']} - #{movie.title}")
    end
  rescue => e
    Rails.logger.error("Error processing movie data: #{e.message} | Data: #{line}")
  end

  def find_movie_by_tmdb_id(tmdb_id)
    response = elastic_client.search(
      index: MovieSearchService::INDEX_NAME,
      body: {
        query: {
          match: {
            tmdb_id: tmdb_id.to_s
          }
        }
      }
    )
    hits = response.dig("hits", "hits") || []
    hits.first["_source"] if hits.any?
  rescue => e
    Rails.logger.error("Error looking up movie by tmdb_id: #{e.message}")
    nil
  end

  def elastic_client
    @elastic_client ||= Elasticsearch::Client.new(
      url: ENV.fetch("ELASTICSEARCH_URL", "http://elasticsearch:9200"),
      log: Rails.env.development?
    )
  end
end

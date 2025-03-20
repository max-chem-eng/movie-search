require "uri"
require "net/http"

class TmdbService
  # now I'm leaving this empty, but this is where the TMDB API calls would be implemented
  # in order to search for movies in case the local db doesn't have any results
  # or to get the details of a movie once the user selects it
  def self.search(query, locale)
    []
  end

  # the get_movie_details is not working yet, I need an api key for it and set the authorization header
  # this is an example response from the TMDB API:
  # {
  #   "id": 550,
  #   "results": [
  #     {
  #       "iso_639_1": "en",
  #       "iso_3166_1": "US",
  #       "name": "Fight Club (1999) Trailer - Starring Brad Pitt, Edward Norton, Helena Bonham Carter",
  #       "key": "O-b2VfmmbyA",
  #       "site": "YouTube",
  #       "size": 720,
  #       "type": "Trailer",
  #       "official": false,
  #       "published_at": "2016-03-05T02:03:14.000Z",
  #       "id": "639d5326be6d88007f170f44"
  #     },
  #     {
  #       "iso_639_1": "en",
  #       "iso_3166_1": "US",
  #       "name": "#TBT Trailer",
  #       "key": "BdJKm16Co6M",
  #       "site": "YouTube",
  #       "size": 1080,
  #       "type": "Trailer",
  #       "official": true,
  #       "published_at": "2014-10-02T19:20:22.000Z",
  #       "id": "5c9294240e0a267cd516835f"
  #     }
  #   ]
  # }
  #
  def self.get_movie_details(tmdb_id, locale)
    return {} if tmdb_id.blank?

    # Ensure the TMDB API key is set
    return {} if ENV["TMDB_API_KEY"].blank?
    # raise "TMDB_API_KEY is not set" if ENV["TMDB_API_KEY"].blank?

    url = URI("https://api.themoviedb.org/3/movie/#{tmdb_id}/videos?language=en-US")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(url)
    request["accept"] = "application/json"
    request["Authorization"] = ENV["TMDB_API_KEY"]
    response = http.request(request)
    JSON.parse(response.read_body)
  rescue StandardError => e
    Rails.logger.error("Error fetching movie details from TMDB: #{e.message}")
    {}
  end
end

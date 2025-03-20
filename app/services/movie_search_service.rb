require "elasticsearch"

class MovieSearchService
  INDEX_NAME = "movies".freeze
  SORT_FIELD_MAPPING = {
    "popularity"   => "popularity",
    "title"        => "title.keyword"
  }.freeze

  def self.client
    @client ||= Elasticsearch::Client.new(
      url: ENV.fetch("ELASTICSEARCH_URL", "http://elasticsearch:9200"),
      log: Rails.env.development?
    )
  end

  # Options can include:
  #   :locale, :filters, :sort_by, :sort_order, :page, :per_page
  def self.search(query, options = {})
    locale     = options[:locale]
    filters    = options[:filters] || {}
    sort_by    = options[:sort_by] || "relevance"
    sort_order = options[:sort_order] || "desc"
    page       = options[:page].to_i > 0 ? options[:page].to_i : 1
    per_page   = options[:per_page].to_i > 0 ? options[:per_page].to_i : 10
    from       = (page - 1) * per_page

    begin
      search_definition = build_query(query, locale, filters, sort_by, sort_order, from, per_page)
      response = client.search(index: INDEX_NAME, body: search_definition)
      hits = response.dig("hits", "hits") || []
      formatted_hits = hits.map { |hit| format_hit(hit) }
      {
        "results" => formatted_hits,
        "total_results" => response.dig("hits", "total", "value") || 0,
        "total_pages" => ((response.dig("hits", "total", "value") || 0).to_f / per_page).ceil,
        "page" => page,
        "per_page" => per_page
      }
    rescue Elasticsearch => e
      Rails.logger.warn("Elasticsearch index '#{INDEX_NAME}' does not exist: #{e.message}")
      []
    rescue StandardError => e
      Rails.logger.error("Elasticsearch error in search: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      []
    end
  end

  def self.build_query(query, locale, filters, sort_by, sort_order, from, size)
    search_definition = {
      from: from,
      size: size,
      query: {
        bool: {
          must: [],
          filter: []
        }
      },
      highlight: {
        fields: {
          title: {}
        }
      }
    }

    if filters[:title_only]
      search_definition[:query][:bool][:must] << {
        match: {
          title: {
            query: query,
            boost: 3,
            fuzziness: "AUTO"
          }
        }
      }
    else
      search_definition[:query][:bool][:must] << {
        multi_match: {
          query: query,
          fields: [ "title^3" ],
          fuzziness: "AUTO"
        }
      }
    end

    search_definition[:query][:bool][:should] = [
      {
        match_phrase_prefix: {
          title: {
            query: query,
            boost: 10
          }
        }
      }
    ]

    if locale.present?
      language_code = locale.to_s.split("-").first.downcase
      search_definition[:query][:bool][:filter] << { term: { language: language_code } }
    end

    if filters[:language].present?
      search_definition[:query][:bool][:filter] << {
        term: { language: filters[:language] }
      }
    end

    unless sort_by == "relevance"
      sort_field = SORT_FIELD_MAPPING[sort_by] || SORT_FIELD_MAPPING["popularity"]
      sort_order = %w[asc desc].include?(sort_order.downcase) ? sort_order.downcase : "desc"
      search_definition[:sort] = [
        { sort_field => { order: sort_order } }
      ]
    end

    search_definition
  end

  def self.format_hit(hit)
    source = hit["_source"] || {}
    {
      "id"                => source["tmdb_id"],
      "uuid"              => source["uuid"],
      "title"             => source["title"],
      "original_language" => source["language"],
      "popularity"        => source["popularity"],
      "score"             => hit["_score"],
      "highlight"         => hit["highlight"]
    }
  end

  # Indexes a movie record into Elasticsearch.
  def self.index(movie)
    begin
      client.index(
        index: INDEX_NAME,
        id: movie.uuid,
        body: {
          uuid:         movie.uuid,
          tmdb_id:      movie.tmdb_id,
          title:        movie.title,
          language:     movie.language,
          popularity:   movie.respond_to?(:popularity) ? movie.popularity : nil,
          indexed_at:   Time.now.utc
        }
      )
      client.indices.refresh(index: INDEX_NAME)
      Rails.logger.info("Movie '#{movie.title}' indexed in Elasticsearch.")
      true
    rescue StandardError => e
      Rails.logger.error("Elasticsearch indexing error for movie '#{movie.title}': #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end

  def self.create_index
    client.indices.create(
      index: INDEX_NAME,
      body: {
        mappings: {
          properties: {
            uuid:         { type: "keyword" },
            tmdb_id:      { type: "keyword" },
            title: {
              type: "text",
              analyzer: "standard",
              fields: { keyword: { type: "keyword" } }
            },
            language:     { type: "keyword" },
            popularity:   { type: "float" },
            indexed_at:   { type: "date" }
          }
        }
      }
    )
    Rails.logger.info("Created Elasticsearch index '#{INDEX_NAME}'.")
    true
  rescue StandardError => e
    if e.message.include?("resource_already_exists_exception")
      Rails.logger.info("Elasticsearch index '#{INDEX_NAME}' already exists.")
      true
    else
      Rails.logger.error("Elasticsearch index creation error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end

  def self.reset_index
    begin
      if client.indices.exists?(index: INDEX_NAME)
        client.indices.delete(index: INDEX_NAME)
        Rails.logger.info("Deleted Elasticsearch index '#{INDEX_NAME}'.")
      end
      create_index
    rescue StandardError => e
      Rails.logger.error("Elasticsearch index reset error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end

  # Synchronizes all movies from DynamoDB to Elasticsearch.
  def self.sync_from_dynamodb
    begin
      create_index
      all_movies = Movie.scan.to_a
      Rails.logger.info("Found #{all_movies.count} movies in DynamoDB to index.")
      count = 0

      all_movies.each do |movie|
        begin
          if index(movie)
            count += 1
            Rails.logger.info("Indexed movie: #{movie.title}") if count % 10 == 0
          else
            Rails.logger.warn("Failed to index movie: #{movie.title}")
          end
        rescue StandardError => e
          Rails.logger.error("Error indexing movie '#{movie.title}': #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      end

      client.indices.refresh(index: INDEX_NAME)
      Rails.logger.info("Synchronized #{count} out of #{all_movies.count} movies from DynamoDB to Elasticsearch.")
      count
    rescue StandardError => e
      Rails.logger.error("Failed to sync movies from DynamoDB: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      0
    end
  end
end

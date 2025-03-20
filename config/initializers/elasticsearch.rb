# this is creating the index for the movies in case it does not exist
Rails.application.config.after_initialize do
  MovieSearchService.create_index unless MovieSearchService.client.indices.exists?(index: "movies")
end

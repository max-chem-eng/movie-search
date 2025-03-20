# Movie Search API

A scalable API for searching movie data across multiple online channels. This service allows users to find movies and view their trailers through a RESTful API, with optimized search capabilities, caching, and international support.

## Key Features
- Fast and relevant movie search with advanced filtering
- Multi-language support
- Scalable architecture designed for global deployment
- Comprehensive caching for optimal performance


## Usage
Clone this repository to your local machine using the following command:

```bash
git clone <this repository>
```
Then, navigate to the cloned directory:

```bash
cd <this repository>
```
Open it in VSC and accept the prompt to reopen in container.
This will open the repository in a Docker container with all the necessary dependencies installed.

### Run the app
To run the app, use the following command:

```bash
rails s
```
This will start the Rails server, and you can access the app at `http://localhost:3000`.
For registration, use this link: `http://localhost:3000/api/v1/auth/register`.
For login, use this link: `http://localhost:3000/api/v1/auth/login`.
For refreshing the token, use this link: `http://localhost:3000/api/v1/auth/refresh`.

In order to seed the database with movies, use the following command:

```ruby
MovieSearchService.reset_index
TmdbExportJob.perform_now
MovieSearchService.sync_from_dynamodb
```

Then for searching for movies, use the endpoint `http://localhost:3000/api/v1/movies/search?query=forrest&per_page=10`.

## Dev Notes:

### API Design
The api is thought to work under this pattern:
- User searches for a movie
- The API checks if the search query is in the cache
- If so, it returns the cached result
- If not, it searches using elasticsearch
- If the result is not found in elasticsearch, it queries the external API (TMDB) and stores the result in the cache and in the database
- The API returns the result to the user
- The user then selects a movie from the results list and the API returns the movie details, which are also cached. These details include the needed data to show the trailer.

### Design decisions
- I chose Dynamodb as the database for storing movies data because of its great scalability and performance
- I chose Elasticsearch for its powerful search capabilities and ability to handle large volumes of data. DynamoDB is not a good fit for search queries, and Elasticsearch is a great complement to it.
- Redis was chosen for caching to improve performance and reduce the load on the database
- I'm using JWT authentication because of its stateless nature and ability to work well with APIs, along with BCrypt for password hashing
- Background jobs for getting data from third parties that could run on low traffic times

### Documentation
- My first choice for documentation would be swagger. For this POC, I have just used postman and generated tests and documentation from it.
- An export file form postman can be found in `postman.json` in the root of the project.
#### Endpoints
- `POST /api/v1/auth/register` - Register a new user
- `POST /api/v1/auth/login` - Login a user
- `POST /api/v1/auth/refresh` - Refresh the JWT token
- `GET /api/v1/movies/search` - Search for movies
- `GET /api/v1/movies/:id` - Get movie details

### What was done
For this POC, I have implemented the following features:
- Working API on a dev DOCKER container with a local dynamodb and elasticsearch instance
- User registration and login with JWT authentication with expiration.
- Secure password hashing with BCrypt
- Caching using redis
- Movie search with pagination.
- Job to export movies from TMDB to my DynamoDB which includes indexing the movies in Elasticsearch
- basic security with rack attack

### TODOS:
#### High Priority
- Add comprehensive test suite
- Complete localization support
- Implement websocket responses for slow searches

#### Medium Priority
- Evaluate data storage strategy (DynamoDB + ES vs Elasticsearch only)
- Implement background job for TMDB data synchronization
- Add monitoring and alerting

#### Low Priority
- Add admin interface for system monitoring
- Implement more sophisticated caching strategies
- Add user preferences and recommendations


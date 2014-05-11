require 'sinatra/base'
require 'sinatra/reloader'

require 'curb'
require 'net/http'
require 'nokogiri'
require 'builder'
require 'json'
require './my_anime_list'


class App < Sinatra::Base

  API_VERSION = '1.0'

  configure do
    enable :sessions, :static, :methodoverride
    disable :raise_errors

    set :public_folder, Proc.new { File.join(File.dirname(__FILE__), 'public') }

    # JSON CSRF protection interferes with CORS requests. Seeing as we're only acting
    # as a proxy and not dealing with sensitive information, we'll disable this to
    # prevent all manner of headaches.
    set :protection, :except => :json_csrf
  end

  configure :development do
    register Sinatra::Reloader
  end

  # CORS support: this let's us make cross domain ajax requests to
  # this app without having to resort to jsonp.
  #
  # For more details, see the project's readme: https://github.com/cyu/rack-cors
  use Rack::Cors do
    # Blanket whitelist all cross-domain xhr requests
    allow do
      origins '*'
      resource '*', :headers => :any, :methods => [:get, :post, :put, :delete]
    end
  end

  JSON_RESPONSE_MIME_TYPE = 'application/json'
  mime_type :json, JSON_RESPONSE_MIME_TYPE

  # Error handlers.

  error MyAnimeList::NetworkError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>network-error</code><details>#{details}</details></error>"
    else
      body = { :error => 'network-error', :details => details }.to_json
      params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
    end
  end

  error MyAnimeList::UpdateError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>anime-update-error</code><details>#{details}</details></error>"
    else
      body = { :error => 'anime-update-error', :details => details }.to_json
      params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
    end
  end

  error MyAnimeList::NotFoundError do
    status 404
    case params[:format]
    when 'xml'
      "<error><code>not-found</code><details>#{request.env['sinatra.error'].message}</details></error>"
    else
      body = { :error => 'not-found', :details => request.env['sinatra.error'].message }.to_json
      params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
    end
  end

  error MyAnimeList::UnknownError do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>unknown-error</code><details>#{details}</details></error>"
    else
      body = { :error => 'unknown-error', :details => details }.to_json
      params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
    end
  end

  error do
    details = "Exception message: #{request.env['sinatra.error'].message}"
    case params[:format]
    when 'xml'
      "<error><code>unknown-error</code><details>#{details}</details></error>"
    else
      body = { :error => 'unknown-error', :details => details }.to_json
      params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
    end
  end


  helpers do
    include MyAnimeList::Rack::Auth
  end

  before do

    # Check and make sure the version is set to API_VERSION.
      raise MyAnimeList::NotFoundError.new('Malformed URL.', nil) unless Pathname(request.env['REQUEST_URI']).to_s.match(API_VERSION)

    case params[:format]
    when 'xml'
      content_type(:xml)
    else
      content_type(:json)
    end
  end


  # GET /#{API_VERSION}/anime/#{anime_id}
  # Get an anime's details.
  # Optional parameters:
  #  * mine=1 - If specified, include the authenticated user's anime details (e.g. user's score, watched status, watched
  #             episodes). Requires authentication.
  get '/:v/anime/:id' do
    pass unless params[:id] =~ /^\d+$/

    options = nil

    if params.include? 'options'
      options = params[:options].split(',')
    end

    if params[:mine] == '1'
      authenticate unless session['cookie_string']
      anime = MyAnimeList::Anime.scrape_anime(params[:id], options, session['cookie_string'])
    else
      anime = MyAnimeList::Anime.scrape_anime(params[:id], options)

      # Caching.
      expires 3600, :public, :must_revalidate
      last_modified Time.now
      etag "anime/#{anime.id}"
    end

    case params[:format]
    when 'xml'
      anime.to_xml
    else
      params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json})"
    end
  end


  # POST /#{API_VERSION}/animelist/anime
  # Adds an anime to a user's anime list.
  post '/:v/animelist/anime' do
    authenticate unless session['cookie_string']

    # Ensure "anime_id" param is given.
    if params[:anime_id] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>anime_id-required</code></error>'
      else
        body = { :error => 'anime_id-required' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end

    successful = MyAnimeList::Anime.add(params[:anime_id], session['cookie_string'], {
      :status => params[:status],
      :episodes => params[:episodes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # PUT /#{API_VERSION}/animelist/anime/#{anime_id}
  # Updates an anime already on a user's anime list.
  put '/:v/animelist/anime/:anime_id' do
    authenticate unless session['cookie_string']

    successful = MyAnimeList::Anime.update(params[:anime_id], session['cookie_string'], {
      :status => params[:status],
      :episodes => params[:episodes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # DELETE /#{API_VERSION}/animelist/anime/#{anime_id}
  # Delete an anime from user's anime list.
  delete '/:v/animelist/anime/:anime_id' do
    authenticate unless session['cookie_string']

    anime = MyAnimeList::Anime.delete(params[:anime_id], session['cookie_string'])

    if anime
      # Return HTTP 200 OK and the original anime if successful.
      case params[:format]
      when 'xml'
        anime.to_xml
      else
        params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json})"
      end
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # GET /#{API_VERSION}/animelist/#{username}
  # Get a user's anime list.
  get '/:v/animelist/:username' do
    response['Cache-Control'] = 'private,max-age=0,must-revalidate,no-store'

    anime_list = MyAnimeList::AnimeList.anime_list_of(params[:username])

    case params[:format]
    when 'xml'
      anime_list.to_xml
    else
      params[:callback].nil? ? anime_list.to_json : "#{params[:callback]}(#{anime_list.to_json})"
    end
  end

  # GET /#{API_VERSION}/anime/search
  # Search for anime.
  get '/:v/anime/search' do
    # Ensure "q" param is given.
    if params[:q] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>q-required</code></error>'
      else
        body = { :error => 'q-required' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end

    results = MyAnimeList::Anime.search(params[:q])

    # Caching.
    expires 3600, :public, :must_revalidate
    last_modified Time.now
    etag "anime/search/#{params[:q]}"

    case params[:format]
    when 'xml'
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!

      xml.results do |xml|
        xml.query params[:q]
        xml.count results.size

        results.each do |a|
          xml << a.to_xml(:skip_instruct => true)
        end
      end

      xml.target!
    else
      params[:callback].nil? ? results.to_json : "#{params[:callback]}(#{results.to_json})"
    end
  end


  # GET /#{API_VERSION}/anime/top
  # Get the top anime.
  get '/:v/anime/top' do
    anime = MyAnimeList::Anime.top(
      :type     => params[:type],
      :page     => params[:page],
      :per_page => params[:per_page]
    )

    case params[:format]
    when 'xml'
      anime.to_xml
    else
      params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json})"
    end
  end

  # GET /#{API_VERSION}/anime/popular
  # Get the popular anime.
  get '/:v/anime/popular' do
    anime = MyAnimeList::Anime.top(
      :type => 'bypopularity',
      :page => params[:page],
      :per_page => params[:per_page]
    )

    case params[:format]
      when 'xml'
        anime.to_xml
      else
        params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json})"
    end
  end

  # GET /#{API_VERSION}/anime/upcoming
  # Get the upcoming anime
  get '/:v/anime/upcoming' do
    anime = MyAnimeList::Anime.upcoming(
      :page => params[:page],
      :per_page => params[:per_page],
      :start_date => params[:start_date]
    )

    case params[:format]
      when 'xml'
        anime.to_xml
      else
        params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json}"
    end
  end

  # GET /#{API_VERSION}/anime/just_added
  # Get just added anime
  get '/:v/anime/just_added' do
    anime = MyAnimeList::Anime.just_added(
        :page => params[:page],
        :per_page => params[:per_page]
    )

    case params[:format]
      when 'xml'
        anime.to_xml
      else
        params[:callback].nil? ? anime.to_json : "#{params[:callback]}(#{anime.to_json}"
    end
  end

  # GET /#{API_VERSION}/history/#{username}
  # Get user's history.
  get '/:v/history/:username/?:type?' do
    user = MyAnimeList::User.new
    user.username = params[:username]

    options = Hash.new.tap do |options|
      options[:type] = params[:type].to_sym unless params[:type].nil?
    end

    history = user.history(options)

    case params[:format]
    when 'xml'
      history.to_xml
    else
      params[:callback].nil? ? history.to_json : "#{params[:callback]}(#{history.to_json})"
    end
  end

  # GET /#{API_VERSION}/profile/#{username}
  # Get user's profile information.
  get '/:v/profile/:username' do
    user = MyAnimeList::User.new
    user.username = params[:username]

    profile = user.profile

    case params[:format]
    when 'xml'
      profile.to_xml
    else
      params[:callback].nil? ? profile.to_json : "#{params[:callback]}(#{profile.to_json})"
    end
  end

  # GET #{API_VERSION}/manga/#{manga_id}
  # Get a manga's details.
  # Optional parameters:
  #  * mine=1 - If specified, include the authenticated user's manga details (e.g. user's score, read status). Requires
  #             authentication.
  get '/:v/manga/:id' do
    pass unless params[:id] =~ /^\d+$/

    if params[:mine] == '1'
      authenticate unless session['cookie_string']
      manga = MyAnimeList::Manga.scrape_manga(params[:id], session['cookie_string'])
    else
      manga = MyAnimeList::Manga.scrape_manga(params[:id])

      # Caching.
      expires 3600, :public, :must_revalidate
      last_modified Time.now
      etag "manga/#{manga.id}"
    end

    case params[:format]
    when 'xml'
      manga.to_xml
    else
      params[:callback].nil? ? manga.to_json : "#{params[:callback]}(#{manga.to_json})"
    end
  end


  # POST /#{API_VERSION}/mangalist/manga
  # Adds a manga to a user's manga list.
  post '/:v/mangalist/manga' do
    authenticate unless session['cookie_string']

    # Ensure "manga_id" param is given.
    if params[:manga_id] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>manga_id-required</code></error>'
      else
        body = { :error => 'manga_id-required' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end

    successful = MyAnimeList::Manga.add(params[:manga_id], session['cookie_string'], {
      :status => params[:status],
      :chapters => params[:chapters],
      :volumes => params[:volumes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # PUT /#{API_VERSION}/mangalist/manga/#{manga_id}
  # Updates a manga already on a user's manga list.
  put '/:v/mangalist/manga/:manga_id' do
    authenticate unless session['cookie_string']

    successful = MyAnimeList::Manga.update(params[:manga_id], session['cookie_string'], {
      :status => params[:status],
      :chapters => params[:chapters],
      :volumes => params[:volumes],
      :score => params[:score]
    })

    if successful
      nil # Return HTTP 200 OK and empty response body if successful.
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # DELETE /#{API_VERSION}/mangalist/manga/#{manga_id}
  # Delete a manga from user's manga list.
  delete '/:v/mangalist/manga/:manga_id' do
    authenticate unless session['cookie_string']

    manga = MyAnimeList::Manga.delete(params[:manga_id], session['cookie_string'])

    if manga
      # Return HTTP 200 OK and the original manga if successful.
      case params[:format]
      when 'xml'
        manga.to_xml
      else
        params[:callback].nil? ? manga.to_json : "#{params[:callback]}(#{manga.to_json})"
      end
    else
      case params[:format]
      when 'xml'
        halt 400, '<error><code>unknown-error</code></error>'
      else
        body = { :error => 'unknown-error' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end
  end


  # GET /#{API_VERSION}/mangalist/#{username}
  # Get a user's manga list.
  get '/:v/mangalist/:username' do
    manga_list = MyAnimeList::MangaList.manga_list_of(params[:username])

    case params[:format]
    when 'xml'
      manga_list.to_xml
    else
      params[:callback].nil? ? manga_list.to_json : "#{params[:callback]}(#{manga_list.to_json})"
    end
  end


  # GET /#{API_VERSION}/manga/search
  # Search for manga.
  get '/:v/manga/search' do
    # Ensure "q" param is given.
    if params[:q] !~ /\S/
      case params[:format]
      when 'xml'
        halt 400, '<error><code>q-required</code></error>'
      else
        body = { :error => 'q-required' }.to_json
        halt 400, params[:callback].nil? ? body : "#{params[:callback]}(#{body})"
      end
    end

    results = MyAnimeList::Manga.search(params[:q])

    # Caching.
    expires 3600, :public, :must_revalidate
    last_modified Time.now
    etag "manga/search/#{params[:q]}"

    case params[:format]
    when 'xml'
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct!

      xml.results do |xml|
        xml.query params[:q]
        xml.count results.size

        results.each do |a|
          xml << a.to_xml(:skip_instruct => true)
        end
      end

      xml.target!
    else
      params[:callback].nil? ? results.to_json : "#{params[:callback]}(#{results.to_json})"
    end
  end

  # GET /#{API_VERSION}/actor/#{actor_id}
  # Get an actor's details.
  get '/:v/actor/:id' do
    pass unless params[:id] =~ /^\d+$/

    actor = MyAnimeList::Actor.scrape_actor(params[:id])

    # Caching.
    expires 3600, :public, :must_revalidate
    last_modified Time.now
    etag "actor/#{actor.id}"

    params[:callback].nil? ? actor.to_json : "#{params[:callback]}(#{actor.to_json})"

  end

  # GET /#{API_VERSION}/character/#{actor_id}
  # Get a character's details.
  get '/:v/character/:id' do
    pass unless params[:id] =~ /^\d+$/

    character = MyAnimeList::Character.scrape_character(params[:id])

    # Caching.
    expires 3600, :public, :must_revalidate
    last_modified Time.now
    etag "character/#{character.id}"

    params[:callback].nil? ? character.to_json : "#{params[:callback]}(#{character.to_json})"

  end

  # Verify that authentication credentials are valid.
  # Returns an HTTP 200 OK response if authentication was successful, or an HTTP 401 response.
  # FIXME This should be rate-limited to avoid brute-force attacks.
  get '/:v/account/verify_credentials' do
    # Authenticate with MyAnimeList if we don't have a cookie string.
    authenticate unless session['cookie_string']

    nil # Reponse body is empy.
  end
end

require 'curb'
require 'nokogiri'

require './1.0/my_anime_list/rack'
require './1.0/my_anime_list/user'
require './1.0/my_anime_list/anime'
require './1.0/my_anime_list/anime_list'
require './1.0/my_anime_list/manga'
require './1.0/my_anime_list/manga_list'
require './1.0/my_anime_list/actor'

module MyAnimeList

  # Raised when there're any network errors.
  class NetworkError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  # Raised when there's an error updating an anime/manga.
  class UpdateError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  class NotFoundError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

  # Raised when an error we didn't expect occurs.
  class UnknownError < StandardError
    attr_accessor :original_exception

    def initialize(message, original_exception = nil)
      @message = message
      @original_exception = original_exception
      super(message)
    end
    def to_s; @message; end
  end

end
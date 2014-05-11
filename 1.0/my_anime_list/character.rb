module MyAnimeList
  class Character
    attr_accessor :id, :name, :image_url, :favorited_count, :url
    attr_writer :anime, :manga, :actors, :info

    # Scrape character details page on MyAnimeList.net.
    def self.scrape_character(id)
      curl = Curl::Easy.new("http://myanimelist.net/character/#{id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']

      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping character with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      # Check for missing character.
      raise MyAnimeList::NotFoundError.new("Character with ID #{id} doesn't exist.", nil) if response =~ /Invalid ID provided/i

      character = parse_character_response(response)
      character.id = id.to_s

      character

    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping character with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def info
      @info ||= {}
    end

    def actors
      @actors ||= []
    end

    def anime
      @anime ||= []
    end

    def manga
      @manga ||= []
    end

    def attributes
      {
          :id => id,
          :name => name,
          :image_url => image_url,
          :info => info,
          :favorited_count => favorited_count,
          :url => url,
          :anime => anime,
          :manga => manga,
          :actors => actors
      }
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

    private

    def self.parse_character_response(response)

      doc = Nokogiri::HTML(response)

      character = Character.new

      # Name of this character.
      content = doc.xpath('//div[@id="contentWrapper"]')

      character.name = content.at('h1/text()').to_s

      # Image and anime/manga appearances.
      content = doc.xpath('//div[@id="content"]/table/tr/td[1]')

      character.image_url = content.at('div/img/@src').to_s

      # Move pointer to the inner area where this character's bio lies.
      content = doc.xpath('//div[@id="content"]/table/tr/td[1]')

      info = {}

      # Animeography.
      content.xpath('//div[text()="Animeography"]/following-sibling::table[1]/tr').each do |tr|

        puts tr
        anime = {}

        anime_image_url = tr.xpath('td[1]/div/a/img/@src').to_s

        # Remove any letters preceding the extension (usually s or m are appended to get a smaller resolution image.)
        directory = File.dirname(anime_image_url)
        filename = File.basename(anime_image_url, '.*')
        extension = File.extname(anime_image_url)

        # If the filename does not have all digits, then we know we have letters.
        if filename[/[0-9]+/] != filename and filename != 'questionmark_23' then
          anime_image_url = directory + '/' + filename[/[0-9]+/] + extension
        end

        anime_url = tr.xpath('td[2]/a/@href').to_s
        anime[:image_url] = anime_image_url
        anime[:url] = anime_url
        anime[:name] = tr.xpath('td[2]/a/text()').to_s
        anime[:id] = anime_url[%r{/anime/(\d+)/.*?}, 1].to_s

        character.anime << anime
      end

      # Mangaography.
      content.xpath('//div[text()="Mangaography"]/following-sibling::table[1]/tr').each do |tr|

        puts tr
        manga = {}

        manga_image_url = tr.xpath('td[1]/div/a/img/@src').to_s

        # Remove any letters preceding the extension (usually s or m are appended to get a smaller resolution image.)
        directory = File.dirname(manga_image_url)
        filename = File.basename(manga_image_url, '.*')
        extension = File.extname(manga_image_url)

        # If the filename does not have all digits, then we know we have letters.
        if filename[/[0-9]+/] != filename and filename != 'questionmark_23' then
          manga_image_url = directory + '/' + filename[/[0-9]+/] + extension
        end

        manga_url = tr.xpath('td[2]/a/@href').to_s
        manga[:image_url] = manga_image_url
        manga[:url] = manga_url
        manga[:name] = tr.xpath('td[2]/a/text()').to_s
        manga[:id] = manga_url[%r{/manga/(\d+)/.*?}, 1].to_s

        character.manga << manga
      end

     # if (node = content.at('//td[text()="Member Favorites:"]')) && node.next then
     #   character.favorited_count = node.next.text.strip
     # end

      # Biography.

      if (node = content.at('//div[@id="content"]/table/tr/td[2]/div[2]')) then

        info[:biography] = ''

        while (node = node.next) do
          line = node.text.to_s.strip

          break if (line == 'Voice Actors')

          if (node.to_s == '<br>' or node.to_s == '<br />') then
            info[:biography] << "\n"
          elsif !(line.length == 0) then
            info[:biography] << line
          end
        end

      end

      info[:biography] = info[:biography].chomp()

      character.info = info

      character

    end

  end
end
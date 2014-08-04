module MyAnimeList

  class Anime
    attr_accessor :id, :title, :rank, :popularity_rank, :image_url, :episodes, :classification,
                  :members_score, :members_count, :favorited_count, :synopsis, :start_date, :end_date
    attr_accessor :listed_anime_id, :parent_story
    attr_reader :type, :status
    attr_writer :genres, :tags, :other_titles, :manga_adaptations, :prequels, :sequels, :side_stories,
                :character_anime, :spin_offs, :summaries, :alternative_versions, :summary_stats, :score_stats, :additional_info_urls,
                :character_voice_actors

    # These attributes are specific to a user-anime pair, probably should go into another model.
    attr_accessor :watched_episodes, :score
    attr_reader :watched_status

    # Scrape anime details page on MyAnimeList.net. Very fragile!
    def self.scrape_anime(id, options, cookie_string = nil)

      scrape_anime_stats = false
      scrape_character_info = false

      if options != nil
        scrape_anime_stats = options.include? 'stats'
        scrape_character_info = options.include? 'characters_and_staff'
      end

      curl = Curl::Easy.new("http://myanimelist.net/anime/#{id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string if cookie_string
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      # Check for missing anime.
      raise MyAnimeList::NotFoundError.new("Anime with ID #{id} doesn't exist.", nil) if response =~ /No series found/i

      anime = parse_anime_response(response)

      # For testing:
      # response = File.open('/Users/corey.roberts/Projects/myanimelist-api/samples/anime_character_list.html', "rb").read
      # anime = parse_anime_characters(response, anime)

      # If stats are requested.
      if scrape_anime_stats == true
        # Now, scrape anime stats.
        # curl.url = "http://myanimelist.net/anime/#{id}/#{name}/stats"
        if anime.additional_info_urls[:stats]
          curl.url = anime.additional_info_urls[:stats]
          begin
            curl.perform
          rescue Exception => e
            raise MyAnimeList::NetworkError.new("Network error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
          end

          response = curl.body_str

          anime = parse_anime_stats(response, anime)
        end
      end

      # If character and staff details are requested.
      if scrape_character_info == true
        # If available, scrape anime characters.
        if anime.additional_info_urls[:characters_and_staff]

          # For testing:
          # response = File.open("/samples/anime_character_list.html", "rb").read

          curl.url = anime.additional_info_urls[:characters_and_staff]
          begin
            curl.perform
          rescue Exception => e
            raise MyAnimeList::NetworkError.new("Network error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
          end

          response = curl.body_str

          anime = parse_anime_characters(response, anime)
        end
      end

      anime

      rescue MyAnimeList::NotFoundError => e
        raise
      rescue Exception => e
        raise MyAnimeList::UnknownError.new("Error scraping anime with ID=#{id}. Original exception: #{e.message}.", e)
    end

    def self.add(id, cookie_string, options)
      # This is the same as self.update except that the "status" param is required and the URL is
      # http://myanimelist.net/includes/ajax.inc.php?t=61.

      # Default watched_status to 1/watching if not given.
      options[:status] = 1 if options[:status] !~ /\S/
      options[:new] = true

      update(id, cookie_string, options)
    end

    def self.update(id, cookie_string, options)

      # Convert status to the number values that MyAnimeList uses.
      # 1 = Watching, 2 = Completed, 3 = On-hold, 4 = Dropped, 6 = Plan to Watch
      status = case options[:status]
      when 'Watching', 'watching', 1
        1
      when 'Completed', 'completed', 2
        2
      when 'On-hold', 'on-hold', 3
        3
      when 'Dropped', 'dropped', 4
        4
      when 'Plan to Watch', 'plan to watch', 6
        6
      else
        1
      end

      # There're different URLs to POST to for adding and updating an anime.
      url = options[:new] ? 'http://myanimelist.net/includes/ajax.inc.php?t=61' : 'http://myanimelist.net/includes/ajax.inc.php?t=62'

      curl = Curl::Easy.new(url)
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string
      params = [
        Curl::PostField.content('aid', id),
        Curl::PostField.content('status', status)
      ]
      params << Curl::PostField.content('epsseen', options[:episodes]) if options[:episodes]
      params << Curl::PostField.content('score', options[:score]) if options[:score]

      begin
        curl.http_post(*params)
      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error updating anime with ID=#{id}. Original exception: #{e.message}", e)
      end

      if options[:new]
        # An add is successful for an HTTP 200 response containing "successful".
        # The MyAnimeList site is actually pretty bad and seems to respond with 200 OK for all requests.
        # It's also oblivious to IDs for non-existent anime and responds wrongly with a "successful" message.
        # It responds with an empty response body for bad adds or if you try to add an anime that's already on the
        # anime list.
        # Due to these limitations, we will return false if the response body doesn't match "successful" and assume that
        # anything else is a failure.
        return curl.response_code == 200 && curl.body_str =~ /successful/i
      else
        # Update is successful for an HTTP 200 response with this string.
        curl.response_code == 200 && curl.body_str =~ /successful/i
      end
    end

    def self.delete(id, cookie_string)
      anime = scrape_anime(id, nil, cookie_string)

      curl = Curl::Easy.new("http://myanimelist.net/panel.php?go=edit&id=#{anime.listed_anime_id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.cookies = cookie_string

      begin
        curl.http_post(
          Curl::PostField.content('series_id', anime.listed_anime_id),
          Curl::PostField.content('series_title', id),
          Curl::PostField.content('submitIt', '3')
        )
      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error deleting anime with ID=#{id}. Original exception: #{e.message}", e)
      end

      # Deletion is successful for an HTTP 200 response with this string.
      if curl.response_code == 200 && curl.body_str =~ /Entry Successfully Deleted/i
        anime # Return the original anime if successful.
      else
        false
      end
    end

    def self.search(query)
      perform_search "/anime.php?c[]=a&c[]=b&c[]=c&c[]=d&c[]=e&c[]=f&c[]=g&q=#{Curl::Easy.new.escape(query)}"
    end

    def self.upcoming(options = {})
      page = options[:page] || 1
      # TODO: Implement page size in options.  Can we even control the page size when calling into MAL?
      page_size = 20
      limit = (page.to_i - 1) * page_size.to_i
      start_date = Date.today
      start_date = Date.parse(options[:start_date]) unless options[:start_date].nil?
      perform_search "/anime.php?sm=#{start_date.month}&sd=#{start_date.day}&sy=#{start_date.year}&em=0&ed=0&ey=0&o=2&w=&c[]=a&c[]=d&c[]=a&c[]=b&c[]=c&c[]=d&c[]=e&c[]=f&c[]=g&cv=1&show=#{limit}"
    end

    def self.just_added(options = {})
      page = options[:page] || 1
      # TODO: Implement page size in options.  Can we even control the page size when calling into MAL?
      page_size = 20
      limit = (page.to_i - 1) * page_size.to_i
      perform_search "/anime.php?o=9&c[]=a&c[]=b&c[]=c&c[]=d&c[]=e&c[]=f&c[]=g&cv=2&w=1&show=#{limit}"
    end

    # Returns top Anime.
    # Options:
    #  * type - Type of anime to return. Possible values: tv, movie, ova, special, bypopularity. Defaults to nothing, which returns
    #           top anime of any type.
    #  * page - Page of top anime to return. Defaults to 1.
    #  * per_page - Number of anime to return per page. Defaults to 30.
    def self.top(options = {})

      page = options[:page] || 1
      limit = (page.to_i - 1) * 30
      type = options[:type].to_s.downcase

      curl = Curl::Easy.new("http://myanimelist.net/topanime.php?type=#{type}&limit=#{limit}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error getting top anime. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      doc = Nokogiri::HTML(response)

      results = []

      doc.search('div#content table tr').each do |results_row|
        anime_title_node = results_row.at('td a strong')
        next unless anime_title_node
        anime_url = anime_title_node.parent['href']
        next unless anime_url
        url_match = anime_url.match %r{/anime/(\d+)/?.*}

        anime = Anime.new

        anime.id = url_match[1].to_s
        anime.title = anime_title_node.text

        table_cell_nodes = results_row.search('td')
        content_cell = table_cell_nodes.at('div.spaceit_pad')

        members_cell = content_cell.at('span.lightLink')
        members = members_cell.text.strip.gsub!(/\D/, '').to_i
        members_cell.remove

        stats = content_cell.text.strip.split(',')
        type = stats[0]
        episodes = stats[1].gsub!(/\D/, '')
        episodes = if episodes.size > 0 then episodes.to_i else nil end
        members_score = stats[2].match(/\d+(\.\d+)?/).to_s.to_f

        anime.type = type
        anime.episodes = episodes
        anime.members_count = members
        anime.members_score = members_score

        if image_node = results_row.at('td a img')
          anime.image_url = image_node['src']
        end

        results << anime
      end

      results
    end

    def watched_status=(value)
      @watched_status = case value
      when /watching/i, '1', 1
        :watching
      when /completed/i, '2', 2
        :completed
      when /on-hold/i, /onhold/i, '3', 3
        :"on-hold"
      when /dropped/i, '4', 4
        :dropped
      when /plan to watch/i, /plantowatch/i, '6', 6
        :"plan to watch"
      else
        :watching
      end
    end

    def type=(value)
      @type = case value
      when /TV/i, '1', 1
        :TV
      when /OVA/i, '2', 2
        :OVA
      when /Movie/i, '3', 3
        :Movie
      when /Special/i, '4', 4
        :Special
      when /ONA/i, '5', 5
        :ONA
      when /Music/i, '6', 6
        :Music
      else
        :TV
      end
    end

    def status=(value)
      @status = case value
      when '2', 2, /finished airing/i
        :"finished airing"
      when '1', 1, /currently airing/i
        :"currently airing"
      when '3', 3, /not yet aired/i
        :"not yet aired"
      else
        :"finished airing"
      end
    end

    def other_titles
      @other_titles ||= {}
    end

    def summary_stats
      @summary_stats ||= {}
    end

    def score_stats
      @score_stats ||= {}
    end

    def genres
      @genres ||= []
    end

    def tags
      @tags ||= []
    end

    def manga_adaptations
      @manga_adaptations ||= []
    end

    def prequels
      @prequels ||= []
    end

    def sequels
      @sequels ||= []
    end

    def side_stories
      @side_stories ||= []
    end

    def character_anime
      @character_anime ||= []
    end

    def spin_offs
      @spin_offs ||= []
    end

    def summaries
      @summaries ||= []
    end

    def alternative_versions
      @alternative_versions ||= []
    end

    def additional_info_urls
      @additional_info_urls ||= {}
    end

    def character_voice_actors
      @character_voice_actors ||= []
    end

    def attributes
      {
        :id => id,
        :title => title,
        :other_titles => other_titles,
        :summary_stats => summary_stats,
        :score_stats => score_stats,
        :additional_info_urls => additional_info_urls,
        :synopsis => synopsis,
        :type => type,
        :rank => rank,
        :popularity_rank => popularity_rank,
        :image_url => image_url,
        :episodes => episodes,
        :status => status,
        :start_date => start_date,
        :end_date => end_date,
        :genres => genres,
        :tags => tags,
        :classification => classification,
        :members_score => members_score,
        :members_count => members_count,
        :favorited_count => favorited_count,
        :manga_adaptations => manga_adaptations,
        :prequels => prequels,
        :sequels => sequels,
        :side_stories => side_stories,
        :parent_story => parent_story,
        :character_anime => character_anime,
        :spin_offs => spin_offs,
        :summaries => summaries,
        :alternative_versions => alternative_versions,
        :listed_anime_id => listed_anime_id,
        :watched_episodes => watched_episodes,
        :score => score,
        :watched_status => watched_status,
        :character_voice_actors => character_voice_actors
      }
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

    def to_xml(options = {})
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! unless options[:skip_instruct]
      xml.anime do |xml|
        xml.id id
        xml.title title
        xml.synopsis synopsis
        xml.type type.to_s
        xml.rank rank
        xml.popularity_rank popularity_rank
        xml.image_url image_url
        xml.episodes episodes
        xml.status status.to_s
        xml.start_date start_date
        xml.end_date end_date
        xml.classification classification
        xml.members_score members_score
        xml.members_count members_count
        xml.favorited_count favorited_count
        xml.listed_anime_id listed_anime_id
        xml.watched_episodes watched_episodes
        xml.score score
        xml.watched_status watched_status.to_s

        other_titles[:synonyms].each do |title|
          xml.synonym title
        end if other_titles[:synonyms]
        other_titles[:english].each do |title|
          xml.english_title title
        end if other_titles[:english]
        other_titles[:japanese].each do |title|
          xml.japanese_title title
        end if other_titles[:japanese]

        genres.each do |genre|
          xml.genre genre
        end
        tags.each do |tag|
          xml.tag tag
        end

        manga_adaptations.each do |manga|
          xml.manga_adaptation do |xml|
            xml.manga_id  manga[:manga_id]
            xml.title     manga[:title]
            xml.url       manga[:url]
          end
        end

        prequels.each do |prequel|
          xml.prequel do |xml|
            xml.anime_id  prequel[:anime_id]
            xml.title     prequel[:title]
            xml.url       prequel[:url]
          end
        end

        sequels.each do |sequel|
          xml.sequel do |xml|
            xml.anime_id  sequel[:anime_id]
            xml.title     sequel[:title]
            xml.url       sequel[:url]
          end
        end

        side_stories.each do |side_story|
          xml.side_story do |xml|
            xml.anime_id  side_story[:anime_id]
            xml.title     side_story[:title]
            xml.url       side_story[:url]
          end
        end

        xml.parent_story do |xml|
          xml.anime_id  parent_story[:anime_id]
          xml.title     parent_story[:title]
          xml.url       parent_story[:url]
        end if parent_story

        character_anime.each do |o|
          xml.character_anime do |xml|
            xml.anime_id  o[:anime_id]
            xml.title     o[:title]
            xml.url       o[:url]
          end
        end

        spin_offs.each do |o|
          xml.spin_off do |xml|
            xml.anime_id  o[:anime_id]
            xml.title     o[:title]
            xml.url       o[:url]
          end
        end

        summaries.each do |o|
          xml.summary do |xml|
            xml.anime_id  o[:anime_id]
            xml.title     o[:title]
            xml.url       o[:url]
          end
        end

        alternative_versions.each do |o|
          xml.alternative_version do |xml|
            xml.anime_id  o[:anime_id]
            xml.title     o[:title]
            xml.url       o[:url]
          end
        end
      end

      xml.target!
    end

    private
      def self.perform_search(url)
        begin
          response = Net::HTTP.start('myanimelist.net', 80) do |http|
            http.get(url, {'User-Agent' => ENV['USER_AGENT']})
          end

          case response
            when Net::HTTPRedirection
              redirected = true

              # Strip everything after the anime ID - in cases where there is a non-ASCII character in the URL,
              # MyAnimeList.net will return a page that says "Access has been restricted for this account".
              redirect_url = response['location'].sub(%r{(http://myanimelist.net/anime/\d+)/?.*}, '\1')

              response = Net::HTTP.start('myanimelist.net', 80) do |http|
                http.get(redirect_url, {'User-Agent' => ENV['USER_AGENT']})
              end
          end

        rescue Exception => e
          raise MyAnimeList::UpdateError.new("Error searching anime with query '#{query}'. Original exception: #{e.message}", e)
        end

        results = []
        if redirected
          # If there's a single redirect, it means there's only 1 match and MAL is redirecting to the anime's details
          # page.
          anime = parse_anime_response(response.body)
          results << anime

        else
          # Otherwise, parse the table of search results.
          doc = Nokogiri::HTML(response.body)
          results_table = doc.xpath('//div[@id="content"]/div[2]/table')

          results_table.xpath('//tr').each do |results_row|

            anime_title_node = results_row.at('td a strong')
            next unless anime_title_node
            url = anime_title_node.parent['href']
            next unless url.match %r{http://myanimelist.net/anime/(\d+)/?.*}

            anime = Anime.new
            anime.id = $1.to_i
            anime.title = anime_title_node.text
            if image_node = results_row.at('td a img')
              anime.image_url = image_node['src']
            end

            table_cell_nodes = results_row.search('td')

            anime.episodes = table_cell_nodes[3].text.to_i
            anime.members_score = table_cell_nodes[4].text.to_f
            synopsis_node = results_row.at('div.spaceit')
            if synopsis_node
              synopsis_node.search('a').remove
              anime.synopsis = synopsis_node.text.strip
            end
            anime.type = table_cell_nodes[2].text
            anime.start_date = parse_start_date(table_cell_nodes[5].text)
            anime.end_date = parse_end_date(table_cell_nodes[6].text)
            anime.classification = table_cell_nodes[8].text if table_cell_nodes[8]

            results << anime
          end
        end

        results
      end

      def self.parse_anime_characters(response, anime)
        doc = Nokogiri::HTML(response)

        left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')
        # puts 'Number of tables: ' + doc.search('//div[@style="padding: 0 7px;"]/table').length.to_s

        doc.search('//div[@style="padding: 0 7px;"]/table').each do |table|

          td_nodes = table.xpath('tr/td')
          # puts td_nodes

          counter = 0

          character_details = {}
          voice_actor_details = []

          td_nodes.each { |td|
            # puts 'Node: ' + td.to_s + '\n'

            # Character URL and Image URL.
            if counter == 0
              character_url = td.at('a/@href').to_s
              image_url = td.at('img/@src').to_s
              image_url.slice!(image_url.length-5)

              id = character_url[%r{http://myanimelist.net/character/(\d+)/.*?}, 1].to_s

              # puts 'Character URL: ' + character_url
              # puts 'Image URL: ' + image_url

              character_details[:name] = ''
              character_details[:character_id] = id
              character_details[:url] = character_url
              character_details[:image_url] = image_url
            end

            # Name of Character
            if counter == 1
              character_name = td.at('a/text()').to_s

              # puts 'Character name: ' + character_name

              character_details[:name] = character_name
            end

            # Voice actors for this character (embedded in its own table)
            if counter == 2
              inner_table_tr_nodes = td.xpath('table/tr')
              inner_table_tr_nodes.each { |inner_tr|
                # puts 'inner_tr' + inner_tr.to_s
                # Actor's name and Language
                actor_name = inner_tr.at('td[1]/a/text()').to_s
                actor_name_url = inner_tr.at('td[1]/a/@href').to_s
                actor_language = inner_tr.at('td[1]/small/text()').to_s
                id = actor_name_url[%r{http://myanimelist.net/people/(\d+)/.*?}, 1].to_s

                # Actor's image URL
                actor_image_url = inner_tr.xpath('td[2]').at('div/a/img/@src').to_s
                actor_image_url.slice!(actor_image_url.length-5)

                if actor_name.length > 0
                  voice_actor_details <<  {
                                            :name       => actor_name,
                                            :actor_id   => id,
                                            :url        => actor_name_url,
                                            :language   => actor_language,
                                            :image_url  => actor_image_url
                                          }
                end
              }

              anime.character_voice_actors << { :character_details => character_details, :voice_actors => voice_actor_details }

            end

            counter += 1
          }

        end

        anime
      end

      def self.parse_anime_stats(response, anime)
        doc = Nokogiri::HTML(response)

        # Summary Stats.
        # Example:
        # <div class="spaceit_pad"><span class="dark_text">Watching:</span> 12,334</div>
        # <div class="spaceit_pad"><span class="dark_text">Completed:</span> 59,459</div>
        # <div class="spaceit_pad"><span class="dark_text">On-Hold:</span> 3,419</div>
        # <div class="spaceit_pad"><span class="dark_text">Dropped:</span> 2,907</div>
        # <div class="spaceit_pad"><span class="dark_text">Plan to Watch:</span> 17,571</div>
        # <div class="spaceit_pad"><span class="dark_text">Total:</span> 95,692</div>

        left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')

        if (node = left_column_nodeset.at('//span[text()="Watching:"]')) && node.next
          anime.summary_stats[:watching] = node.next.text.strip.gsub(',','').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Completed:"]')) && node.next
          anime.summary_stats[:completed] = node.next.text.strip.gsub(',','').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="On-Hold:"]')) && node.next
          anime.summary_stats[:on_hold] = node.next.text.strip.gsub(',','').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Dropped:"]')) && node.next
          anime.summary_stats[:dropped] = node.next.text.strip.gsub(',','').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Plan to Watch:"]')) && node.next
          anime.summary_stats[:plan_to_watch] = node.next.text.strip.gsub(',','').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Total:"]')) && node.next
          anime.summary_stats[:total] = node.next.text.strip.gsub(',','').to_i
        end

        parse_anime_score_stats(response, anime)

        anime
      end

    def self.parse_anime_score_stats(response, anime)
      doc = Nokogiri::HTML(response)

      # Summary Stats.
      # Example:
      # <tr>
      #   <td width="20">10</td>
			#	  <td>
      #     <div class="spaceit_pad">
      #       <div class="updatesBar" style="float: left; height: 15px; width: 23%;"></div>
      #       <span>&nbsp;22.8% <small>(12989 votes)</small></span>
      #     </div>
      #   </td>
      # </tr>

      left_column_nodeset = doc.xpath('//table[preceding-sibling::h2[text()="Score Stats"]]')
      progress_bars = left_column_nodeset.search("//small/text()")

      bar_value = 10
      (0..progress_bars.length-1).each { |i|
        progress_bar = progress_bars[i].to_s

        if progress_bar.match %r{\([0-9]+ votes\)}
          progress_bar_value = progress_bar.scan(%r{\(([0-9]+) votes\)}).first.first.to_s
          # puts bar_value.to_s + ' : ' + progress_bar_value
          anime.score_stats[bar_value] = progress_bar_value
          bar_value -= 1
        end
      }

      anime
    end

      def self.parse_anime_response(response)
        doc = Nokogiri::HTML(response)

        anime = Anime.new

        # Anime ID.
        # Example:
        # <input type="hidden" name="aid" value="790">
        anime_id_input = doc.at('input[@name="aid"]')
        if anime_id_input
          anime.id = anime_id_input['value'].to_i
        else
          details_link = doc.at('//a[text()="Details"]')
          anime.id = details_link['href'][%r{http://myanimelist.net/anime/(\d+)/.*?}, 1].to_i
        end

        # Title and rank.
        # Example:
        # <h1><div style="float: right; font-size: 13px;">Ranked #96</div>Lucky ☆ Star</h1>
        anime.title = doc.at(:h1).children.find { |o| o.text? }.to_s
        anime.rank = doc.at('h1 > div').text.gsub(/\D/, '').to_i

        if image_node = doc.at('div#content tr td div img')
          anime.image_url = image_node['src']
        end

        # -
        # Extract from sections on the left column: Alternative Titles, Information, Statistics, Popular Tags.
        # -

        # Alternative Titles section.
        # Example:
        # <h2>Alternative Titles</h2>
        # <div class="spaceit_pad"><span class="dark_text">English:</span> Lucky Star/div>
        # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Lucky Star, Raki ☆ Suta</div>
        # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> らき すた</div>
        left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')

        if (node = left_column_nodeset.at('//span[text()="English:"]')) && node.next
          anime.other_titles[:english] = node.next.text.strip.split(/,\s?/)
        end
        if (node = left_column_nodeset.at('//span[text()="Synonyms:"]')) && node.next
          anime.other_titles[:synonyms] = node.next.text.strip.split(/,\s?/)
        end
        if (node = left_column_nodeset.at('//span[text()="Japanese:"]')) && node.next
          anime.other_titles[:japanese] = node.next.text.strip.split(/,\s?/)
        end


        # Information section.
        # Example:
        # <h2>Information</h2>
        # <div><span class="dark_text">Type:</span> TV</div>
        # <div class="spaceit"><span class="dark_text">Episodes:</span> 24</div>
        # <div><span class="dark_text">Status:</span> Finished Airing</div>
        # <div class="spaceit"><span class="dark_text">Aired:</span> Apr  9, 2007 to Sep  17, 2007</div>
        # <div>
        #   <span class="dark_text">Producers:</span>
        #   <a href="http://myanimelist.net/anime.php?p=2">Kyoto Animation</a>,
        #   <a href="http://myanimelist.net/anime.php?p=104">Lantis</a>,
        #   <a href="http://myanimelist.net/anime.php?p=262">Kadokawa Pictures USA</a><sup><small>L</small></sup>,
        #   <a href="http://myanimelist.net/anime.php?p=286">Bang Zoom! Entertainment</a>
        # </div>
        # <div class="spaceit">
        #   <span class="dark_text">Genres:</span>
        #   <a href="http://myanimelist.net/anime.php?genre[]=4">Comedy</a>,
        #   <a href="http://myanimelist.net/anime.php?genre[]=20">Parody</a>,
        #   <a href="http://myanimelist.net/anime.php?genre[]=23">School</a>,
        #   <a href="http://myanimelist.net/anime.php?genre[]=36">Slice of Life</a>
        # </div>
        # <div><span class="dark_text">Duration:</span> 24 min. per episode</div>
        # <div class="spaceit"><span class="dark_text">Rating:</span> PG-13 - Teens 13 or older</div>
        if (node = left_column_nodeset.at('//span[text()="Type:"]')) && node.next
          anime.type = node.next.text.strip
        end
        if (node = left_column_nodeset.at('//span[text()="Episodes:"]')) && node.next
          anime.episodes = node.next.text.strip.gsub(',', '').to_i
          anime.episodes = nil if anime.episodes == 0
        end
        if (node = left_column_nodeset.at('//span[text()="Status:"]')) && node.next
          anime.status = node.next.text.strip
        end
        if (node = left_column_nodeset.at('//span[text()="Aired:"]')) && node.next
          airdates_text = node.next.text.strip
          anime.start_date = parse_start_date(airdates_text)
          anime.end_date = parse_end_date(airdates_text)
        end
        if node = left_column_nodeset.at('//span[text()="Genres:"]')
          node.parent.search('a').each do |a|
            anime.genres << a.text.strip
          end
        end
        if (node = left_column_nodeset.at('//span[text()="Rating:"]')) && node.next
          anime.classification = node.next.text.strip
        end

        # Statistics
        # Example:
        # <h2>Statistics</h2>
        # <div>
        #   <span class="dark_text">Score:</span> 8.41<sup><small>1</small></sup>
        #   <small>(scored by 22601 users)</small>
        # </div>
        # <div class="spaceit"><span class="dark_text">Ranked:</span> #96<sup><small>2</small></sup></div>
        # <div><span class="dark_text">Popularity:</span> #15</div>
        # <div class="spaceit"><span class="dark_text">Members:</span> 36,961</div>
        # <div><span class="dark_text">Favorites:</span> 2,874</div>
        if (node = left_column_nodeset.at('//span[text()="Score:"]')) && node.next
          anime.members_score = node.next.text.strip.to_f
        end
        if (node = left_column_nodeset.at('//span[text()="Popularity:"]')) && node.next
          anime.popularity_rank = node.next.text.strip.sub('#', '').gsub(',', '').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Members:"]')) && node.next
          anime.members_count = node.next.text.strip.gsub(',', '').to_i
        end
        if (node = left_column_nodeset.at('//span[text()="Favorites:"]')) && node.next
          anime.favorited_count = node.next.text.strip.gsub(',', '').to_i
        end

        # Popular Tags
        # Example:
        # <h2>Popular Tags</h2>
        # <span style="font-size: 11px;">
        #   <a href="http://myanimelist.net/anime.php?tag=comedy" style="font-size: 24px" title="1059 people tagged with comedy">comedy</a>
        #   <a href="http://myanimelist.net/anime.php?tag=parody" style="font-size: 11px" title="493 people tagged with parody">parody</a>
        #   <a href="http://myanimelist.net/anime.php?tag=school" style="font-size: 12px" title="546 people tagged with school">school</a>
        #   <a href="http://myanimelist.net/anime.php?tag=slice of life" style="font-size: 18px" title="799 people tagged with slice of life">slice of life</a>
        # </span>
        if (node = left_column_nodeset.at('//span[preceding-sibling::h2[text()="Popular Tags"]]'))
          node.search('a').each do |a|
            anime.tags << a.text
          end
        end


        # -
        # Extract from sections on the right column: Synopsis, Additional URLs, Related Anime, Characters & Voice Actors, Reviews
        # Recommendations.
        # -
        right_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td/div/table')

        # Synopsis
        # Example:
        # <td>
        # <h2>Synopsis</h2>
        # Having fun in school, doing homework together, cooking and eating, playing videogames, watching anime. All those little things make up the daily life of the anime- and chocolate-loving Izumi Konata and her friends. Sometimes relaxing but more than often simply funny! <br />
        # -From AniDB
        synopsis_h2 = right_column_nodeset.at('//h2[text()="Synopsis"]')
        if synopsis_h2
          node = synopsis_h2.next
          while node
            if anime.synopsis
              anime.synopsis << node.to_s
            else
              anime.synopsis = node.to_s
            end

            node = node.next
          end
        end

        # Additional URLs
        # Example:
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/reviews">Reviews</a></li>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/userrecs">Recommendations</a>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/stats">Stats</a></li>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/characters">Characters & Staff</a></li>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/news">News</a></li>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/forum">Forum</a></li>
        # <li><a  href="http://myanimelist.net/anime/13759/Sakurasou_no_Pet_na_Kanojo/pics">Pictures</a></li>

        if (node = right_column_nodeset.at('//div[@id="horiznav_nav"]/ul'))
          urls = node.search('li')

          (0..urls.length-1).each { |i|
            url_node = urls[i]

            additional_url_title = url_node.at('//div[@id="horiznav_nav"]/ul/li['+(i+1).to_s+']/a[1]/text()')
            additional_url = url_node.at('//div[@id="horiznav_nav"]/ul/li['+(i+1).to_s+']/a[1]/@href')

            if (additional_url_title.to_s == "Details")
              anime.additional_info_urls[:details] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Reviews")
              anime.additional_info_urls[:reviews] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Recommendations")
              anime.additional_info_urls[:recommendations] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Stats")
              anime.additional_info_urls[:stats] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Characters &amp; Staff")
              anime.additional_info_urls[:characters_and_staff] = additional_url.to_s
            end
            if (additional_url_title.to_s == "News")
              anime.additional_info_urls[:news] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Forum")
              anime.additional_info_urls[:forum] = additional_url.to_s
            end
            if (additional_url_title.to_s == "Pictures")
              anime.additional_info_urls[:pictures] = additional_url.to_s
            end
          }
        end

        # Related Anime
        # Example:
        # <td>
        #   <br>
        #   <h2>Related Anime</h2>
        #   Adaptation: <a href="http://myanimelist.net/manga/9548/Higurashi_no_Naku_Koro_ni_Kai_Minagoroshi-hen">Higurashi no Naku Koro ni Kai Minagoroshi-hen</a>,
        #   <a href="http://myanimelist.net/manga/9738/Higurashi_no_Naku_Koro_ni_Matsuribayashi-hen">Higurashi no Naku Koro ni Matsuribayashi-hen</a><br>
        #   Prequel: <a href="http://myanimelist.net/anime/934/Higurashi_no_Naku_Koro_ni">Higurashi no Naku Koro ni</a><br>
        #   Sequel: <a href="http://myanimelist.net/anime/3652/Higurashi_no_Naku_Koro_ni_Rei">Higurashi no Naku Koro ni Rei</a><br>
        #   Side story: <a href="http://myanimelist.net/anime/6064/Higurashi_no_Naku_Koro_ni_Kai_DVD_Specials">Higurashi no Naku Koro ni Kai DVD Specials</a><br>
        related_anime_h2 = right_column_nodeset.at('//h2[text()="Related Anime"]')
        if related_anime_h2

          # Get all text between <h2>Related Anime</h2> and the next <h2> tag.
          match_data = related_anime_h2.parent.to_s.match(%r{<h2>Related Anime</h2>(.+?)<h2>}m)

          if match_data
            related_anime_text = match_data[1]

            if related_anime_text.match %r{Adaptation: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
                anime.manga_adaptations << {
                  :manga_id => manga_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Prequel: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.prequels << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Sequel: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.sequels << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Side story: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.side_stories << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Parent story: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.parent_story = {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Character: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.character_anime << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Spin-off: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.spin_offs << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Summary: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.summaries << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end

            if related_anime_text.match %r{Alternative versions?: ?(<a .+?)<br}
              $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
                anime.alternative_versions << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
                }
              end
            end
          end

        end

        # <h2>My Info</h2>
        # <a name="addtolistanchor"></a>
        # <div id="addtolist" style="display: block;">
        #   <input type="hidden" id="myinfo_anime_id" value="934">
        #   <input type="hidden" id="myinfo_curstatus" value="2">
        #
        #   <table border="0" cellpadding="0" cellspacing="0" width="100%">
        #     <tr>
        #       <td class="spaceit">Status:</td>
        #       <td class="spaceit"><select id="myinfo_status" name="myinfo_status" onchange="checkEps(this);" class="inputtext"><option value="1" selected>Watching</option><option value="2" >Completed</option><option value="3" >On-Hold</option><option value="4" >Dropped</option><option value="6" >Plan to Watch</option></select></td>
        #     </tr>
        #     <tr>
        #       <td class="spaceit">Eps Seen:</td>
        #       <td class="spaceit"><input type="text" id="myinfo_watchedeps" name="myinfo_watchedeps" size="3" class="inputtext" value="26"> / <span id="curEps">26</span></td>
        #     </tr>
        #     <tr>
        #       <td class="spaceit">Your Score:</td>
        #         <td class="spaceit"><select id="myinfo_score" name="myinfo_score" class="inputtext"><option value="0">Select</option><option value="10" >(10) Masterpiece</option><option value="9" >(9) Great</option><option value="8" >(8) Very Good</option><option value="7" >(7) Good</option><option value="6" >(6) Fine</option><option value="5" >(5) Average</option><option value="4" >(4) Bad</option><option value="3" >(3) Very Bad</option><option value="2" >(2) Horrible</option><option value="1" >(1) Unwatchable</option></select></td>
        #     </tr>
        #     <tr>
        #       <td>&nbsp;</td>
        #       <td><input type="button" name="myinfo_submit" value="Update" onclick="myinfo_updateInfo(1100070);" class="inputButton"> <small><a href="http://www.myanimelist.net/panel.php?go=edit&id=1100070">Edit Details</a></small></td>
        #     </tr>
        #   </table>
        watched_status_select_node = doc.at('select#myinfo_status')
        if watched_status_select_node && (selected_option = watched_status_select_node.at('option[selected="selected"]'))
          anime.watched_status = selected_option['value']
        end
        episodes_input_node = doc.at('input#myinfo_watchedeps')
        if episodes_input_node and episodes_input_node['value'].length > 0
          anime.watched_episodes = episodes_input_node['value'].to_i
        end
        score_select_node = doc.at('select#myinfo_score')
        if score_select_node && (selected_option = score_select_node.at('option[selected="selected"]'))
          anime.score = selected_option['value'].to_i
        end
        listed_anime_id_node = doc.at('//a[text()="Edit Details"]')
        if listed_anime_id_node
          anime.listed_anime_id = listed_anime_id_node['href'].match('id=(\d+)')[1].to_i
        end

        anime
      end

      def self.parse_start_date(text)
        text = text.strip

        case text
        when /^\d{4}$/
          return text.strip
        when /^(\d{4}) to \?/
          return $1
        when /^\d{2}-\d{2}-\d{2}$/
          return Date.strptime(text, '%m-%d-%y')
        else
          date_string = text.split(/\s+to\s+/).first
          return nil if !date_string

          Chronic.parse(date_string)
        end
      end

      def self.parse_end_date(text)
        text = text.strip

        case text
        when /^\d{4}$/
          return text.strip
        when /^\? to (\d{4})/
          return $1
        when /^\d{2}-\d{2}-\d{2}$/
          return Date.strptime(text, '%m-%d-%y')
        else
          date_string = text.split(/\s+to\s+/).last
          return nil if !date_string

          Chronic.parse(date_string)
        end
      end

  end # END class Anime
end

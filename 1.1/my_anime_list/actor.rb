module MyAnimeList
  class Actor
    attr_accessor :id, :name, :image_url, :favorited_count, :url
    attr_writer :character, :anime, :roles, :info

    # Scrape actor details page on MyAnimeList.net.
    def self.scrape_actor(id)
      curl = Curl::Easy.new("https://myanimelist.net/people/#{id}")
      curl.headers['User-Agent'] = ENV['USER_AGENT']
      curl.interface = ENV['INTERFACE']

      begin
        curl.perform
      rescue Exception => e
        raise MyAnimeList::NetworkError.new("Network error scraping actor with ID=#{id}. Original exception: #{e.message}.", e)
      end

      response = curl.body_str

      # Check for missing actor.
      raise MyAnimeList::NotFoundError.new("Actor with ID #{id} doesn't exist.", nil) if response =~ /Invalid ID provided/i

      actor = Actor.new
      actor.id = id.to_s

      actor = parse_actor_response(response, actor)

      actor

    rescue MyAnimeList::NotFoundError => e
      raise
    rescue Exception => e
      raise MyAnimeList::UnknownError.new("Error scraping actor with ID=#{id}. Original exception: #{e.message}.", e)
    end

=begin
    def self.search(query)
      begin
        response = Net::HTTP.start('myanimelist.net', 80) do |http|
          http.get("/people.php?q=#{Curl::Easy.new.escape(query)}", {'User-Agent' => ENV['USER_AGENT']})
        end

        case response
          when Net::HTTPRedirection
            redirected = true

            # Strip everything after the actor ID - in cases where there is a non-ASCII character in the URL,
            # MyAnimeList.net will return a page that says "Access has been restricted for this account".
            redirect_url = response['location'].sub(%r{(http://myanimelist.net/people/\d+)/?.*}, '\1')

            response = Net::HTTP.start('myanimelist.net', 80) do |http|
              http.get(redirect_url, {'User-Agent' => ENV['USER_AGENT']})
            end
        end

      rescue Exception => e
        raise MyAnimeList::UpdateError.new("Error searching actor with query '#{query}'. Original exception: #{e.message}", e)
      end

      results = []
      if redirected
        # If there's a single redirect, it means there's only 1 match and MAL is redirecting to the actor's details
        # page.

        actor = parse_actor_response(response.body)
        results << actor

      else
        # Otherwise, parse the table of search results.

        doc = Nokogiri::HTML(response.body)
        results_table = doc.xpath('//div[@id="content"]/div[2]/table')

        results_table.xpath('//tr').each do |results_row|

          manga_title_node = results_row.at('td a strong')
          next unless manga_title_node
          url = manga_title_node.parent['href']
          next unless url.match %r{http://myanimelist.net/manga/(\d+)/?.*}

          manga = Manga.new
          manga.id = $1.to_i
          manga.title = manga_title_node.text
          if image_node = results_row.at('td a img')
            manga.image_url = image_node['src']
          end

          table_cell_nodes = results_row.search('td')

          manga.volumes = table_cell_nodes[3].text.to_i
          manga.chapters = table_cell_nodes[4].text.to_i
          manga.members_score = table_cell_nodes[5].text.to_f
          synopsis_node = results_row.at('div.spaceit_pad')
          if synopsis_node
            synopsis_node.search('a').remove
            manga.synopsis = synopsis_node.text.strip
          end
          manga.type = table_cell_nodes[2].text

          results << manga
        end
      end

      results
    end
=end

    def info
      @info ||= {}
    end

    def roles
      @roles ||= []
    end

    def attributes
      {
          :id => id,
          :name => name,
          :image_url => image_url,
          :info => info,
          :favorited_count => favorited_count,
          :url => url,
          :roles => roles
      }
    end

    def to_json(*args)
      attributes.to_json(*args)
    end

=begin
    def to_xml(options = {})
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! unless options[:skip_instruct]
      xml.anime do |xml|
        xml.id id
        xml.title title
        xml.rank rank
        xml.image_url image_url
        xml.type type.to_s
        xml.status status.to_s
        xml.volumes volumes
        xml.chapters chapters
        xml.members_score members_score
        xml.members_count members_count
        xml.popularity_rank popularity_rank
        xml.favorited_count favorited_count
        xml.synopsis synopsis
        xml.read_status read_status.to_s
        xml.chapters_read chapters_read
        xml.volumes_read volumes_read
        xml.score score

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

        anime_adaptations.each do |anime|
          xml.anime_adaptation do |xml|
            xml.anime_id  anime[:anime_id]
            xml.title     anime[:title]
            xml.url       anime[:url]
          end
        end

        related_manga.each do |manga|
          xml.related_manga do |xml|
            xml.manga_id  manga[:manga_id]
            xml.title     manga[:title]
            xml.url       manga[:url]
          end
        end

        alternative_versions.each do |manga|
          xml.alternative_version do |xml|
            xml.manga_id  manga[:manga_id]
            xml.title     manga[:title]
            xml.url       manga[:url]
          end
        end
      end

      xml.target!
    end
=end

    private

    def self.parse_actor_response(response, actor)

      doc = Nokogiri::HTML(response)

      # Name of this actor.
      content = doc.xpath('//div[@id="contentWrapper"]')

      actor.name = content.at('h1/text()').to_s

      # Biography and image of this actor.
      content = doc.xpath('//div[@id="content"]/table/tr/td[1]')

      actor.image_url = content.at('div img/@src').to_s

      # Move pointer to the inner area where this actor's bio lies.
      content = doc.xpath('//div[@id="content"]/table/tr/td[1]')

      info = {}

      # Given Name.
      if (node = content.at('//span[text()="Given name:"]')) && node.next then
        info[:given_name] = node.next.text.strip
      end

      if (node = content.at('//span[text()="Family name:"]')) && node.next then
        info[:family_name] = node.next.text.strip
      end

      if (node = content.at('//span[text()="Birthday:"]')) && node.next then
        info[:birthday] = node.next.text.strip
      end

      if (node = content.at('//span[text()="Website:"]')) && node.next then
        info[:website] = node.next.next['href'].to_s.strip
      end

      if (node = content.at('//span[text()="Member Favorites:"]')) && node.next then
        actor.favorited_count = node.next.text.strip
      end

      if (node = content.at('//span[text()="More:"]').parent()) then

        info[:extra_info] = []

        while (node = node.next) do
          line = node.text.to_s.strip
          if !(line == '<br>' or line == '<br />' or line.length == 0) then
            info[:extra_info] << line
          end
        end

      end

      actor.info = info

      # Animes that this actor has participated in.
      content = doc.xpath('//div[@id="content"]/table/tr/td[2]/table[1]')

      doc.search('//div[@id="content"]/table/tr/td[2]/table[1]/tr').each do |tr|

        anime = {}
        character = {}

        anime_image_url = tr.xpath('td[1]/div/a/img/@data-src').to_s || tr.xpath('td[1]/div/a/img/@src').to_s

        # umalapi-27: Update in MAL's html caused inaccessible image URLs.
        unless anime_image_url.match(%r{questionmark}) then
          anime_image_url = ('http://cdn.myanimelist.net' + anime_image_url.match(%r{/images/anime/.*.jpg}).to_s).gsub(/t.jpg/, '.jpg').gsub(/r\/\d+x\d+\//, '').gsub(/\?s=.*/, '')
          anime[:image_url] = anime_image_url
        end

        anime_url = tr.xpath('td[2]/a/@href').to_s

        anime[:url] = anime_url
        anime[:name] = tr.xpath('td[2]/a/text()').to_s
        anime[:id] = anime_url[%r{/anime/(\d+)/.*?}, 1].to_s

        character_image_url = tr.xpath('td[4]/div/a/img/@data-src').to_s || tr.xpath('td[4]/div/a/img/@src').to_s

        # umalapi-27: Update in MAL's html caused inaccessible image URLs.
        unless character_image_url.match(%r{questionmark}) then
          character_image_url = ('http://cdn.myanimelist.net' + character_image_url.match(%r{/images/characters/.*.jpg}).to_s).gsub(/t.jpg/, '.jpg').gsub(/r\/\d+x\d+\//, '').gsub(/\?s=.*/, '')
          character[:image_url] = character_image_url
        end

        character_url = tr.xpath('td[3]/a/@href').to_s
        character[:url] = character_url
        character[:name] = tr.xpath('td[3]/a/text()').to_s
        character[:id] = character_url[%r{/character/(\d+)/.*?}, 1].to_s

        actor.roles << { :anime => anime, :character => character }

=begin
  structure:
  roles:
  [
    {
      anime:
      {
        id
        name
        url
        img_url
      }

      character:
      {
        id
        name
        url
        img_url
      }
    }
  ]

=end
      actor

      end



=begin
      manga = Manga.new

      # Manga ID.
      # Example:
      # <input type="hidden" value="104" name="mid" />
      manga_id_input = doc.at('input[@name="mid"]')
      if manga_id_input

        manga.id = manga_id_input['value'].to_i
      else
        details_link = doc.at('//a[text()="Details"]')
        manga.id = details_link['href'][%r{http://myanimelist.net/manga/(\d+)/.*?}, 1].to_i
      end

      # Title and rank.
      # Example:
      # <h1>
      #   <div style="float: right; font-size: 13px;">Ranked #8</div>Yotsuba&!
      #   <span style="font-weight: normal;"><small>(Manga)</small></span>
      # </h1>
      manga.title = doc.at(:h1).children.find { |o| o.text? }.to_s.strip
      manga.rank = doc.at('h1 > div').text.gsub(/\D/, '').to_i

      # Image URL.
      if image_node = doc.at('div#content tr td div img')
        manga.image_url = image_node['src']
      end

      # -
      # Extract from sections on the left column: Alternative Titles, Information, Statistics, Popular Tags.
      # -
      left_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td[@class="borderClass"]')

      # Alternative Titles section.
      # Example:
      # <h2>Alternative Titles</h2>
      # <div class="spaceit_pad"><span class="dark_text">English:</span> Yotsuba&!</div>
      # <div class="spaceit_pad"><span class="dark_text">Synonyms:</span> Yotsubato!, Yotsuba and !, Yotsuba!, Yotsubato, Yotsuba and!</div>
      # <div class="spaceit_pad"><span class="dark_text">Japanese:</span> よつばと！</div>
      if (node = left_column_nodeset.at('//span[text()="English:"]')) && node.next
        manga.other_titles[:english] = node.next.text.strip.split(/,\s?/)
      end
      if (node = left_column_nodeset.at('//span[text()="Synonyms:"]')) && node.next
        manga.other_titles[:synonyms] = node.next.text.strip.split(/,\s?/)
      end
      if (node = left_column_nodeset.at('//span[text()="Japanese:"]')) && node.next
        manga.other_titles[:japanese] = node.next.text.strip.split(/,\s?/)
      end


      # Information section.
      # Example:
      # <h2>Information</h2>
      # <div><span class="dark_text">Type:</span> Manga</div>
      # <div class="spaceit"><span class="dark_text">Volumes:</span> Unknown</div>
      # <div><span class="dark_text">Chapters:</span> Unknown</div>
      # <div class="spaceit"><span class="dark_text">Status:</span> Publishing</div>
      # <div><span class="dark_text">Published:</span> Mar  21, 2003 to ?</div>
      # <div class="spaceit"><span class="dark_text">Genres:</span>
      #   <a href="http://myanimelist.net/manga.php?genre[]=4">Comedy</a>,
      #   <a href="http://myanimelist.net/manga.php?genre[]=36">Slice of Life</a>
      # </div>
      # <div><span class="dark_text">Authors:</span>
      #   <a href="http://myanimelist.net/people/1939/Kiyohiko_Azuma">Azuma, Kiyohiko</a> (Story & Art)
      # </div>
      # <div class="spaceit"><span class="dark_text">Serialization:</span>
      #   <a href="http://myanimelist.net/manga.php?mid=23">Dengeki Daioh (Monthly)</a>
      # </div>
      if (node = left_column_nodeset.at('//span[text()="Type:"]')) && node.next
        manga.type = node.next.text.strip
      end
      if (node = left_column_nodeset.at('//span[text()="Volumes:"]')) && node.next
        manga.volumes = node.next.text.strip.gsub(',', '').to_i
        manga.volumes = nil if manga.volumes == 0
      end
      if (node = left_column_nodeset.at('//span[text()="Chapters:"]')) && node.next
        manga.chapters = node.next.text.strip.gsub(',', '').to_i
        manga.chapters = nil if manga.chapters == 0
      end
      if (node = left_column_nodeset.at('//span[text()="Status:"]')) && node.next
        manga.status = node.next.text.strip
      end
      if node = left_column_nodeset.at('//span[text()="Genres:"]')
        node.parent.search('a').each do |a|
          manga.genres << a.text.strip
        end
      end

      # Statistics
      # Example:
      # <h2>Statistics</h2>
      # <div><span class="dark_text">Score:</span> 8.90<sup><small>1</small></sup> <small>(scored by 4899 users)</small>
      # </div>
      # <div class="spaceit"><span class="dark_text">Ranked:</span> #8<sup><small>2</small></sup></div>
      # <div><span class="dark_text">Popularity:</span> #32</div>
      # <div class="spaceit"><span class="dark_text">Members:</span> 8,344</div>
      # <div><span class="dark_text">Favorites:</span> 1,700</div>
      if (node = left_column_nodeset.at('//span[text()="Score:"]')) && node.next
        manga.members_score = node.next.text.strip.to_f
      end
      if (node = left_column_nodeset.at('//span[text()="Popularity:"]')) && node.next
        manga.popularity_rank = node.next.text.strip.sub('#', '').gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Members:"]')) && node.next
        manga.members_count = node.next.text.strip.gsub(',', '').to_i
      end
      if (node = left_column_nodeset.at('//span[text()="Favorites:"]')) && node.next
        manga.favorited_count = node.next.text.strip.gsub(',', '').to_i
      end

      # Popular Tags
      # Example:
      # <h2>Popular Tags</h2>
      # <span style="font-size: 11px;">
      #   <a href="http://myanimelist.net/manga.php?tag=comedy" style="font-size: 24px" title="241 people tagged with comedy">comedy</a>
      #   <a href="http://myanimelist.net/manga.php?tag=slice of life" style="font-size: 11px" title="207 people tagged with slice of life">slice of life</a>
      # </span>
      if (node = left_column_nodeset.at('//span[preceding-sibling::h2[text()="Popular Tags"]]'))
        node.search('a').each do |a|
          manga.tags << a.text
        end
      end


      # -
      # Extract from sections on the right column: Synopsis, Related Manga
      # -
      right_column_nodeset = doc.xpath('//div[@id="content"]/table/tr/td/div/table')

      # Synopsis
      # Example:
      # <h2>Synopsis</h2>
      # Yotsuba's daily life is full of adventure. She is energetic, curious, and a bit odd &ndash; odd enough to be called strange by her father as well as ignorant of many things that even a five-year-old should know. Because of this, the most ordinary experience can become an adventure for her. As the days progress, she makes new friends and shows those around her that every day can be enjoyable.<br />
      # <br />
      # [Written by MAL Rewrite]
      synopsis_h2 = right_column_nodeset.at('//h2[text()="Synopsis"]')
      if synopsis_h2
        node = synopsis_h2.next
        while node
          if manga.synopsis
            manga.synopsis << node.to_s
          else
            manga.synopsis = node.to_s
          end

          node = node.next
        end
      end

      # Related Manga
      # Example:
      # <h2>Related Manga</h2>
      #   Adaptation: <a href="http://myanimelist.net/anime/66/Azumanga_Daioh">Azumanga Daioh</a><br>
      #   Side story: <a href="http://myanimelist.net/manga/13992/Azumanga_Daioh:_Supplementary_Lessons">Azumanga Daioh: Supplementary Lessons</a><br>
      related_manga_h2 = right_column_nodeset.at('//h2[text()="Related Manga"]')
      if related_manga_h2

        # Get all text between <h2>Related Manga</h2> and the next <h2> tag.
        match_data = related_manga_h2.parent.to_s.match(%r{<h2>Related Manga</h2>(.+?)<h2>}m)

        if match_data
          related_anime_text = match_data[1]

          if related_anime_text.match %r{Adaptation: ?(<a .+?)<br}
            $1.scan(%r{<a href="(/anime/(\d+)/.*?)">(.+?)</a>}) do |url, anime_id, title|
              manga.anime_adaptations << {
                  :anime_id => anime_id,
                  :title => title,
                  :url => url
              }
            end
          end

          if related_anime_text.match %r{.+: ?(<a .+?)<br}
            $1.scan(%r{<a href="(/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
              manga.related_manga << {
                  :manga_id => manga_id,
                  :title => title,
                  :url => url
              }
            end
          end

          if related_anime_text.match %r{Alternative versions?: ?(<a .+?)<br}
            $1.scan(%r{<a href="(/manga/(\d+)/.*?)">(.+?)</a>}) do |url, manga_id, title|
              manga.alternative_versions << {
                  :manga_id => manga_id,
                  :title => title,
                  :url => url
              }
            end
          end
        end
      end


      # User's manga details (only available if he authenticates).
      # <h2>My Info</h2>
      # <div id="addtolist" style="display: block;">
      #   <input type="hidden" id="myinfo_manga_id" value="104">
      #   <table border="0" cellpadding="0" cellspacing="0" width="100%">
      #   <tr>
      #     <td class="spaceit">Status:</td>
      #     <td class="spaceit"><select id="myinfo_status" name="myinfo_status" onchange="checkComp(this);" class="inputtext"><option value="1" selected>Reading</option><option value="2" >Completed</option><option value="3" >On-Hold</option><option value="4" >Dropped</option><option value="6" >Plan to Read</option></select></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Chap. Read:</td>
      #     <td class="spaceit"><input type="text" id="myinfo_chapters" size="3" maxlength="4" class="inputtext" value="62"> / <span id="totalChaps">0</span></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Vol. Read:</td>
      #     <td class="spaceit"><input type="text" id="myinfo_volumes" size="3" maxlength="4" class="inputtext" value="5"> / <span id="totalVols">?</span></td>
      #   </tr>
      #   <tr>
      #     <td class="spaceit">Your Score:</td>
      #     <td class="spaceit"><select id="myinfo_score" name="myinfo_score" class="inputtext"><option value="0">Select</option><option value="10" selected>(10) Masterpiece</option><option value="9" >(9) Great</option><option value="8" >(8) Very Good</option><option value="7" >(7) Good</option><option value="6" >(6) Fine</option><option value="5" >(5) Average</option><option value="4" >(4) Bad</option><option value="3" >(3) Very Bad</option><option value="2" >(2) Horrible</option><option value="1" >(1) Unwatchable</option></select></td>
      #   </tr>
      #   <tr>
      #     <td>&nbsp;</td>
      #     <td><input type="button" name="myinfo_submit" value="Update" onclick="myinfo_updateInfo();" class="inputButton"> <small><a href="http://www.myanimelist.net/panel.php?go=editmanga&id=75054">Edit Details</a></small></td>
      #   </tr>
      #   </table>
      # </div>
      read_status_select_node = doc.at('select#myinfo_status')
      if read_status_select_node && (selected_option = read_status_select_node.at('option[selected="selected"]'))
        manga.read_status = selected_option['value']
      end
      chapters_node = doc.at('input#myinfo_chapters')
      if chapters_node
        manga.chapters_read = chapters_node['value'].to_i
      end
      volumes_node = doc.at('input#myinfo_volumes')
      if volumes_node
        manga.volumes_read = volumes_node['value'].to_i
      end
      score_select_node = doc.at('select#myinfo_score')
      if score_select_node && (selected_option = score_select_node.at('option[selected="selected"]'))
        manga.score = selected_option['value'].to_i
      end
      listed_manga_id_node = doc.at('//a[text()="Edit Details"]')
      if listed_manga_id_node
        manga.listed_manga_id = listed_manga_id_node['href'].match('id=(\d+)')[1].to_i
      end
=end

      actor
    end
  end
end

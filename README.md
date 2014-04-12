umalapi - The MyAnimeList Unofficial API
========================================

umalapi is an unofficial API for http://myanimelist.net/. This API is an extension to the [official API](http://myanimelist.net/modules.php?go=api), which extracts additional information from responses to bring the user more content to digest. Such content includes related works, ratings, tags, and genres. There's much more to come.

MyAnimeList.net's API is stagnant, and there doesn't seem to be any plan to update it. That's annoying. ._.

umalapi originally derived from [chuyeow](https://github.com/chuyeow)'s fantastic [myanimelist-api](https://github.com/chuyeow/myanimelist-api). Why is this on its own repository then? It seems like that project is no longer in development, nor does it seem like there is any interest in reviving the endpoints. So, I've decided to take in the responsibility of improving this so people can use them in their own apps.

For API documentation, check it out [here](http://umal-api.coreyjustinroberts.com/docs/). I will provide common requests in the README in a future update.

What do I need to run this?
---------------------------------------

- ruby 1.9.3 or later.
- libxml2 and libxslt (for nokogiri)
- Bundler gem.
- memcached
- a User-Agent provided by MyAnimeList.net

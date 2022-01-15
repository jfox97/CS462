ruleset my_movie_app {
  meta {
    use module org.themoviedb.sdk alias sdk
    with
      apiKey = meta:rulesetConfig{"api_key"}
      sessionID = meta:rulesetConfig{"session_id"}
    name "My Movie App"
    description <<
An APP for Movies
>>
    author "Jason Fox"
    shares getPopular, lastResponse
  }

  global {
    getPopular = function() {
      sdk:getPopular()
    }

    lastResponse = function() {
      {}.put(ent:lastTimestamp, ent:lastResponse)
    }
  }

  rule rate_movie {
    select when movie new_rating
      movieID re#(.+)#
      rating re#^(\d+([.]\d+)?)$#
      setting(movieID,rating)
    pre {
      rating_value = rating.as("Number")
      valid_rating = 0.5 <= rating_value && rating_value <= 10
    }
    if valid_rating then sdk:rateMovie(movieID,rating) setting(response)
    fired {
      ent:lastResponse := response
      ent:lastTimestamp := time:now()
      raise movie event "rated" attributes event:attrs
    }
  }
}
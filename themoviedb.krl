ruleset org.themoviedb.sdk {
  meta {
    name "themoviedb SDK"
    description <<
SDK for themoviedb.org
>>
    author "Jason Fox"
    configure using
      apiKey = ""
      sessionID = ""
    provides getPopular, rateMovie
  }

  global {
    base_url = "https://api.themoviedb.org/3"

    getPopular = function() {
      queryString = {"api_key":apiKey}
      response = http:get(<<#{base_url}/movie/popular>>, qs=queryString)
      response{"content"}.decode()
    }

    rateMovie = defaction(movieID, rating) {
      queryString = {"api_key":apiKey,"session_id":sessionID}
      body = {"value":rating}
      http:post(<<#{base_url}/movie/#{movieID}/rating>>
        ,qs=queryString,json=body) setting(response)
      return response
    }
  }
}
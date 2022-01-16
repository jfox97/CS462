ruleset com.twilio.sdk {
    meta {
      name "Twilio SDK"
      description <<
  SDK for twilio.com
  >>
      author "Jason Fox"
      configure using
        accountSID = ""
        authToken = ""
        messagingServiceSID = ""
      provides sendMessage, messages
    }
  
    global {
      base_url = <<https://api.twilio.com/2010-04-01/Accounts/#{accountSID}/Messages>>
      basic_auth = {"username":accountSID, "password":authToken}

      messages = function(messageSID=null, pageSize=50, page=0, pageToken="") {
        url = messageSID => <<#{base_url}/#{messageSID}.json>> | <<#{base_url}.json>>
        queryString = {"PageSize":pageSize, "Page":page, "PageToken":pageToken}
        response = messageSID => http:get(url, auth=basic_auth) | http:get(url, qs=queryString, auth=basic_auth)
        response{"content"}.decode()
      }
  
      sendMessage = defaction(phoneNumber, message) {
        body = {"To":phoneNumber, "MessagingServiceSid":messagingServiceSID, "Body":message}
        
        http:post(<<#{base_url}.json>>
          ,auth=basic_auth, form=body) setting(response)
        return response
      }
    }
  }
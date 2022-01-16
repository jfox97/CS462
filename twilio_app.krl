ruleset twilio_app {
  meta {
    use module com.twilio.sdk alias twilio
    with
      accountSID = meta:rulesetConfig{"account_sid"}
      authToken = meta:rulesetConfig{"auth_token"}
      messagingServiceSID = meta:rulesetConfig{"messaging_service_sid"}
    name "My Twilio App"
    description <<
An APP for sending messages
>>
    author "Jason Fox"
    shares lastResponse, messages
  }

  global {
    messages = function(messageSID=null, pageSize=50, page=0, pageToken="", toNumber=null, fromNumber=null) {
      messagesObj = twilio:messages(messageSID, pageSize, page, pageToken)
      messageList = messagesObj{"messages"}
      newMessageList = toNumber => messageList.filter(function(m) { m{"to"} == toNumber }) | messageList
      finalMessageList = fromNumber => messageList.filter(function(m) { m("from") == fromNumber }) | newMessageList
      messagesObj.set(["messages"], finalMessageList)
    }

    lastResponse = function() {
      {}.put(ent:lastTimestamp, ent:lastResponse)
    }
  }

  rule send_message {
    select when twilio send
      phoneNumber re#(\+1\d{10,})#
      message re#(.+)#
      setting(phoneNumber,message)

    twilio:sendMessage(phoneNumber,message) setting(response)

    fired {
      ent:lastResponse := response
      ent:lastTimestamp := time:now()
    }
  }
}
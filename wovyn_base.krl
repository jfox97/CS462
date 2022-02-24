ruleset wovyn_base {
  meta {
    use module com.twilio.sdk alias twilio
    with
      accountSID = meta:rulesetConfig{"account_sid"}
      authToken = meta:rulesetConfig{"auth_token"}
      messagingServiceSID = meta:rulesetConfig{"messaging_service_sid"}
    use module sensor_profile alias profile
    name "Wovyn Base"
    author "Jason Fox"
  }

  global {
    threshold = function() {
      profile:profile(){"threshold"} || 80
    }

    phone = function() {
      profile:profile(){"phone_number"} || "+18019600469"
    }
  }

  rule process_heartbeat {
    select when wovyn heartbeat where event:attr("genericThing")
    pre {
      emitterGUID = event:attr("emitterGUID").klog("Emitter GUID: ")
      genericThing = event:attr("genericThing").klog("Generic thing: ")
      specificThing = event:attr("specificThing").klog("Specific thing: ")
      property = event:attr("property").klog("Property: ")
    }
    send_directive("Heartbeat received", {"emitterGUID":emitterGUID, "genericThing":genericThing, "specificThing":specificThing, "property":property})
    always {
      raise wovyn event "new_temperature_reading" attributes {
        "temperature": genericThing{["data", "temperature"]},
        "timestamp": time:now()
      }
    }
  }

  rule find_high_temps {
    select when wovyn new_temperature_reading where event:attr("temperature")[0]{"temperatureF"} > threshold()
    pre {
      temp = event:attr("temperature")[0]{"temperatureF"}
    }
    send_directive("High temp received", {"temperature": temp})
    always {
      raise wovyn event "threshold_violation" attributes {
        "temperature": temp,
        "timestamp": event:attr("timestamp")
      }
    }
  }

  rule threshold_notification {
    select when wovyn threshold_violation
    pre {
      temp = event:attr("temperature").klog("High temperature: ")
      timestamp = event:attr("timestamp").klog("Timestamp: ")
    }
    twilio:sendMessage(phone(), "High temperature alert. Temperature: " + temp + " Timestamp: " + timestamp)
  }

  rule send_back_channel {
    select when wrangler channel_created
    pre {
      channel = event:attr("channel")
    }
    always {
      raise sensor event "channel_created" attributes {
        "channel": channel
      }
    }
  }
}
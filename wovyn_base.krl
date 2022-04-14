ruleset wovyn_base {
  meta {
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
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

    name = function() {
      profile:profile(){"name"}
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
    foreach subs:established() setting (sub)
    pre {
      temperature = event:attr("temperature")[0]{"temperatureF"}
      timestamp = event:attr("timestamp")
      host = sub{"Tx_host"} || meta:host
    }
    event:send(
      {
        "eci": sub{"Tx"},
        "eid": "threshold_notification",
        "domain": "wovyn", "type": "threshold_violation",
        "attrs": {
          "temperature": temperature,
          "sensor": name(),
          "timestamp": timestamp
        }
      }, host
    )
    fired {
      raise wovyn event "internal_threshold_violation"
    }
  }
  
  rule find_normal_temps {
    select when wovyn new_temperature_reading where event:attr("temperature")[0]{"temperatureF"} <= threshold()
    pre {
      temperature = event:attr("temperature")[0]{"temperatureF"}
      timestamp = event:attr("timestamp")
    }
    noop()
    fired {
      raise wovyn event "temp_okay"
    }
  }
  
  rule send_back_channel {
    select when wrangler channel_created
    pre {
      channel = event:attr("channel")
      parent_eci = wrangler:parent_eci()
    }
    event:send(
      {
          "eci": parent_eci, 
          "eid": "send_channel",
          "domain": "sensor", "type": "channel_created",
          "attrs": { 
            "channel": channel,
            "name": name()
          }
      }
    )
  }

  rule ruleset_added {
    select when wrangler ruleset_installed
      where event:attr("rids") >< meta:rid
    pre {
      parent_eci = wrangler:parent_eci()
      wellKnown_eci = subs:wellKnown_Rx(){"id"}
    }
    event:send(
      {
        "eci": parent_eci,
        "domain": "sensor", "type": "subscription",
        "attrs": {
          "wellKnown_eci": wellKnown_eci,
          "name": name()
        }
      }
    )
  }

  rule auto_accept {
    select when wrangler inbound_pending_subscription_added
    pre {
        my_role = event:attr("Rx_role")
        their_role = event:attr("Tx_role")
    }
    if (my_role=="sensor" && their_role=="manager") ||
      (my_role=="peer" && their_role=="peer")
      then noop()
    fired {
        raise wrangler event "pending_subscription_approval"
            attributes event:attrs
    } else {
        raise wrangler event "inbound_rejection"
            attributes event:attrs
    }
  }
}
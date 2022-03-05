ruleset app_student {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
    }

    rule capture_initial_state {
        select when wrangler ruleset_installed
          where event:attr("rids") >< meta:rid
        if ent:student_eci.isnull() then
          wrangler:createChannel(tags,eventPolicy,queryPolicy) setting(channel)
        fired {
          ent:name := event:attr("name")
          ent:wellKnown_Rx := event:attr("wellKnown_Rx")
          ent:student_eci := channel{"id"}
          raise student event "new_subscription_request"
        }
    }

    rule make_a_subscription {
        select when student new_subscription_request
        event:send({"eci":ent:wellKnown_Rx,
          "domain":"wrangler", "name":"subscription",
          "attrs": {
            "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
            "Rx_role":"registration", "Tx_role":"student",
            "name":ent:name+"-registration", "channel_type":"subscription"
          }
        })
    }
}
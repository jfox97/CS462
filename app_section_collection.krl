ruleset app_section_collection {
  meta {
    use module io.picolabs.wrangler alias wrangler
    shares nameFromID, showChildren, sections, wellKnown_Rx
  }

  global {
    nameFromID = function(section_id) {
      "Section " + section_id + " Pico"
    }
    showChildren = function() {
      wrangler:children()
    }
    sections = function() {
      ent:sections
    }
    wellKnown_Rx = function(section_id) {
      eci = ent:sections{[section_id,"eci"]}
      eci.isnull() => null
        | ctx:query(eci,"io.picolabs.subscription","wellKnown_Rx"){"id"}
    }
  }

  rule initialize_sections {
    select when section needs_initialization
    always {
      ent:sections := {}
    }
  }

  rule section_already_exists {
    select when section needed
    pre {
      section_id = event:attr("section_id")
      exists = ent:sections && ent:sections >< section_id
    }
    if exists then
      send_directive("section_ready", {"section_id":section_id})
  }

  rule section_needed {
    select when section needed
    pre {
      section_id = event:attr("section_id")
      exists = ent:sections && ent:sections >< section_id
    }
    if not exists then noop()
    fired {
      raise wrangler event "new_child_request"
        attributes { "name": nameFromID(section_id),
                     "backgroundColor": "#ff69b4",
                     "section_id": section_id }
    }
  }

  rule section_offline {
    select when section offline
    pre {
      section_id = event:attr("section_id")
      exists = ent:sections >< section_id
      eci_to_delete = ent:sections{[section_id,"eci"]}
    }
    if exists && eci_to_delete then
      send_directive("deleting_section", {"section_id":section_id})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
      clear ent:sections{[section_id]}
    }
  }

  rule store_new_section {
    select when wrangler new_child_created
    pre {
      the_section = {"eci": event:attr("eci")}
      section_id = event:attr("section_id")
    }
    if section_id.klog("found section_id") then
      event:send(
        { "eci": the_section.get("eci"), "eid": "install-ruleset",
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "url": "file:///Users/jfox/School/CS462/Rulesets/app_section.krl",
            "config":{},
            "section_id":section_id
          }
        }
      )
    fired {
      ent:sections{section_id} := the_section
    }
  }

  rule accept_wellKnown {
    select when section identify
      section_id re#(.+)#
      wellKnown_eci re#(.+)#
      setting(section_id,wellKnown_eci)
    fired {
      ent:sections{[section_id,"wellKnown_eci"]} := wellKnown_eci
    }
  }

  rule auto_accept {
    select when wrangler inbound_pending_subscription_added
    pre {
      my_role = event:attr("Rx_role")
      their_role = event:attr("Tx_role")
    }
    if my_role=="student" && their_role=="registration" then noop()
    fired {
      raise wrangler event "pending_subscription_approval"
        attributes event:attrs
      ent:subscriptionTx := event:attr("Tx")
    } else {
      raise wrangler event "inbound_rejection"
        attributes event:attrs
    }
  }
}
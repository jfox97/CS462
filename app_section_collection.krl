ruleset app_section_collection {
  meta {
    use module io.picolabs.wrangler alias wrangler
    name "App Section Collection"
    author "Jason Fox"
    shares nameFromID, showChildren, sections
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

  rule store_new_section {
    select when wrangler new_child_created
    pre {
      the_section = {"eci": event:attr("eci")}
      section_id = event:attr("section_id")
    }
    if section_id.klog("found section_id") then
      event:send(
        { "eci": the_section.get("eci"), 
          "eid": "install-ruleset", // can be anything, used for correlation
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "app_section",
            "config": {},
            "section_id": section_id
          }
        }
      )
    fired {
      ent:sections{section_id} := the_section
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
      clear ent:sections{section_id}
    }
  }
}
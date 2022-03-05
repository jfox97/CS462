ruleset app_section {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
    }

    rule pico_ruleset_added {
        select when wrangler ruleset_installed
          where event:attr("rids") >< meta:rid
        pre {
          section_id = event:attr("section_id")
          parent_eci = wrangler:parent_eci()
          wellKnown_eci = subs:wellKnown_Rx(){"id"}
        }
        event:send({"eci":parent_eci,
          "domain": "section", "type": "identify",
          "attrs": {
            "section_id": section_id,
            "wellKnown_eci": wellKnown_eci
          }
        })
        always {
          ent:section_id := section_id
        }
      }
}
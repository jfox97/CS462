ruleset app_registration {
    meta {
        use module io.picolabs.wrangler alias wrangler
    }

    rule init_section_collection_eci {
        select when init section_collection_eci
        pre {
            eci = event:attrs{"eci"}
        }
        fired {
            ent:sectionCollectionECI := eci
        }
    }

    rule allow_student_to_register {
        select when student arrives
          name re#(.+)# setting(name)
        pre {
          backgroundColor = event:attr("backgroundColor") || "#CCCCCC"
        }
        event:send({"eci":wrangler:parent_eci(),
          "domain":"wrangler", "type":"new_child_request",
          "attrs":{
            "name":name,
            "backgroundColor": backgroundColor,
            "wellKnown_Rx":ent:sectionCollectionECI
          }
        })
    }
}
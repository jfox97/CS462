ruleset sensor_profile {
    meta {
        name "Sensor Profile"
        author "Jason Fox"
        provides profile
        shares profile
    }

    global {
        profile = function() {
            {
                "location": ent:location,
                "name": ent:name,
                "threshold": ent:threshold,
                "phone_number": ent:phone_number
            }
        }
    }

    rule profile_updated {
        select when sensor profile_updated
        pre {
            location = event:attr("location")
            name = event:attr("name")
            threshold = event:attr("threshold")
            phone_number = event:attr("phone_number")
        }
        always {
            ent:location := location
            ent:name := name
            ent:threshold := threshold
            ent:phone_number := phone_number
        }
    }
}
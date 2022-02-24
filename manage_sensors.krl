ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        name "Manage Sensors"
        author "Jason Fox"
        shares sensors, temperatures
    }

    global {
        sensors = function() {
            ent:sensors
        }

        temperatures = function() {
            ent:sensors.values().map(function(v) {
                wrangler:skyQuery(v{"test_channel"}, "temperature_store", "temperatures")
            }).reduce(function(a, b) { a.append(b) })
        }

        rulesets = [
            {
                "id": 0,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/twilio.sdk.krl",
                "config": {}
            },
            {
                "id": 1,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/temperature_store.krl",
                "config": {}
            },
            {
                "id": 2,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/sensor_profile.krl",
                "config": {}
            },
            {
                "id": 3,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/io.picoloabs.wovyn.emitter.krl",
                "config": {}
            },
            {
                "id": 4,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/wovyn_base.krl",
                "config": {
                    "account_sid": meta:rulesetConfig{"account_sid"},
                    "auth_token": meta:rulesetConfig{"auth_token"},
                    "messaging_service_sid": meta:rulesetConfig{"messaging_service_sid"}
                }
            },
        ]

        default_location = "Vineyard, UT"
        default_phone = "+18019600469"
        default_threshold = "75"
    }

    rule initialize {
        select when sensors init
        always {
            ent:sensors := {}
        }
    }
    
    rule new_sensor {
        select when sensor new_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors && ent:sensors >< name
        }
        if exists then
            send_directive("sensor ready", {"sensor_name":name})
        notfired {
            raise wrangler event "new_child_request"
                attributes { "name": name,
                             "backgroundColor": "#99ffff"}
        }
    }

    rule store_sensor {
        select when wrangler new_child_created
        pre {
            sensor = {"eci": event:attr("eci")}
            name = event:attr("name")
        }
        fired {
            ent:sensors := ent:sensors.defaultsTo({})
            ent:sensors{name} := sensor
        }
    }

    rule install_rulesets {
        select when wrangler new_child_created
        foreach rulesets setting (r)
        pre {
            eci = event:attr("eci")
            name = event:attr("name")
        }
        event:send(
            {
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": r{"url"},
                    "config": r{"config"}
                }
            }
        )
        fired {
            raise sensor event "ruleset_installed"
                attributes {"ruleset": r, "eci": eci, "name": name}
        }
    }

    rule set_sensor_profile {
        select when sensor ruleset_installed where event:attr("ruleset"){"id"} == rulesets.length() - 1
        pre {
            eci = event:attr("eci")
            name = event:attr("name")
        }
        event:send(
            {
                "eci": eci,
                "eid": "set-sensor-profile",
                "domain": "sensor", "type": "profile_updated",
                "attrs": {
                    "location": default_location,
                    "name": name,
                    "threshold": default_threshold,
                    "phone_number": default_phone
                }
            }
        )
        fired {
            raise sensor event "profile_set" attributes {
                "eci": eci
            }
        }
    }

    rule add_test_channel {
        select when sensor profile_set
        pre {
            eci = event:attr("eci")
        }
        event:send(
            {
                "eci": eci,
                "eid": "add-test-channel",
                "domain": "wrangler", "type": "new_channel_request",
                "attrs": {
                    "tags": ["test"],
                    "eventPolicy": {
                        "allow": [ { "domain": "emitter", "name": "*" }, { "domain": "sensor", "name": "*" } ],
                        "deny": []
                    },
                    "queryPolicy": {
                        "allow": [ { "rid": "sensor_profile", "name": "*" }, { "rid": "temperature_store", "name": "*" } ],
                        "deny": []
                    }
                }
            }
        )
    }

    rule store_test_channel {
        select when sensor channel_created where event:attr("channel"){"tags"} >< "test"
        pre {
            name = event:attr("name")
            channel = event:attr("channel"){"id"}
        }
        if name != null && name.length() > 0 then noop()
        fired {
            ent:sensors{[name, "test_channel"]} := channel
        }
    }

    rule delete_sensor {
        select when sensor unneeded_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors && ent:sensors >< name
            eci = ent:sensors{[name, "eci"]}
        }
        if exists && eci then
            send_directive("deleting_sensor", {"name": name})
        fired {
            raise wrangler event "child_deletion_request"
                attributes {"eci": eci}
            clear ent:sensors{name}
        }
    }
}
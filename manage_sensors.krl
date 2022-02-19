ruleset manage_sensors {
    meta {
        name "Manage Sensors"
        author "Jason Fox"
        shares sensors
    }

    global {
        sensors = function() {
            ent:sensors
        }
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

    rule store_new_sensor {
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

    rule install_twilio_sdk {
        select when wrangler new_child_created
        pre
        {
            eci = event:attr("eci")
        }
        event:send(
            {
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/twilio.sdk.krl",
                    "config": {}
                }
            }
        )
        fired {
            raise sensor event "twilio_sdk_installed" attributes {
                "eci": eci
            }
        }
    }

    rule install_temperature_store {
        select when wrangler new_child_created
        pre
        {
            eci = event:attr("eci")
        }
        event:send(
            { 
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/temperature_store.krl",
                    "config": {}
                }
            }
        )
    }

    rule install_wovyn_base {
        select when sensor twilio_sdk_installed
        pre
        {
            eci = event:attr("eci")
        }
        event:send(
            {
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/wovyn_base.krl",
                    "config": {"account_sid":"AC426c1eb111b29962294e16f204523e52","auth_token":"2b237dfedda92a45065276e2900ec06d","messaging_service_sid":"MGcf4ea7f4f0db5d07ec57cedfe01c0901"}
                }
            }
        )
    }

    rule install_sensor_profile {
        select when wrangler new_child_created
        pre
        {
            eci = event:attr("eci")
        }
        event:send(
            { 
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/sensor_profile.krl",
                    "config": {}
                }
            }
        )
    }

    rule install_wovyn_emitter {
        select when wrangler new_child_created
        pre
        {
            eci = event:attr("eci")
        }
        event:send(
            { 
                "eci": eci, 
                "eid": "install-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/io.picoloabs.wovyn.emitter.krl",
                    "config": {}
                }
            }
        )
    }
}
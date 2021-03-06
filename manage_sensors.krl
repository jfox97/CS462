ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
        name "Manage Sensors"
        author "Jason Fox"
        shares sensors, temperatures, notifications_sent, temperature_reports
    }

    global {
        sensors = function() {
            ent:sensors
        }

        temperatures = function() {
            subs:established().filter(function(v) {
                v{"Tx_role"} == "sensor"
            }).map(function(v) {
                host = v{"Tx_host"} || meta:host
                wrangler:skyQuery(v{"Tx"}, "temperature_store", "temperatures", {}, host)
            }).reduce(function(a, b) { a.append(b) })
        }

        min = function(x, y) {
            x < y => x | y
        }

        temperature_reports = function() {
            report_ids = ent:temperature_reports.keys().sort("reverse").slice(0, min(4, ent:temperature_reports.length()))
            report_ids.reduce(function(recent_reports, report_id) {
              recent_reports.put(report_id, ent:temperature_reports{report_id})
            }, {})
        }

        notifications_sent = function() {
            ent:notifications_sent
        }

        rulesets = [ 
            {
                "id": 0,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/sensor_profile.krl",
                "config": {}
            },
            {
                "id": 1,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/temperature_store.krl",
                "config": {}
            },
            {
                "id": 2,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/io.picoloabs.wovyn.emitter.krl",
                "config": {}
            },
            {
                "id": 3,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/wovyn_base.krl",
                "config": {}
            },
            {
                "id": 4,
                "url": "https://raw.githubusercontent.com/jfox97/CS462/master/gossip.krl",
                "config": {}
            }
        ]

        default_location = "Vineyard, UT"
        default_phone = "+18019600469"
        default_threshold = "75"
    }

    rule initialize {
        select when sensors init
        always {
            ent:sensors := {}
            ent:current_rcn := 1000
            ent:temperature_reports := {}
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

    rule subscribe_sensor {
        select when sensor subscription
        pre {
            wellKnown_eci = event:attr("wellKnown_eci")
            name = event:attr("name")
            host = event:attr("host")
        }
        if wellKnown_eci && wellKnown_eci != "" then noop()
        fired {
            raise wrangler event "subscription"
                attributes {
                    "wellKnown_Tx": wellKnown_eci,
                    "Rx_role": "manager", "Tx_role": "sensor",
                    "name": name, "channel_type": "subscription",
                    "Tx_host": host
                }
        }
    }

    rule send_threshold_violation_notification {
        select when wovyn threshold_violation
        pre {
            temperature = event:attr("temperature")
            sensor = event:attr("sensor")
        }
        always {
            raise manager event "send_message"
                attributes {
                    "message": "High temp noticiation: Current temperature is " + temperature + " degrees Fahrenheit"
                }
            ent:notifications_sent := ent:notifications_sent.defaultsTo([])
            ent:notifications_sent := ent:notifications_sent.append({"sensor": sensor, "temperature": temperature})
        }
    }

    rule reset_notification_history {
        select when manager reset_notification_history
        always {
            ent:notifications_sent := []
        }
    }

    rule start_temperature_report {
        select when manager start_temperature_report
        foreach subs:established().filter(function(v) {
            v{"Tx_role"} == "sensor"
        }) setting(sensor_sub)
        pre {
            host = sensor_sub{"Tx_host"} || meta:host
            tx = sensor_sub{"Tx"}
            rx = sensor_sub{"Rx"}
        }
        event:send(
            {
                "eci": tx,
                "eid": "temperature_report",
                "domain": "manager", "type": "temperature_report",
                "attrs": {"rcn": ent:current_rcn, "tx": rx}
            }, 
            host
        )
        always {
            ent:current_rcn := ent:current_rcn + 1 on final
        }
    }

    rule catch_temperature_reports {
        select when sensor temperature_report_created
        pre {
            name = event:attr("name")
            rcn = event:attr("rcn")
            temperature = event:attr("temperature").put("name", name)
            num_sensors = subs:established().length()
        }
        always {
            ent:temperature_reports{[rcn, "temperature_sensors"]} := num_sensors
            ent:temperature_reports{[rcn, "responding"]} := (ent:temperature_reports{[rcn, "responding"]}).defaultsTo(0) + 1
            ent:temperature_reports{[rcn, "temperatures"]} := (ent:temperature_reports{[rcn, "temperatures"]}).defaultsTo([]).append(temperature)
        }
    }

    rule update_wovyn_base_ruleset {
        select when manager update_wovyn_base_ruleset
        foreach subs:established().filter(function(v) {
            v{"Tx_role"} == "sensor"
        }) setting(sensor_sub)
        pre {
            tx = sensor_sub{"Tx"}
        }
        event:send(
            {
                "eci": tx,
                "eid": "update-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/wovyn_base.krl",
                    "config": {}
                }
            }
        )
    }

    rule update_gossip_ruleset {
        select when manager update_gossip_ruleset
        foreach subs:established().filter(function(v) {
            v{"Tx_role"} == "sensor"
        }) setting(sensor_sub)
        pre {
            tx = sensor_sub{"Tx"}
        }
        event:send(
            {
                "eci": tx,
                "eid": "update-ruleset",
                "domain": "wrangler", "type": "install_ruleset_request",
                "attrs": {
                    "url": "https://raw.githubusercontent.com/jfox97/CS462/master/gossip.krl",
                    "config": {}
                }
            }
        )
    }

    rule set_period {
        select when manager set_period
        foreach subs:established().filter(function(v) {
            v{"Tx_role"} == "sensor"
        }) setting(sensor_sub)
        pre {
            tx = sensor_sub{"Tx"}
            period = event:attr("period")
        }
        event:send(
            {
                "eci": tx,
                "eid": "change_period",
                "domain": "gossip", "type": "change_period",
                "attrs": {
                    "period": period,
                }
            }
        )
    }
}
ruleset gossip {
    meta {
        name "Gossip"
        use module io.picolabs.subscription alias subs
        shares period, get_schedule, heartbeat_count, temperatures, sequences, sensor_id, get_rumors_for_seen, get_sequences_from_seen, get_potential_peers, get_peer, channels
    }

    global {
        default_heartbeat_period = 1 // seconds

        period = function() {
            ent:heartbeat_period
        }

        get_schedule = function() {
            ent:schedule
        }

        heartbeat_count = function() {
            ent:heartbeat_count
        }

        temperatures = function() {
            ent:temperatures
        }

        sequences = function() {
            ent:sequences
        }

        sensor_id = function() {
            ent:sensor_id
        }

        channels = function() {
            ent:channels
        }

        get_rumors_for_seen = function(seen) {
            new_sensors = ent:temperatures.keys().difference(seen.keys())
            new_sensor_rumors = new_sensors.reduce(function(array, sensor_id) {
                array.append(ent:temperatures{sensor_id}.map(function(temperature_object) {
                    {
                        "MessageID": sensor_id + ":" + temperature_object{"sequence"},
                        "SensorID": sensor_id,
                        "Temperature": temperature_object{"temperature"},
                        "Timestamp": temperature_object{"timestamp"}
                    }
                }))
            }, [])

            higher_sensors = ent:temperatures.keys().intersection(seen.keys()).filter(function(sensor_id) {
                ent:sequences{[ent:sensor_id, sensor_id]} > seen{sensor_id}
            })
            higher_sensor_rumors = higher_sensors.reduce(function(array, sensor_id) {
                temperature_objects = ent:temperatures{sensor_id}.filter(function(temperature_object) {
                    (not temperature_object.isnull()) && temperature_object{"sequence"} > seen{sensor_id}
                })
                array.append(temperature_objects.map(function(temperature_object) {
                    {
                        "MessageID": sensor_id + ":" + temperature_object{"sequence"},
                        "SensorID": sensor_id,
                        "Temperature": temperature_object{"temperature"},
                        "Timestamp": temperature_object{"timestamp"}
                    }
                }))
            }, [])

            new_sensor_rumors.append(higher_sensor_rumors)
        }

        get_sequences_from_seen = function(seen) {
            all_sensors = seen.keys().union(ent:sequences{ent:sensor_id}.keys())
            all_sensors.reduce(function(m, sensor_id) {
                seen_for_sensor = seen{sensor_id}.isnull() => -1 | seen{sensor_id}
                our_seen_for_sensor = ent:sequences{[ent:sensor_id, sensor_id]}.isnull() => -1 | ent:sequences{[ent:sensor_id, sensor_id]}
                m.put([sensor_id], max(seen_for_sensor, our_seen_for_sensor))
            }, {})
        }

        max = function(x, y) {
            x > y => x | y
        }

        get_potential_peers = function() {
            ent:sequences.keys().difference([ent:sensor_id]).filter(function (sensor_id) {
                ent:sequences{ent:sensor_id}.keys().any(function (key) {
                    peer_sequence = ent:sequences{[sensor_id, key]}.isnull() => -1 | ent:sequences{[sensor_id, key]}
                    ent:sequences{[ent:sensor_id, key]} > peer_sequence
                })
            })
        }

        get_peer_diff = function(sensor_id) {
            ent:sequences{ent:sensor_id}.keys().reduce(function (total, key) {
                total + (ent:sequences{[ent:sensor_id, key]} - (ent:sequences{[sensor_id, key]} || 0))
            }, 0)
        }

        get_peer = function() {
            potential_peers = get_potential_peers()
            potential_peers.reduce(function(a, b) {
                get_peer_diff(a) > get_peer_diff(b) => a | b
            })
        }
    }

    rule initialize_ruleset {
        select when wrangler ruleset_installed where event:attr("rids") >< meta:rid
        pre {
            period = ent:heartbeat_period
                    .defaultsTo(event:attr("heartbeat_period") || default_heartbeat_period)
                    .klog("Initilizing heartbeat period: "); // in seconds
    
        }
        if ( ent:heartbeat_period.isnull() && schedule:list().length() == 0) then send_directive("Initializing gossip heartbeat");
        fired {
            ent:heartbeat_period := period if ent:heartbeat_period.isnull();
    
            schedule gossip event "heartbeat" repeat << */#{period} * * * * * >> setting(new_schedule)
            ent:schedule := new_schedule
        }
    }

    rule reset_ruleset {
        select when wrangler ruleset_installed where event:attr("rids") >< meta:rid
        always {
            ent:heartbeat_count := 0
            ent:temperatures := {}
            ent:sensor_id := random:uuid()
            ent:sequences := {}
            ent:sequences:= {}
            ent:channels := {} // keep a mapping between sensor_ids and tx channel ids
        }
    }

    rule change_period {
        select when gossip change_period
        pre {
            period = event:attr("period")
        }
        if period > 0 then schedule:remove(ent:schedule{"id"})
        fired {
            ent:heartbeat_period := period
    
            schedule gossip event "heartbeat" repeat << */#{period} * * * * * >> setting(new_schedule)
            ent:schedule := new_schedule
        }
    }

    rule execute_seen {
        select when gossip heartbeat where get_potential_peers().length() == 0 || random:integer(2) == 1
        foreach subs:established().filter(function(v) {
            v{"Tx_role"} == "peer"
        }) setting(peer_sub)
        pre {
            tx = peer_sub{"Tx"}
            rx = peer_sub{"Rx"}
        }
        if (not tx.isnull()) then
        event:send(
            {
                "eci": tx,
                "eid": "seen",
                "domain": "gossip", "type": "seen",
                "attrs": {
                    "sensor_id": ent:sensor_id,
                    "Rx": rx,
                    "seen": ent:sequences{ent:sensor_id}
                }
            }
        )
    }

    rule execute_rumor {
        select when gossip heartbeat where get_potential_peers().length() > 0
        pre {
            sensor_id = get_peer()
        }
        always {
            raise gossip event "send_rumor"
                attributes {"sensor_id": sensor_id}
        }
    }

    rule send_rumor {
        select when gossip send_rumor
        foreach get_rumors_for_seen(ent:sequences{event:attr("sensor_id")}) setting(rumor)
        pre {
            sensor_id = event:attr("sensor_id")
            tx = ent:channels{sensor_id}
        }
        if (not tx.isnull()) then
        event:send(
            {
                "eci": tx,
                "eid": "rumor",
                "domain": "gossip", "type": "rumor",
                "attrs": rumor
            }
        )
        fired {
            ent:sequences{sensor_id} := get_sequences_from_seen(ent:sequences{sensor_id}) on final
        }
    }

    rule store_temperature {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attr("temperature")[0]{"temperatureF"}
            timestamp = event:attr("timestamp")
            sequence_number = ent:sequences{[ent:sensor_id, ent:sensor_id]}.isnull() => 0 | ent:sequences{[ent:sensor_id, ent:sensor_id]} + 1
        }
        always {
            ent:temperatures{[ent:sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "temperature": temperature,
                "timestamp": timestamp
            }
            ent:sequences{[ent:sensor_id, ent:sensor_id]} := sequence_number
        }
    }

    rule store_rumor {
        select when gossip rumor
        pre {
            sequence_number = event:attr("MessageID").split(re#:#)[1].as("Number")
            sensor_id = event:attr("SensorID")
            temperature = event:attr("Temperature")
            timestamp = event:attr("Timestamp")
        }
        if (ent:temperatures >< sensor_id && ent:temperatures{sensor_id}[sequence_number].isnull()) || 
            (not (ent:temperatures >< sensor_id))
            then noop()
        fired {
            ent:temperatures{[sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "temperature": temperature,
                "timestamp": timestamp
            }
        }
    }

    rule set_sequence {
        select when gossip rumor
        pre {
            sequence_number = event:attr("MessageID").split(re#:#)[1].as("Number")
            sensor_id = event:attr("SensorID")
        }
        if (ent:sequences{ent:sensor_id} >< sensor_id && ent:sequences{[ent:sensor_id, sensor_id]} == sequence_number - 1) ||
            ((not (ent:sequences{ent:sensor_id} >< sensor_id)) && sequence_number == 0)
            then noop()
        fired {
            ent:sequences{[ent:sensor_id, sensor_id]} := sequence_number
        }
    }

    rule send_rumors_for_seen {
        select when gossip seen
        foreach get_rumors_for_seen(event:attr("seen")) setting(rumor)
        pre {
            sensor_id = event:attr("sensor_id") // For testing in web interface
            tx = event:attr("Rx")
        }
        if (not tx.isnull()) then
        event:send(
            {
                "eci": tx,
                "eid": "send_rumor_for_seen",
                "domain": "gossip", "type": "rumor",
                "attrs": rumor
            }
        )
        fired {
            ent:channels{sensor_id} := tx on final
        }
    }

    rule update_sequences_from_seen {
        select when gossip seen
        pre {
            sensor_id = event:attr("sensor_id")
            new_sequences = get_sequences_from_seen(event:attr("seen"))
        }
        if (not sensor_id.isnull()) then noop()
        fired {
            ent:sequences{sensor_id} := new_sequences
        }
    }
}
ruleset gossip {
    meta {
        name "Gossip"
        use module io.picolabs.subscription alias subs
        shares period, get_schedule, heartbeat_count, temperatures, sequences, sensor_id, get_rumors_for_seen,
        get_sequences_from_seen, get_potential_peers, get_peer, channels, violations, violation_messages, violation_counts
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

        violations = function() {
            ent:violations
        }

        violation_messages = function() {
            ent:violation_messages
        }

        violation_counts = function() {
            ent:violation_counter
        }

        get_rumors_for_seen = function(seen) {
            new_messages = ent:sequences{ent:sensor_id}.keys().difference(seen.keys())
            new_message_rumors = new_messages.reduce(function(array, message_head) {
                sensor_id = message_head.split(re#:#)[0]
                message_type = message_head.split(re#:#)[1]
                updated_array = message_type == "temperature" => 
                array.append(ent:temperatures{sensor_id}.map(function(temperature_object) {
                    {
                        "MessageID": message_head + ":" + temperature_object{"sequence"},
                        "SensorID": sensor_id,
                        "Temperature": temperature_object{"temperature"},
                        "Timestamp": temperature_object{"timestamp"}
                    }
                })) | array.append(ent:violation_messages{sensor_id}.map(function(violation_message) {
                    {
                        "MessageID": message_head + ":" + violation_message{"sequence"},
                        "SensorID": sensor_id,
                        "Increment": violation_message{"increment"}
                    }
                }))
                updated_array
            }, [])

            higher_messages = ent:sequences{ent:sensor_id}.keys().intersection(seen.keys()).filter(function(message_head) {
                ent:sequences{[ent:sensor_id, message_head]} > seen{message_head}
            })
            higher_message_rumors = higher_messages.reduce(function(array, message_head) {
                sensor_id = message_head.split(re#:#)[0]
                message_type = message_head.split(re#:#)[1]
                messages = message_type == "temperature" => ent:temperatures{sensor_id}.filter(function(temperature_object) {
                    (not temperature_object.isnull()) && temperature_object{"sequence"} > seen{message_head}
                }) | ent:violation_messages{sensor_id}.filter(function(violation_message) {
                    (not violation_message.isnull()) && violation_message{"sequence"} > seen{message_head}
                })
                updated_array = message_type == "temperature" => array.append(messages.map(function(temperature_object) {
                    {
                        "MessageID": message_head + ":" + temperature_object{"sequence"},
                        "SensorID": sensor_id,
                        "Temperature": temperature_object{"temperature"},
                        "Timestamp": temperature_object{"timestamp"}
                    }
                })) | array.append(messages.map(function(violation_message) {
                    {
                        "MessageID": message_head + ":" + violation_message{"sequence"},
                        "SensorID": sensor_id,
                        "Increment": violation_message{"increment"}
                    }
                }))
                updated_array
            }, [])

            new_message_rumors.append(higher_message_rumors)
        }

        get_sequences_from_seen = function(seen) {
            all_messages = seen.keys().union(ent:sequences{ent:sensor_id}.keys())
            all_messages.reduce(function(m, message_head) {
                seen_for_message_head = seen{message_head}.isnull() => -1 | seen{message_head}
                our_seen_for_message_head = ent:sequences{[ent:sensor_id, message_head]}.isnull() => -1 | ent:sequences{[ent:sensor_id, message_head]}
                m.put([message_head], max(seen_for_message_head, our_seen_for_message_head))
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
            ent:violations := {}
            ent:violation_messages := {}
            ent:violation_counter := {}
            ent:sensor_id := random:uuid()
            ent:sequences := {}
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
            sequence_number = ent:sequences{[ent:sensor_id, ent:sensor_id + ":temperature"]}.isnull() => 0 | ent:sequences{[ent:sensor_id, ent:sensor_id + ":temperature"]} + 1
        }
        always {
            ent:temperatures{[ent:sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "temperature": temperature,
                "timestamp": timestamp
            }
            ent:sequences{[ent:sensor_id, ent:sensor_id + ":temperature"]} := sequence_number
        }
    }

    rule store_violation {
        select when wovyn internal_threshold_violation
        pre {
            sequence_number = ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]}.isnull() => 0 | ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]} + 1
            increment = (not (ent:violations >< ent:sensor_id)) || (ent:violations{ent:sensor_id} == 0) => 1 | 0
        }
        always {
            ent:violations{ent:sensor_id} := 1
            ent:violation_messages{[ent:sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "increment": increment
            }
            ent:violation_counter{ent:sensor_id} := ent:violation_counter{ent:sensor_id}.defaultsTo(0) + increment
            ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]} := sequence_number
        }
    }

    rule store_temp_okay {
        select when wovyn temp_okay
        pre {
            sequence_number = ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]}.isnull() => 0 | ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]} + 1
        }
        if (ent:violations >< ent:sensor_id) && (ent:violations{ent:sensor_id} == 1) then noop()
        fired {
            ent:violations{ent:sensor_id} := 0
            ent:violation_messages{[ent:sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "increment": -1
            }
            ent:sequences{[ent:sensor_id, ent:sensor_id + ":violation"]} := sequence_number
        }
    }

    rule handle_rumor {
        select when gossip rumor
        pre {
            message_type = event:attr("MessageID").split(re#:#)[1]
            sequence_number = event:attr("MessageID").split(re#:#)[2].as("Number")
            event_attributes = event:attrs.put(["message_type"], message_type).put(["sequence_number"], sequence_number)
        }
        always {
            raise gossip event "handle_rumor" attributes event_attributes
        }
    }

    rule handle_temperature_rumor {
        select when gossip handle_rumor where event:attr("message_type") == "temperature"
        pre {
            sequence_number = event:attr("sequence_number")
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

    rule handle_violation_rumor {
        select when gossip handle_rumor where event:attr("message_type") == "violation"
        pre {
            sequence_number = event:attr("sequence_number")
            sensor_id = event:attr("SensorID")
            increment = event:attr("Increment")
        }
        if (ent:violation_messages >< sensor_id && ent:violation_messages{sensor_id}[sequence_number].isnull()) ||
            (not (ent:violation_messages >< sensor_id))
            then noop()
        fired {
            ent:violation_messages{[sensor_id, sequence_number]} := {
                "sequence": sequence_number,
                "increment": increment
            }
            ent:violations{sensor_id} := ent:violation_messages{sensor_id}.reduce(function(violation, message) {
                message != null => violation + message{"increment"} | violation
            }, 0)
            ent:violation_counter{sensor_id} := ent:violation_messages{sensor_id}.reduce(function(violation, message) {
                message != null && message{"increment"} == 1 => violation + 1 | violation
            }, 0)
        }
    }

    rule set_sequence {
        select when gossip rumor
        pre {
            id_split = event:attr("MessageID").split(re#:#)
            message_head = id_split[0] + ":" + id_split[1]
            sequence_number = id_split[2].as("Number")
            sensor_id = event:attr("SensorID")
        }
        if (ent:sequences{ent:sensor_id} >< message_head && ent:sequences{[ent:sensor_id, message_head]} == sequence_number - 1) ||
            ((not (ent:sequences{ent:sensor_id} >< message_head)) && sequence_number == 0)
            then noop()
        fired {
            ent:sequences{[ent:sensor_id, message_head]} := sequence_number
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
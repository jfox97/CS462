ruleset temperature_store {
    meta {
      name "Temperature Store"
      author "Jason Fox"
      provides temperatures, threshold_violations, inrange_temperatures
      shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function() {
            ent:temperature_readings || []
        }

        threshold_violations = function() {
            ent:threshold_violations || []
        }

        inrange_temperatures = function() {
            temperature_readings = ent:temperature_readings || []
            threshold_violations = ent:threshold_violations || []
            temperature_readings.filter(function(x) {
                threshold_violations.none(function(y) {
                    x == y
                })
            })
        }
    }

    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attr("temperature")[0]{"temperatureF"}
            timestamp = event:attr("timestamp")
        }
        always {
            ent:temperature_readings := ent:temperature_readings.defaultsTo([])
            ent:temperature_readings := ent:temperature_readings.append({"temperature": temperature, "timestamp": timestamp})
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            temperature = event:attr("temperature")
            timestamp = event:attr("timestamp")
        }
        always {
            ent:threshold_violations := ent:threshold_violations.defaultsTo([])
            ent:threshold_violations := ent:threshold_violations.append({"temperature": temperature, "timestamp": timestamp})
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset
        always {
            ent:temperature_readings := []
            ent:threshold_violations := []
        }
    }
}
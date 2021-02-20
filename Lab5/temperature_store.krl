ruleset temperature_store {
 
    meta {
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function() {
            ent:all_temperatures.defaultsTo([])
        }

        threshold_violations = function() {
            ent:all_threshold_violations.defaultsTo([])
        }

        inrange_temperatures = function() {
            ent:all_temperatures.difference(ent:all_threshold_violations)
        }
    }

    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs{"temperature"}
            timestamp = event:attrs{"timestamp"}
        }

        always {
            ent:all_temperatures := ent:all_temperatures.defaultsTo([])
            ent:all_temperatures := ent:all_temperatures.append({"temperature": temperature, "timestamp": timestamp})
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            violation_temperature = event:attrs{"temperature"}
            timestamp = event:attrs{"timestamp"}
        }

        always {
            ent:all_threshold_violations := ent:all_threshold_violations.defaultsTo([])
            ent:all_threshold_violations := ent:all_threshold_violations.append({"temperature": violation_temperature, "timestamp": timestamp})
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset

        always {
            clear ent:all_temperatures
            clear ent:all_threshold_violations
        }
    }
}
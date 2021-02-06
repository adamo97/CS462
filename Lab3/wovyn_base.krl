ruleset wovyn_base {
    meta {
        use module twilio_api_module alias twil
            with
                apiKey = meta:rulesetConfig{"api_key"}
                sessionID = meta:rulesetConfig{"session_id"}
    }

    global {
        temperature_threshold = 60
        notification_number = "+16692654358"
        twil_number = "+12244124560"
    }

    // wovyn webhook
    // http://192.168.0.192:3000/sky/event/ckku6oh3g001euovqfq6y284x/temp/wovyn/heartbeat

    rule process_heartbeat {
        select when wovyn heartbeat where event:attrs{"genericThing"}
        pre {
            temperature = event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureF"}
            timestamp = time:now()
        }

        send_directive("data", {"temperatureF": temperature})
        fired {
            raise wovyn event "new_temperature_reading"
                attributes {"temperature": temperature, "timestamp": timestamp}
        }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs{"temperature"}.klog("find_high_temps")
        }

        if temperature > temperature_threshold then
            send_directive("temperature_violation", {"temperatureF": temperature, "threshold": temperature_threshold})

        fired {
            raise wovyn event "threshold_violation"
                attributes event:attrs
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs{"temperature"}.klog("threshold_notification")
        }
        twil:sendMessage(notification_number, twil_number, "Temperature violation: " + temperature + " over threshold of " + temperature_threshold)
    }
}
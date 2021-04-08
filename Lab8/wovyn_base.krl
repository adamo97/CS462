ruleset wovyn_base {
    meta {
        use module twilio_api_module alias twil
            with
                apiKey = meta:rulesetConfig{"api_key"}
                sessionID = meta:rulesetConfig{"session_id"}
        use module sensor_profile
        use module io.picolabs.subscription alias sub
        use module temperature_store
    }

    global {
        twil_number = "+12244124560"
    }

    // wovyn webhook
    // http://192.168.0.192:3000/sky/event/ckku6oh3g001euovqfq6y284x/temp/wovyn/heartbeat

    rule process_report_request {
        select when report request_received
        pre {
            temperatures = temperature_store:temperatures()
        }
        event:send(
            {
                "eci": event:attrs{"Rx"},
                "eid": "report_response",
                "domain": "report",
                "type": "response",
                "attrs": {"temperatures": temperatures, "Tx": event:attrs{"Tx"}, "correlation_id": event:attrs{"correlation_id"}}
            }
        )
    }

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
            temperature_threshold = sensor_profile:profile_data(){"threshold"}.defaultsTo(65)
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
        foreach sub:established("Rx_role", "sensor_collection") setting (subscription)
            event:send(
                {
                    "eci": subscription{"Tx"},
                    "eid": "threshold_violation",
                    "domain": "sensor_collection",
                    "type": "subscription_threshold_violation",
                    "attrs": event:attrs
                }
            )
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        always {
            raise wrangler event "pending_subscription_approval" attributes event:attrs
        }
    }
}
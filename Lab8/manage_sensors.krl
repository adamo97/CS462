ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias sub
        shares sensors, showChildren, getAllTemperatures, getAllOpenChannelIds, getTempReports
    }

    global {
        sensors = function() {
            sub:established("Rx_role", "sensor")
        }

        showChildren = function() {
            wrangler:children()
        }

        getOpenChannelId = function(v,n) {
            (ctx:query(v{"Tx"}, "io.picolabs.wrangler", "channels", {"tags":["open"]})).head(){"id"}
        }

        getAllOpenChannelIds = function() {
            sensors().map(getOpenChannelId).values()
        }

        getTemperature = function(v,n) {
            ctx:query(v{"Tx"}, "temperature_store", "temperatures")
        }

        getAllTemperatures = function() {
            sensors().map(getTemperature)
        }

        getTempReports = function() { 
            reports = ent:temp_reports.values()
            num_total_reports = reports.length().klog("num_reports")
            reports.slice(reports.length() - 5 >= 0 => reports.length() - 5 | 0, reports.length() - 1)
        }

        needed_ruleset_rids =
            {
                "twilio_api_module": {},
                "temperature_store": {},
                "sensor_profile": {},
                "wovyn_base": {},
                "io.picolabs.wovyn.emitter":{}
            }

        default_threshold = "70"
    }

    rule clear_temp_report {
        select when report empty
        always {
            ent:temp_reports := {}
        }
    }

    rule send_need_temp_report {
        select when report request
        foreach sensors() setting(sensor)
        pre {
            sensor_attrs = {"Rx": sensor{"Rx"}, "Tx": sensor{"Tx"}, "correlation_id": ent:correlation_id.defaultsTo(random:uuid())}
        }
        event:send(
            {
                "eci": sensor{"Tx"},
                "eid": "report_request",
                "domain": "report",
                "type": "request_received",
                "attrs": sensor_attrs
            }
        )
        fired {
            ent:correlation_id := random:uuid() on final
        }
    }

    rule receive_temp_report {
        select when report response
        pre {
            temperatures = event:attrs{"temperatures"}
            tx = event:attrs{"Tx"}
            correlation_id = event:attrs{"correlation_id"}
            report = ent:temp_reports{correlation_id}.defaultsTo({"temperature_sensors": sensors().length(), "responding": 0, "temperatures": []})
            updated_report = {"temperature_sensors": report["temperature_sensors"], "responding": report["responding"] + 1, "temperatures": report["temperatures"].append({"tx": tx, "temps": temperatures})}
        }
        always {
            ent:temp_reports{correlation_id} := updated_report
        }
    }

    rule register_new_sensor {
        select when sensor new_sensor
        pre {
            name = event:attrs{"name"}
            already_exists = ent:sensors >< name
        }

        if already_exists then
            send_directive("Name in use", {"name":name})
        notfired {
            raise wrangler event "new_child_request"
                attributes { "name": name, "backgroundColor": "#ff69b4", "rids":["temperature_store", "sensor_profile", "wovyn_base"] }
        }
    }

    rule store_new_sensor {
        select when wrangler new_child_created
        foreach needed_ruleset_rids setting (config, rid)
        pre {
          the_sensor = {"eci": event:attrs{"eci"}}
          sensor_name = event:attrs{"name"}
        }

        if sensor_name.klog("found sensor_name") then
            event:send(
                { "eci": the_sensor.get("eci"), 
                    "eid": "install-ruleset", // can be anything, used for correlation
                    "domain": "wrangler", "type": "install_ruleset_request",
                    "attrs": {
                    "absoluteURL": meta:rulesetURI,
                    "rid": rid,
                    "config": config,
                    "name": sensor_name
                    }
                }
            )
        fired {
          ent:sensors := ent:sensors.defaultsTo([]) on final
          ent:sensors{sensor_name} := the_sensor on final
          raise sensor event "install_subscription" attributes event:attrs on final
          raise sensor event "update_sensor_profile" attributes event:attrs on final
        }
    }

    rule install_subscription {
        select when sensor install_subscription
        pre {
            eci = event:attrs{"eci"}
            sensor_name = event:attrs{"name"}.klog("In install subscription")
        }

        always {
            raise wrangler event "subscription" attributes
                {
                    "name": sensor_name,
                    "Rx_role": "sensor",
                    "Tx_role": "sensor_collection",
                    "channel_type": "subscription",
                    "wellKnown_Tx": eci
                }
        }
    }

    rule update_sensor_profile {
        select when sensor update_sensor_profile
        pre {
            the_sensor = {"eci": event:attrs{"eci"}}
            sensor_name = event:attrs{"name"}
        }

        event:send(
            {
                "eci": the_sensor{"eci"},
                "eid": "set_profile",
                "domain": "sensor",
                "type": "profile_updated",
                "attrs": { "name": sensor_name, "threshold": default_threshold, "location": "some_location", "phone_number": "+16692654358" }
            }
        )

        fired {
            raise sensor event "install_open_channel"
                attributes event:attrs
        }
    }

    rule install_open_channel {
        select when sensor install_open_channel
        pre {
            the_sensor = {"eci": event:attrs{"eci"}}
            sensor_name = event:attrs{"name"}
        }

        event:send(
            {
                "eci": the_sensor{"eci"},
                "eid": "install_open_channel",
                "domain": "wrangler",
                "type": "new_channel_request",
                "attrs":
                    { "tags": ["open"],
                        "eventPolicy": { "allow":[{"domain": "*", "name": "*"}], "deny":[] },
                        "queryPolicy": { "allow": [ { "rid": "*", "name": "*" } ], "deny": [] }
                    }
            }
        )
    }

    rule introduce_foreign_sensor {
        select when sensor introduce_foreign_sensor
        pre {
            eci = event:attrs{"eci"}
            sensor_name = event:attrs{"name"}
            host = event:attrs{"host"}
        }

        always {
            raise wrangler event "subscription" attributes
                {
                    "name": sensor_name,
                    "Rx_role": "sensor",
                    "Tx_role": "sensor_collection",
                    "channel_type": "subscription",
                    "wellKnown_Tx": eci,
                    "Tx_host": host
                }
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        always {
            raise wrangler event "pending_subscription_approval" attributes event:attrs
        }
    }

    rule subscription_threshold_violation {
        select when sensor_collection subscription_threshold_violation
        always {
            raise sensor_collection_profile event  "send_message" attributes {"message": "Temperature violation: " + event:attrs{"temperature"} + " over threshold of " + event:attrs{"threshold"}}
        }
    }

    rule delete_unneeded_sensor {
        select when sensor unneeded_sensor
        pre {
            name = event:attrs{"name"}
            exists = ent:sensors >< name
            sensor = ent:sensors{name}
        }

        if not exists then
            send_directive("Sensor Does Not Exist", name)
        notfired {
            raise wrangler event "child_deletion_request"
                attributes { "eci":sensor{"eci"} }
            ent:sensors := ent:sensors.delete([name])
        }
    }

    rule clearAllSensors {
        select when sensor clear_sensors
        foreach ent:sensors setting (sensor)
        always {
            raise wrangler event "child_deletion_request"
                attributes { "eci":sensor{"eci"} }
            ent:sensors := {} on final
        }
    }
}
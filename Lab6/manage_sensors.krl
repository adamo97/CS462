ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        shares sensors, showChildren, getAllTemperatures, getAllOpenChannelIds
    }

    global {
        sensors = function() {
            ent:sensors.defaultsTo([])
        }

        showChildren = function() {
            wrangler:children()
        }

        getOpenChannelId = function(v,n) {
            (ctx:query(v{"eci"}, "io.picolabs.wrangler", "channels", {"tags":["open"]})).head(){"id"}
        }

        getAllOpenChannelIds = function() {
            sensors().map(getOpenChannelId).values()
        }

        getTemperature = function(v,n) {
            ctx:query(v{"eci"}, "temperature_store", "temperatures")
        }

        getAllTemperatures = function() {
            sensors().map(getTemperature)
        }

        needed_ruleset_rids =
            {
                "twilio_api_module": {},
                "twilio_app": {"api_key":"acf203927fe7a0fe04bb8a72c2f13035","session_id":"AC2f03d00fe6945ebc7b4d7c7d50eafa88"},
                "temperature_store": {},
                "sensor_profile": {},
                "wovyn_base": {},
                "io.picolabs.wovyn.emitter":{}
            }

        default_threshold = "70"
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
          raise sensor event "update_sensor_profile" attributes event:attrs on final
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
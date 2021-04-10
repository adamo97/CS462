ruleset gossip_protocol {
    meta {
        use module io.picolabs.subscription alias sub
        shares state, seen_messages, smart_tracker
    }

    global {
        state = function() {
            { "state": ent:state, "period": ent:period }
        }

        seen_messages = function() {
            ent:seen_messages
        }

        smart_tracker = function() {
            ent:smart_tracker
        }

        getPeer = function() {
            subscribers = sub:established("Rx_role", "node")
            
            smart_tracker = ent:smart_tracker.filter(function(v,k) {k != meta:picoId})
            needy_subs = smart_tracker.filter(function(v,k) {
                mm = missingMessages(v).klog("mm")
                mm.length() > 0
            }).klog("needy_subs")
            // should I give higher priority to subs who know the least?

            random_tx = needy_subs.keys()[random:integer(needy_subs.length() - 1)]
            random_subscriber = subscribers.filter(function(sub) {sub{"Tx"} == random_tx})[0]

            needy_subs.length() > 0 => random_subscriber.klog("random_sub") | (subscribers[random:integer(subscribers.length() - 1)]).klog("default_sub")
        }

        prepareMessage = function(subscriber) {
            r_int = random:integer(1)
            r_int == 0 => prepareRumor(subscriber) | prepareSeen()
        }

        prepareRumor = function(sub) {
            missing_messages = missingMessages(ent:smart_tracker{sub{"Tx"}})
            message = {
                "type": "rumor",
                "message": missing_messages[0].isnull() => ent:seen_messages[0] | missing_messages[0]
            }
            message
        }

        prepareSeen = function() {
            {
                "type": "seen",
                "message": ent:smart_tracker{meta:picoId}
            }
        }

        picoIDFromMessageID = function(message_id) {
            message_id.split(re#:#)[0]
        }

        sequenceNumberFromMessageID = function(message_id) {
            message_id.split(re#:#)[1].as("Number")
        }

        missingMessages = function(seen_message) {
            seen_messages = ent:seen_messages 
            seen_messages.filter(function(mes) {
                message_sender_id = picoIDFromMessageID(mes{"MessageID"})
                seen_message{message_sender_id}.isnull() || seen_message{message_sender_id} < sequenceNumberFromMessageID(mes{"MessageID"}) => true | false
            }).sort(
                function(mes_1, mes_2) {
                    s1 = sequenceNumberFromMessageID(mes_1{"MessageID"})
                    s2 = sequenceNumberFromMessageID(mes_2{"MessageID"})
                    s1 < s2 => -1 |
                    s1 == s2 => 0 |
                                1
                }
            )
        }

        generateMessage = function(temperature, timestamp) {
            {
                "MessageID": meta:picoId + ":" + ent:sequence_number,
                "SensorID": meta:picoId,
                "Temperature": temperature,
                "Timestamp": timestamp
            }
        }
    }

    rule initialize {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        always {
            ent:period := 5
            ent:sequence_number := 0
            ent:smart_tracker := {}.put([meta:picoId], {})
            ent:seen_messages := []
            ent:state := "on"

            raise gossip event "heartbeat"
        }
    }

    rule gossip_update_state {
        select when gossip update_state
        pre {
            new_state = event:attrs{"state"}
            state = new_state == "on" || new_state == "On" => "on" | "off"
        }
        if state == "on" then
        noop()
        fired {
            raise gossip event "heartbeat"
        }
        finally {
            ent:state := state
        }
    }

    rule update_period {
        select when gossip update_period
        always {
            ent:period := event:attrs{"period"}.defaultsTo(ent:period)
        }
    }

    rule gossip_heartbeat {
        select when gossip heartbeat
        always {
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:period})
        }
    }

    rule gossip_heartbeat_tick {
        select when gossip heartbeat where ent:state == "on"
        pre {
            subscriber = getPeer().klog("getPeer")
            m = prepareMessage(subscriber).klog("preparedMessage")
        }

        if subscriber.isnull() || m.isnull() then
        noop()
        notfired {
            raise gossip event "send_rumor" attributes { "subscriber": subscriber, "message": m{"message"}} if m{"type"} == "rumor"
            raise gossip event "send_seen" attributes { "subscriber": subscriber, "message": m{"message"}} if m{"type"} == "seen"
        }    
    }

    rule gossip_send_rumor {
        select when gossip send_rumor
        pre {
            subscriber = event:attrs{"subscriber"}
            message = event:attrs{"message"}
            pico_id = picoIDFromMessageID(message{"MessageID"})
            sequence_number = sequenceNumberFromMessageID(message{"MessageID"})
        }
        event:send(
            {
                "eci": subscriber{"Tx"},
                "eid": "send_rumor",
                "domain": "gossip",
                "type": "rumor",
                "attrs": message
            }
        )

        //update
        always {
            ent:smart_tracker := ent:smart_tracker.put([subscriber{"Tx"}, pico_id], sequence_number)
            if ((ent:smart_tracker{subscriber{"Tx"}}{pico_id}.isnull() && sequence_number == 0) || ent:smart_tracker{subscriber{"Tx"}}{pico_id} == sequence_number - 1).klog("rumor_added_to_tracker")
            // if it is the first message or it is the next message the sensor needs
        }
    }

    rule gossip_send_seen {
        select when gossip send_seen
        event:send(
            {
                "eci": event:attrs{"subscriber"}{"Tx"},
                "eid": "send_seen",
                "domain": "gossip",
                "type": "seen",
                "attrs": {"Rx": event:attrs{"subscriber"}{"Rx"}, "message": event:attrs{"message"}}
            }
        )
    }

    rule gossip_rumor {
        select when gossip rumor where ent:state == "on"
        pre {
            sender_id = picoIDFromMessageID(event:attrs{"MessageID"})
            sender_sequence_num = sequenceNumberFromMessageID(event:attrs{"MessageID"}).klog("sender_sequence_num")
            seen_messages = ent:seen_messages
        }
        //store rumor info if not seen before
        if sender_id.isnull() || sender_sequence_num.isnull() || event:attrs.isnull() then
            noop()
        notfired {
            ent:seen_messages := seen_messages.append(event:attrs)
            if seen_messages.filter(function(m) {m{"MessageID"} == event:attrs{"MessageID"}}).length() == 0
            ent:smart_tracker{meta:picoId} := ent:smart_tracker{meta:picoId}.put([sender_id], sender_sequence_num)
            if ((ent:smart_tracker{meta:picoId}{sender_id}).klog("current_sequence_num") == sender_sequence_num - 1).klog("gr_smart_1") || (ent:smart_tracker{meta:picoId}{sender_id}.isnull() && sender_sequence_num == 0).klog("gr_smart_2")
        }
    }

    rule gossip_seen {
        select when gossip seen where ent:state == "on"
        foreach missingMessages(event:attrs{"message"}) setting (missing_message)
        event:send(
            {
                "eci": event:attrs{"Rx"},
                "eid": "seen_response",
                "domain": "gossip",
                "type": "rumor",
                "attrs": missing_message
            }
        )
        always {
            ent:smart_tracker := ent:smart_tracker.put([event:attrs{"Rx"}], (event:attrs{"message"}).klog("seen_message"))
        }
    }

    rule new_temperature {
        select when wovyn new_temperature_reading
        always {
            ent:seen_messages := ent:seen_messages.append(generateMessage(event:attrs{"temperature"}, event:attrs{"timestamp"}))
            ent:smart_tracker := ent:smart_tracker.put([meta:picoId, meta:picoId], ent:sequence_number)
            ent:sequence_number := ent:sequence_number + 1
        }
    }

    rule add_sub_to_tracker {
        select when wrangler subscription_added
        always {
            ent:smart_tracker{event:attrs{"Tx"}} := {} if event:attrs{"Rx_role"} == "node"
        }
    }
}
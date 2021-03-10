ruleset sensor_collection_profile {
    meta {
        use module twilio_api_module alias twil
            with
                apiKey = meta:rulesetConfig{"api_key"}
                sessionID = meta:rulesetConfig{"session_id"}
    }

    global {
        twilio_number = "+12244124560"
        default_number = "+16692654358"
    }

    rule updated_sensor_profile {
        select when sensor profile_updated
        always {
            ent:phone_number := event:attrs{"phone_number"}.defaultsTo(ent:phone_number)
        }
    }

    rule send_sms {
        select when sensor_collection_profile send_message
        pre {
            phone_number = ent:phone_number.defaultsTo(default_number)
        }

        twil:sendMessage(phone_number, twilio_number, event:attrs{"message"})
    }
}
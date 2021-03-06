ruleset twilio_app {
    meta {
        use module twilio_api_module alias twil
            with
                apiKey = meta:rulesetConfig{"api_key"}
                sessionID = meta:rulesetConfig{"session_id"}
    }

    rule send_message {
        select when send new_message
            twil:sendMessage(event:attrs{"to"}, event:attrs{"from"}, event:attrs{"message"})
    }

    rule messages {
        select when get message_log
        pre {
            messages = twil:messages(event:attrs{"to"}, event:attrs{"from"}, event:attrs{"page_size"})
        }
        send_directive("messages", { "messages": messages})
    }
}
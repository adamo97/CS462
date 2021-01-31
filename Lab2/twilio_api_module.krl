ruleset twilio_api_module {
    meta {
      configure using
        apiKey = ""
        sessionID = ""
      
      provides sendMessage, messages
    }

    global {
        sendMessage = defaction(_to, _from, _body) {
          http:post(<<https://#{sessionID}:#{apiKey}@api.twilio.com/2010-04-01/Accounts/#{sessionID}/Messages.json>>, form = {"To":_to, "From":_from, "Body":_body})
        }

        messages = function(_to, _from, page_size) {
          q_init = {"To":_to, "From":_from, "PageSize":page_size}
          query_string = (q_init.filter(function(v,k){not v.isnull() && v != ""})).klog("message log")
          
          response = http:get(<<https://#{sessionID}:#{apiKey}@api.twilio.com/2010-04-01/Accounts/#{sessionID}/Messages.json>>, qs = query_string);
          response{"content"}.decode(){"messages"}
        }
    }
}
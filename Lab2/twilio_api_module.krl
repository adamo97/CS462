ruleset twilio_api_module {
    meta {
      configure using
        apiKey = ""
        sessionID = ""
      
      provides sendMessage
    }

    global {
        base_url = "https://api.twilio.com"

        sendMessage = defaction(_to, _from, _body) {
          http:post(<<#{base_url}/2010-04-01/Accounts/#{sessionID}/Messages>>, form = {"To" : _to, "From" : _from, "Body": _body}) setting(response)
          return response
        }
    }
}
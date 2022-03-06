ruleset sensor_manager_profile {
    meta {
        use module com.twilio.sdk alias twilio
        with
            accountSID = meta:rulesetConfig{"account_sid"}
            authToken = meta:rulesetConfig{"auth_token"}
            messagingServiceSID = meta:rulesetConfig{"messaging_service_sid"}
        shares phone_number
    }

    global {
        phone_number = function() {
            ent:phone_number
        }
    }

    rule profile_updated {
        select when manager profile_updated
        pre {
            phone_number = event:attr("phone_number")
        }
        always {
            ent:phone_number := phone_number
        }
    }

    rule send_message {
        select when manager send_message
        pre {
            message = event:attr("message")
        }
        twilio:sendMessage(ent:phone_number, message)
    }
}
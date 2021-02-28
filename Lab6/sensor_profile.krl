ruleset sensor_profile {
    meta {
        shares profile_data
        provides profile_data
    }

    global {
        profile_data = function() {
            { 
                "location": ent:location.isnull() || ent:location == "" => "some_location" | ent:location,
                "name": ent:name.isnull() || ent:name == "" => "some_name" | ent:name,
                "threshold": ent:threshold.isnull() || ent:threshold == "" => "65" | ent:threshold,
                "phone_number": ent:phone_number.isnull() || ent:phone_number == "" => "+16692654358" | ent:phone_number
            }
        }
    }

    rule profile_update {
        select when sensor profile_updated
        pre {
            sensor_location = event:attrs{"location"}
            sensor_name = event:attrs{"name"}
            sensor_threshold = event:attrs{"threshold"}
            sensor_phone_number = event:attrs{"phone_number"}
        }

        always {
            ent:location := sensor_location
            ent:name := sensor_name
            ent:threshold := sensor_threshold
            ent:phone_number := sensor_phone_number
        }
    }
}
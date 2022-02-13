const eventBaseURL = "http://localhost:3000/sky/event/ckzk5hvkp02jcqhoi77fg6qeu/";
const queryBaseURL = "http://localhost:3000/sky/cloud/ckzk5hvkp02jcqhoi77fg6qeu/sensor_profile/";

async function getSensorProfile() {
    const url = queryBaseURL + "profile";
    const response = await fetch(url);
    const profile = await response.json();

    $("#location").val(profile.location);
    $("#name").val(profile.name);
    $("#threshold").val(profile.threshold);
    $("#phone").val(profile.phone_number);
}

$(() => {
    $("#profile_form").submit(e => {
        e.preventDefault();
        $.ajax({
            url: eventBaseURL + "none/sensor/profile_updated",
            type: 'POST',
            data: $("#profile_form").serialize(),
            success: () => {
                $("#status").text("Profile submitted successfully");
            },
            fail: () => {
                $("#status").text("Error occurred");
            } 
        })
    });

    getSensorProfile();
});
const baseURL = "http://localhost:3000/sky/cloud/ckzk37ppn002dqhoi51hy13nq/temperature_store/";

async function queryPico(functionName) {
    var url = baseURL + functionName;
    var response = await fetch(url);
    return await response.json()
}

async function setTempData() {
    var allTemps = (await queryPico("temperatures")).reverse();
    var thresholdViolations = (await queryPico("threshold_violations")).reverse();

    var currentTemp = allTemps[0];
    $("#current_temp").text(currentTemp.temperature);
    $("#current_time").text(currentTemp.timestamp);

    $("#threshold_violations").empty();
    
    for (const temp of thresholdViolations.slice(0, 10)) {
        $("#threshold_violations").append("<p>" + temp.temperature + " degrees Fahrenheit at " + temp.timestamp + "</p>");
    }

    $("#recent_results").empty();
    for (const temp of allTemps.slice(0, 10)) {
        $("#recent_results").append("<p>" + temp.temperature + " degrees Fahrenheit at " + temp.timestamp + "</p>");
    }
}

$(async () => {
    await setTempData();

    setInterval(setTempData, 5000);
});
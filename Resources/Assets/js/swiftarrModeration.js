//
for (let btn of document.querySelectorAll('[data-action]')) {
	let action = btn.dataset.action;
	if (action == "handleReports") {
		btn.addEventListener("click", handleAllReportsAction);
	}
	else if (action == "closeReports") {
		btn.addEventListener("click", closeAllReportsAction);
	}
	else if (action == "setModState") {
		btn.addEventListener("click", setModerationStateAction);
	}
}

function handleAllReportsAction() {
	let reportid = event.target.dataset.reportid;
	let req = new Request("/reports/" + reportid + "/handle", { method: 'POST' });
	let errorDiv = document.getElementById("ModerateContentErrorAlert");
	fetch(req).then(function(response) {
		if (response.ok) {
			location.reload();
		}
		else {
			response.json().then( data => {
				errorDiv.innerHTML = "<b>Error:</b> " + data.reason
			});
		}
	}).catch(error => {
		errorDiv.innerHTML = "<b>Error:</b> " + error;
	});
}

function closeAllReportsAction() {
	let reportid = event.target.dataset.reportid;
	let req = new Request("/reports/" + reportid + "/close", { method: 'POST' });
	fetch(req).then(function(response) {
		if (response.ok) {
			location.reload();
		}
		else {
			console.log(response);
		}
	})
}

function setModerationStateAction() {
	let newstate = event.target.dataset.newstate;
	let reportableID = event.target.closest('[data-reportableid]').dataset.reportableid;
	let reportableType = event.target.closest('[data-reportabletype]').dataset.reportabletype;
	let errorDiv = document.getElementById("ModerateContentErrorAlert");
	let req = new Request("/" + reportableType + "/" + reportableID + "/setstate/" + newstate, { method: 'POST' });
	fetch(req).then(function(response) {
		if (response.ok) {
			location.reload();
		}
		else {
			response.json().then( data => {
				errorDiv.innerHTML = "<b>Error:</b> " + response.status + " " + data.reason;
				errorDiv.classList.remove("d-none");
			});
		}
	}).catch(error => {
		errorDiv.innerHTML = "<b>Error:</b> " + error;
		errorDiv.classList.remove("d-none");
	});
}

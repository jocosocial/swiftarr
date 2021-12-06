// Setup handlers at page load time
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
	else if (action == "setAccessLevel") {
		btn.addEventListener("click", setUserAccessLevelAction);
	}
	else if (action == "clearTempBan") {
		btn.addEventListener("click", clearTempQuarantineAction);
	}
	else if (action == "setCategory") {
		btn.addEventListener("click", setForumCategoryAction);
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

function setUserAccessLevelAction() {
	let newstate = event.target.dataset.newstate;
	let userID = event.target.closest('[data-userid]').dataset.userid;
	let errorDiv = document.getElementById("ModerateContentErrorAlert");
	let req = new Request("/moderate/user/" + userID + "/setaccesslevel/" + newstate, { method: 'POST' });
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

function clearTempQuarantineAction() {
	let path = event.target.dataset.path
	if (path == null) {
		return;
	}
	let req = new Request(path, { method: 'POST' });
	fetch(req).then(function(response) {
		if (response.ok) {
			location.reload();
		}
		else {
			console.log(response);
		}
	})
}

function setForumCategoryAction() {
	let newCategory = event.target.dataset.newcategory;
	let forumID = event.target.closest('[data-reportableid]').dataset.reportableid;
	let req = new Request("/forum/" + forumID + "/setcategory/" + newCategory, { method: 'POST' });
	fetch(req).then(function(response) {
		if (response.ok) {
			location.reload();
		}
		else {
			console.log(response);
		}
	})
}

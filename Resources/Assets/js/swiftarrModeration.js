//
for (let btn of document.querySelectorAll('[data-action]')) {
	let action = btn.dataset.action;
	if (action == "handleReports") {
		btn.addEventListener("click", handleAllReportsAction);
	}
	else if (action == "closeReports") {
		btn.addEventListener("click", closeAllReportsAction);
	}
}

function handleAllReportsAction() {
	
//	let req = new Request("/reports/handle", { method: 'POST' });
//	fetch(req).then(function(response) {
//	
//	}
}

function closeAllReportsAction() {
	console.log("close reports");
}

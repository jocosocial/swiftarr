// Make the like/love/laugh buttons post their actions when tapped.
var likeButtons = document.querySelectorAll('[data-action]');
for (let btn of likeButtons) {
	btn.addEventListener("click", likeAction);
}

function likeAction() {
	let twarrtid = event.target.closest('[data-twarrtid]').getAttribute('data-twarrtid');
	let tappedButton = event.target;
	var path = 'tweets/' + twarrtid + '/';

	if (!tappedButton.checked) {
		path = path + "unreact";
	}
	else {
		path = path + tappedButton.getAttribute("data-action");
	}
		
	let buttons = tappedButton.parentElement.querySelectorAll("input");
	setLikeButtonsState(buttons, tappedButton, false);

	let req = new Request(path, { method: 'POST' });
	fetch(req).then(function(response) {
	  let errorDiv = tappedButton.closest('[data-twarrtid]').querySelector('[data-purpose="errordisplay"]');
	  if (response.ok) {
		errorDiv.innerHTML = "";
	  }
	  else {
	  	errorDiv.innerHTML = "Could not post reaction";
	  }
	  setTimeout(() => {
		setLikeButtonsState(buttons, tappedButton, true);
	  }, 1000)
	}).catch(error => {
	  tappedButton.closest('[data-twarrtid]').querySelector('[data-purpose="errordisplay"]').innerHTML = "Could not post reaction";
	  setLikeButtonsState(buttons, tappedButton, true);
	});
}

function setLikeButtonsState(buttons, tappedButton, state) {
	let spanElem = tappedButton.parentElement.querySelector("label[for='" + tappedButton.id + "'] > .spinner-border");
	if (state) {
		for (let btn of buttons) {
			btn.disabled = false;
		}
		if (spanElem !== null) spanElem.classList.add("d-none");
	}
	else {
		for (let btn of buttons) {
			btn.disabled = true;
			if (btn.checked && btn != tappedButton) {
				btn.checked = false;
			}
		}
		if (spanElem !== null) spanElem.classList.remove("d-none");
	}
}


// Make every twarrt expand when first clicked, showing the previously hidden action bar.
var twarrtlistItems = document.querySelectorAll('[data-twarrtid]');
for (let twarrt of twarrtlistItems) {
	twarrt.addEventListener("click", showActionBar);
}
function showActionBar() {
	let actionbar = event.currentTarget.querySelector('[data-label="actionbar"]');
	var bsCollapse = new bootstrap.Collapse(actionbar, { toggle: false }).show()
}


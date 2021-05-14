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

// Handlers for the parts of messagePostForm.leaf
var imageUploadInputs = document.querySelectorAll('.image-upload-input');
for (let input of imageUploadInputs) {
	updatePhotoCardState(input.closest('.card'));
	input.addEventListener("change", function() { updatePhotoCardState(event.target.closest('.card')); })
}
function updatePhotoCardState(cardElement) {
	let imgElem = cardElement.querySelector('img');
	let noImgElem = cardElement.querySelector('.no-image-marker');
	let fileInputElem = cardElement.querySelector('.image-upload-input');
	let hiddenFormElem = cardElement.querySelector('input[type="hidden"]');
	let imageSwapButton = cardElement.querySelector('.twitarr-image-swap');
	let imageRemoveButton = cardElement.querySelector('.twitarr-image-remove');
	let imageVisible = true;
	if (fileInputElem.files.length > 0) {
		imgElem.src = window.URL.createObjectURL(fileInputElem.files[0]);
		imgElem.style.display = "block";
		noImgElem.style.display = "none";
		hiddenFormElem.value = "";
	}
	else if (hiddenFormElem.value) {
		imgElem.src = "/api/v3/image/thumb/" + hiddenFormElem.value;
		imgElem.style.display = "block";
		noImgElem.style.display = "none";
	}
	else {
		imgElem.style.display = "none";
		noImgElem.style.display = "block";
		imageRemoveButton.disabled = true
		imageVisible = false;
	}
	if (imageSwapButton) {
		imageSwapButton.disabled = !imageVisible;
	}
	imageRemoveButton.disabled = !imageVisible;
	let nextCard = cardElement.nextElementSibling;
	if (nextCard != null) {
		nextCard.style.display = imgElem.style.display;
	}
}
var imageRemoveButtons = document.querySelectorAll('.twitarr-image-remove');
for (let btn of imageRemoveButtons) {
	btn.addEventListener("click", removeUploadImage);
}
function removeUploadImage() {
	let cardElement = event.target.closest('.card');
	let nextCard = cardElement;
	while (nextCard = cardElement.nextElementSibling) {
		cardElement.querySelector('.image-upload-input').files = nextCard.querySelector('.image-upload-input').files;
		cardElement.querySelector('input[type="hidden"]').value = nextCard.querySelector('input[type="hidden"]').value;
		updatePhotoCardState(cardElement);
		cardElement = nextCard;
	}
	let lastCard = cardElement.parentElement.lastElementChild;
	lastCard.querySelector('.image-upload-input').value = null
	lastCard.querySelector('input[type="hidden"]').value = "";
	updatePhotoCardState(lastCard);
}
var imageSwapButtons = document.querySelectorAll('.twitarr-image-swap');
for (let btn of imageSwapButtons) {
	btn.addEventListener("click", swapUploadImage);
}
function swapUploadImage() {
	let cardElement = event.target.closest('.card');
	let prevCard = cardElement.previousElementSibling;
	let curFiles = cardElement.querySelector('.image-upload-input').files;
	let curServerFile = cardElement.querySelector('input[type="hidden"]').value
	cardElement.querySelector('.image-upload-input').files = prevCard.querySelector('.image-upload-input').files;
	cardElement.querySelector('input[type="hidden"]').value = prevCard.querySelector('input[type="hidden"]').value;
	prevCard.querySelector('.image-upload-input').files = curFiles;
	prevCard.querySelector('input[type="hidden"]').value = curServerFile;
	updatePhotoCardState(prevCard);
	updatePhotoCardState(cardElement);
}
for (let form of document.querySelectorAll('form.ajax')) {
	form.addEventListener("submit", function(event) { submitAJAXForm(form, event); });
}
function submitAJAXForm(formElement, event) {
    event.preventDefault();
	var req = new XMLHttpRequest();
	req.onload = function() {
		if (this.status < 300) {
			location.reload();
		}
		else {
			var data = JSON.parse(this.responseText);
			let alertElement = formElement.querySelector('.alert');
			alertElement.innerHTML = "<b>Error:</b> " + data.reason;
			alertElement.style.display = "block"
		}
	}
	req.onerror = function() {
		let alertElement = formElement.querySelector('.alert');
		alertElement.innerHTML = "<b>Error:</b> " + this.statusText;
		alertElement.style.display = "block"
	}
	req.open("post", formElement.action);
    req.send(new FormData(formElement));
}

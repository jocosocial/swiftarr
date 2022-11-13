import("/js/bootstrap.bundle.js");

// Make buttons with data-action properties post their actions when tapped.
for (let btn of document.querySelectorAll('[data-action]')) {
	let action = btn.dataset.action;
	switch (action) {
		case "laugh":
		case "like":
		case "love":
		case "favorite":
		case "follow":
		case "reload":
		case "block":
		case "mute": 
		case "unblock": 
		case "unmute":
		case "alertWordDelete":
		case "muteWordDelete":
		case "redirect":
			btn.addEventListener("click", spinnerButtonAction); 
			break;
		case "delete": btn.addEventListener("click", deleteAction); break;
		case "eventFiltersChanged": btn.addEventListener("click", filterEvents); break;
		case "filterEventType": btn.addEventListener("click", eventFilterDropdownTappedAction); break;
		case "eventScrollToNow": btn.addEventListener("click", soonButtonTappedAction); break;
		case "filterFezDay": 
			dropdownButtonSetup(btn); 
			btn.addEventListener("click", fezDayFilterDropdownTappedAction);
			break;
		case "filterFezType":
			dropdownButtonSetup(btn); 
			btn.addEventListener("click", fezTypeFilterDropdownTappedAction);
			break;
	}
}

// Updates button state for buttons that perform a data-action
function setActionButtonsState(tappedButton, state) {
	if (!tappedButton) { return }
	let spinnerElem = tappedButton.labels[0]?.querySelector(".spinner-border") ??
			 tappedButton.querySelector(".spinner-border");
	if (state) {
		setTimeout(() => {
			for (let btn of tappedButton.parentElement.children) {
				btn.disabled = false;
			}
			spinnerElem?.classList.add("d-none");
		}, 1000);
	}
	else {
		for (let btn of tappedButton.parentElement.children) {
			btn.disabled = true;
			if (btn.checked && btn != tappedButton) {
				btn.checked = false;
			}
		}
		spinnerElem?.classList.remove("d-none");
	}
}

// Button handler for buttons that POST on click, spinner while processing, reload/redirect on completion, and display errors inline.
// on Button: data-actionpath="/path/to/POST/to" 
//		data-istoggle="true if it toggles via POST/DELETE of its actionPath"
// 		data-errordiv="id"
// on error div: class="d-none"
// in error div: <span class="errorText"></span> 
async function spinnerButtonAction() {
	let tappedButton = event.target;
	let path = tappedButton.dataset.actionpath;
	let actionStr = 'POST'
	if (tappedButton.dataset.istoggle == "true" && !tappedButton.checked) {
		actionStr = 'DELETE';
	}
	let req = new Request(path, { method: actionStr });
	let errorDiv = document.getElementById(tappedButton.dataset.errordiv);
	errorDiv?.classList.add("d-none")
	setActionButtonsState(tappedButton, false);
	try {
		var response = await fetch(req);
		if (response.ok) {
			// A console message is generated "Fetch failed loading" for operations that
			// return no content (such as 201 and 204). To silence this we pretend to care
			// about the output so that the message is not eroniously interpreted as a problem.
			// https://stackoverflow.com/questions/57477805/why-do-i-get-fetch-failed-loading-when-it-actually-worked
			await response.text();

			switch(tappedButton.dataset.action) {
				case "like": 
				case "laugh": 
				case "love": 
					let postElement = tappedButton.closest('[data-postid]');
					updateLikeCounts(postElement);
					break;
				case "follow":
					tappedButton.closest('[data-eventfavorite]').dataset.eventfavorite = tappedButton.checked ? "true": "false";
					break;
				case "reload":
					location.reload();
					break;
				case "redirect": 
					let newLoc = tappedButton.dataset.successpath;
					if (newLoc != null) {
						window.location.replace(newLoc);
					}
					else {
						window.location.relace("/");
					}
					break;
				case "block":
				case "mute":
					window.location.href = "/";		// Once blocked, can't see profile anymore.
					break;
				case "unblock": acknowledgeRemovalAction(tappedButton, "unblocked"); break;
				case "unmute": acknowledgeRemovalAction(tappedButton, "unmuted"); break;
				case "alertWordDelete": acknowledgeRemovalAction(tappedButton, "removed"); break;
				case "muteWordDelete": acknowledgeRemovalAction(tappedButton, "removed"); break;
			}
		}
		else {
			let responseJson = await response.json();
			throw responseJson.reason; 
		}
	} catch (error) {
		if (tappedButton.dataset.istoggle == "true") {
			tappedButton.checked = !tappedButton.checked;
		}
		let errorSpan = errorDiv?.querySelector(".errortext");
		if (errorSpan) { 
			errorSpan.innerText = error; 
		}
		errorDiv?.classList.remove("d-none");
	} finally {
		if (tappedButton && tappedButton.parentNode) {
			setActionButtonsState(tappedButton, true);
		}
	}
}
function acknowledgeRemovalAction(btn, str) {
	let italicElem = document.createElement('i');
	italicElem.append(document.createTextNode(str));
	btn.replaceWith(italicElem);
	btn = null;
}

for (let modal of document.querySelectorAll('.modal')) {
	modal.addEventListener('show.bs.modal', event => {
		modal.querySelector('.error-display')?.classList.add("d-none");
	});
}

// When a Delete Modal is shown, stash the ID of the thing being deleted in the Delete btn. 
document.getElementById('deleteModal')?.addEventListener('show.bs.modal', function(event) {
	let postElem = event.relatedTarget.closest('[data-postid]');
	let deleteBtn = event.target.querySelector('[data-delete-postid]');
	deleteBtn.setAttribute('data-delete-postid', postElem.dataset.postid);
})

// Deletes forums, forumposts, tweets, and fez posts. Delete btn handler inside Delete Modal.
async function deleteAction() {
	let postid = event.target.dataset.deletePostid;
	let deleteType = event.target.dataset.deleteType;
	let modal = event.target.closest('.modal');
	let path = "/" + deleteType + "/" + postid + "/delete";
	let req = new Request(path, { method: 'POST' });
	try {
		var response = await fetch(req);
		if (response.ok) {
			bootstrap.Modal.getInstance(modal).hide()
			let deletedPost = document.querySelector('li[data-postid="' + postid + '"]');
			if (deletedPost != null) {
				deletedPost.remove()
			}
			else {
				location.reload();
			}	
		}
		else {
			let responseJson = await response.json();
			throw responseJson.reason; 
		}
	}
	catch (error) {
		let errorSpan = modal?.querySelector(".errortext");
		if (errorSpan) { 
			errorSpan.innerText = error; 
		}
		modal?.querySelector(".error-display")?.classList.remove("d-none");
	}
}

// Make every post expand when first clicked, showing the previously hidden action bar.
for (let posElement of document.querySelectorAll('.has-action-bar')) {
	posElement.addEventListener("click", showActionBar);
}
function showActionBar() {
	let actionBar = event.currentTarget.querySelector('[data-label="actionbar"]');
	if (actionBar && !actionBar.classList.contains("show")) {
		var bsCollapse = new bootstrap.Collapse(actionBar, { toggle: false }).show();
		updateLikeCounts(event.currentTarget);
	}
}
// When a post is expanded, get like count details and update counts.
function updateLikeCounts(postElement) {
	let listType = postElement.closest('ul')?.dataset.listtype;
	let postid = postElement.dataset.postid;
	if (!listType || !postid) return;
	fetch("/" + listType + "/" + postid + "/details")
			.then(response => response.json())
			.then(jsonStruct => {
		let actionBar = postElement.querySelector('[data-label="actionbar"]');
		if (jsonStruct.laughs) { 
			let laughspan = actionBar.querySelector('.laughtext');
			if (laughspan) {
				laughspan.textContent = (jsonStruct.laughs.length > 0 ? "\xa0\xa0" + jsonStruct.laughs.length : "");
			}
		}
		if (jsonStruct.likes) { 
			let likespan = actionBar.querySelector('.liketext');
			if (likespan) {
				likespan.textContent = (jsonStruct.likes.length > 0 ? "\xa0\xa0" + jsonStruct.likes.length : "");
			}
		}
		if (jsonStruct.loves) { 
			let lovespan = actionBar.querySelector('.lovetext');
			if (lovespan) {
				lovespan.textContent = (jsonStruct.loves.length > 0 ? "\xa0\xa0" + jsonStruct.loves.length : "");
			}
		}
	});
}

function dropdownButtonSetup(menuItemBtn) {
	if (menuItemBtn.classList.contains("active")) {
		let dropdownBtn = menuItemBtn.closest('.dropdown').querySelector('[data-bs-toggle="dropdown"]');
		dropdownBtn.innerHTML = menuItemBtn.innerHTML;
		dropdownBtn.dataset.selected = menuItemBtn.dataset.selection;
	}
}

function updateDropdownButton(menuItemBtn) {
	let dropdownBtn = menuItemBtn.closest('.dropdown').querySelector('[data-bs-toggle="dropdown"]');
	dropdownBtn.innerHTML = menuItemBtn.innerHTML;
	dropdownBtn.dataset.selected = menuItemBtn.dataset.selection;
	for (menuItem of dropdownBtn.parentElement.querySelectorAll('[data-action]')) {
		menuItem.classList.remove("active");
	}
	menuItemBtn.classList.add("active");
}

// MARK: - messagePostForm Handlers

// Updates the char/line count labels as text input fields change
for (let input of document.querySelectorAll('[data-lengthlabel]')) {
	updateInputFieldCharCounts(input);
	input.addEventListener("input", function() { updateInputFieldCharCounts(event.target); });
}
function updateInputFieldCharCounts(inputElement) {
	let label = document.getElementById(inputElement.dataset.lengthlabel);
	let maxlength = inputElement.getAttribute("maxLength");
	let maxlines = inputElement.dataset.maxlines;
	if (label != null && maxlength != null) {
		let str = inputElement.value;
		let lines = str.split(/\r\n|\r|\n/).length;
		label.innerHTML = "<span " + (str.length > maxlength ? 'class="text-danger">' : ">") + str.length + "/" + maxlength + " chars</span>";
		if (maxlines != null) {
			label.innerHTML += "&nbsp;<span " + (lines > maxlines ? 'class="text-danger">' : ">") + lines + "/" + maxlines + " lines</span>";
		}
	}
}

// Updates a photo card when its file input field changes (mostly, shows the photo selected).
for (let input of document.querySelectorAll('.image-upload-input')) {
	updatePhotoCardState(input.closest('.card'));
	input.addEventListener("change", function() { updatePhotoCardState(event.target.closest('.card')); })
}
function updatePhotoCardState(cardElement) {
	let imgElem = cardElement.querySelector('img');
	let imgContainer = cardElement.querySelector('.img-for-upload-container');
	let noImgElem = cardElement.querySelector('.no-image-marker');
	let fileInputElem = cardElement.querySelector('.image-upload-input');
	let hiddenFormElem = cardElement.querySelector('input[type="hidden"]');
	let imageSwapButton = cardElement.querySelector('.twitarr-image-swap');
	let imageRemoveButton = cardElement.querySelector('.twitarr-image-remove');
	let imageVisible = true;
	if (fileInputElem.files.length > 0) {
		imgElem.src = window.URL.createObjectURL(fileInputElem.files[0]);
		imgContainer.style.display = "block";
		noImgElem.style.display = "none";
		hiddenFormElem.value = "";
	}
	else if (hiddenFormElem.value) {
		if (hiddenFormElem.value.startsWith('/api/v3') || hiddenFormElem.value.startsWith('/avatar')) {
			imgElem.src = hiddenFormElem.value;
		}
		else {
			imgElem.src = "/api/v3/image/thumb/" + hiddenFormElem.value;
		}
		imgContainer.style.display = "block";
		noImgElem.style.display = "none";
	}
	else {
		imgContainer.style.display = "none";
		noImgElem.style.display = "block";
		imageRemoveButton.disabled = true
		imageVisible = false;
	}
	if (imageSwapButton) {
		imageSwapButton.disabled = !imageVisible;
	}
	if (imageRemoveButton) {
		imageRemoveButton.disabled = !imageVisible;
	}
	let nextCard = cardElement.nextElementSibling;
	if (nextCard != null && nextCard.classList.contains("card")) {
		nextCard.style.display = imgContainer.style.display;
	}
}

// In photo cards, handles 'remove' button.
for (let btn of document.querySelectorAll('.twitarr-image-remove')) {
	btn.addEventListener("click", removeUploadImage);
}
function removeUploadImage() {
	let cardElement = event.target.closest('.card');
	let nextCard = cardElement;
	while (nextCard = cardElement.nextElementSibling) {
		if (!nextCard.classList.contains("card")) {
			break;
		}
		cardElement.querySelector('.image-upload-input').files = nextCard.querySelector('.image-upload-input').files;
		cardElement.querySelector('input[type="hidden"]').value = nextCard.querySelector('input[type="hidden"]').value;
		updatePhotoCardState(cardElement);
		cardElement = nextCard;
	}
	cardElement.querySelector('.image-upload-input').value = null
	cardElement.querySelector('input[type="hidden"]').value = "";
	updatePhotoCardState(cardElement);
}

// Handles photo card 'swap' button, which swaps image N with N-1.
for (let btn of document.querySelectorAll('.twitarr-image-swap')) {
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

// For all form submits that display an error alert on fail but load a new page on success.
for (let form of document.querySelectorAll('form.ajax')) {
	form.addEventListener("submit", function(event) { submitAJAXForm(form, event); });
}
async function submitAJAXForm(formElement, event) {
	if (!formElement.classList.contains('ajax')) {
		return;
	}
    event.preventDefault();
    try {
		let response = await fetch(formElement.action, { method: 'POST', body: new FormData(formElement) });
		if (response.status < 300) {
			let successURL = formElement.dataset.successurl;
			formElement.reset();
			for (let elem of formElement.querySelectorAll('textarea,input.text')) {
				elem.value = "";
				updateInputFieldCharCounts(elem);
			}
			if (successURL == "reset") {
				formElement.querySelector('.twitarr-image-remove')?.click();
				formElement.querySelector('.alert-success')?.classList.remove("d-none")
			}
			else if (successURL) {
				location.assign(successURL);
			}
			else {
				location.reload();
			}
		}
		else {
			let newloc = response.headers.get('Location');
			if (newloc != null) {
				formElement.classList.remove("ajax");
				formElement.setAttribute("action", newloc);
				formElement.submit();
				return;
			}
			let data = await response.json();
			let alertElement = formElement.querySelector('.alert-danger');
			if (alertElement) {
				alertElement.innerHTML = "<b>Error:</b> " + data.reason;
				alertElement.classList.remove("d-none");
			}
		}
	}
	catch(e) {
		let alertElement = formElement.querySelector('.alert-danger');
		alertElement.innerHTML = "<b>Error:</b> " + this.statusText;
		alertElement.classList.remove("d-none");
	}
}

// MARK: - Schedule Page Handlers

// Apply the locally saved event type and following filters to the list of events.
if ((new URL(document.location)).searchParams.get('cruiseday') != null) {
	let onlyFollowing = false;
	if (localStorage.getItem('eventFollowingFilterState') == 'true') {
		document.getElementById("eventFollowingFilter").classList.add('active');
		onlyFollowing = true;
	}
	let category = localStorage.getItem('eventCategoryFilterState');
	if (category) {
		let menuElement = document.getElementById("eventFilterMenuItems").querySelector(`[data-selection="${category}"]`);
		if (menuElement) {
			updateDropdownButton(menuElement);
		}
	}
	for (let listItem of document.querySelectorAll('[data-eventid]')) {
		let hideEvent = (onlyFollowing && listItem.dataset.eventfavorite == "false") ||
				(category && category != "all" && category != listItem.dataset.eventcategory)
		if (hideEvent && listItem.classList.contains("show")) {
			listItem.classList.remove("show");
		}
		else if (!hideEvent && !listItem.classList.contains("show")) {
			listItem.classList.add("show");
		}
	}
}

// Every 15 secs, update the 'Soon' and 'Now' banners on the event cells.
if (document.querySelector('[data-cruiseday]') != null) {
	function updateEventBanners() {
		let [minutesSince3AM, cruiseDay] = calcCruiseDayTime(new Date());
		for (let listItem of document.querySelectorAll('[data-eventid]')) {
			if (listItem.getAttribute('data-cruiseday') == cruiseDay) {
				let eventStartMinutes = calcCruiseDayTime(new Date(listItem.getAttribute('data-starttime') * 1000))[0];
				let eventEndMinutes = calcCruiseDayTime(new Date(listItem.getAttribute('data-endtime') * 1000))[0];
				if (minutesSince3AM >= eventStartMinutes && minutesSince3AM < eventEndMinutes) {
					listItem.classList.remove("event-soon-badge");
					listItem.classList.add("event-now-badge");
				}
				else if (minutesSince3AM >= eventStartMinutes - 30 && minutesSince3AM < eventStartMinutes) {
					listItem.classList.remove("event-now-badge");
					listItem.classList.add("event-soon-badge");
				}
				else {
					listItem.classList.remove("event-soon-badge");
					listItem.classList.remove("event-now-badge");
				}
			}
		}
	}
	updateEventBanners();
	if ((new URL(document.location)).searchParams.get('now') != null) {
		scrollToCurrentEvent();
	}
	let timerFn = setInterval(updateEventBanners, 15000);
}

// Embarkation day is CruiseDay 0. For testing, returns dayOfWeek() + 1 when we're not on the cruise.
function calcCruiseDayTime(dateValue) {
	let listElement = document.querySelector('[data-cruisestart]');
	let cruiseStartDate = new Date(listElement.getAttribute('data-cruisestart') * 1000);
	let cruiseEndDate = new Date(listElement.getAttribute('data-cruiseend') * 1000);
	let cruiseStartDay = cruiseStartDate.getDay();
	if (cruiseStartDate.getHours() > 12) {		// Hackish. StartDate is midnight EST, which makes getDay return the day before in [PCM]ST.
		cruiseStartDay = (cruiseStartDay + 1) % 7;
	}
	// Subtract 3 hours so the 'day' divider for events is 3AM. NOT doing timezone math here.
	let adjustedDate = new Date(dateValue.getTime() - 3 * 60 * 60 * 1000);
	let cruiseDay = (7 - cruiseStartDay + adjustedDate.getDay()) % 7;
	if (adjustedDate >= cruiseStartDate && adjustedDate < cruiseEndDate) {
		cruiseDay = parseInt((adjustedDate - cruiseStartDate) / (1000 * 60 * 60 * 24))
	}
	let minutesSince3AM = adjustedDate.getHours() * 60 + adjustedDate.getMinutes();
	return [minutesSince3AM, cruiseDay];
}

function soonButtonTappedAction() {
	if (!scrollToCurrentEvent()) {
		window.location.href = "/events?now";
	}
}

function scrollToCurrentEvent() {
	// each 'day' for events starts/ends at 3AM, to make events starting at 11:30 PM work better.
	let [minutesSince3AM, cruiseDay] = calcCruiseDayTime(new Date());
	for (let listItem of document.querySelectorAll('[data-eventid]')) {
		if (listItem.getAttribute('data-cruiseday') == cruiseDay) {
			let eventStartMinutes = calcCruiseDayTime(new Date(listItem.getAttribute('data-starttime') * 1000))[0];
			let eventEndMinutes = calcCruiseDayTime(new Date(listItem.getAttribute('data-endtime') * 1000))[0];
			if (minutesSince3AM <= eventEndMinutes && eventEndMinutes - eventStartMinutes <= 120) {
				listItem.scrollIntoView({ block: "center" });
				return true;
			}
		}
	}
	return false;
}

function eventFilterDropdownTappedAction() {
	updateDropdownButton(event.target);
	filterEvents();
}

function filterEvents() {
	let onlyFollowing = document.getElementById("eventFollowingFilter").classList.contains("active")
	let category = document.getElementById("eventFilterMenu").dataset.selected;
	let dayCheckboxes = document.getElementById("cruiseDayButtonGroup").querySelectorAll('input');
	let selectedDays = [];
	for (let checkbox of dayCheckboxes) {
		if (checkbox.checked) {
			selectedDays.push(checkbox.dataset.cruiseday);
		}
	}
	for (let listItem of document.querySelectorAll('[data-eventid]')) {
		let hideEvent = (onlyFollowing && listItem.dataset.eventfavorite == "false") ||
				(category && category != "all" && category != listItem.dataset.eventcategory) ||
				(selectedDays.length > 0 && !selectedDays.includes(listItem.dataset.cruiseday))
		if ((hideEvent && listItem.classList.contains("show")) || (!hideEvent && !listItem.classList.contains("show"))) {
			bootstrap.Collapse.getOrCreateInstance(listItem).toggle();
		}
	}
	localStorage.setItem('eventFollowingFilterState', onlyFollowing.toString());
	localStorage.setItem('eventCategoryFilterState', category);
}

// MARK: - Fez Handlers

function fezDayFilterDropdownTappedAction() {
	updateDropdownButton(event.target);
	applyFezSearchFilters();
}

function fezTypeFilterDropdownTappedAction() {
	updateDropdownButton(event.target);
	applyFezSearchFilters();
}

function applyFezSearchFilters() {
	let typeSelection = document.getElementById("fezTypeFilterMenu").dataset.selected;
	let queryString = ""
	if (typeSelection != "all") {
		queryString = "?type=" + typeSelection;
	}
	let daySelection = document.getElementById("fezDayFilterMenu").dataset.selected;
	if (daySelection != "all") {
		if (queryString.length > 0) {
			queryString = queryString + "&cruiseday=" + daySelection;
		}
		else {
			queryString = "?cruiseday=" + daySelection;
		}
	}
	window.location.href = "/fez" + queryString;
}

// Populates username completions for a partial username. 
let userSearchAPICallTimeout = null;
let userSearch = document.querySelector('input.user-autocomplete');
userSearch?.addEventListener('input', function(event) {
	if (userSearchAPICallTimeout) {
		clearTimeout(userSearchAPICallTimeout);
	}
	userSearchAPICallTimeout = setTimeout(() => {
		userSearchAPICallTimeout = null;
		let searchString = userSearch.value?.replace(/\s+/g, '');
		if (searchString.length < 2) { return }
		fetch("/seamail/usernames/search/" + encodeURIComponent(searchString))
			.then(response => response.json())
			.then(userHeaders => {
				let suggestionDiv = document.getElementById('name_suggestions');
				suggestionDiv.innerHTML = "";
				for (user of userHeaders) {
					let listItem = document.getElementById('potentialMemberTemplate').content.firstElementChild.cloneNode(true);
					listItem.dataset.userid = user.userID;
					listItem.querySelector('.username-here').innerHTML = ["@", user.username, " <b>", user.displayName,"</b>"].join('');
					suggestionDiv.append(listItem);
					let checkbox = listItem.querySelector('.btn-check');
					if (checkbox != null) {
						checkbox.dataset.actionpath = checkbox.dataset.actionpath + user.userID;
						checkbox.dataset.errordiv = "waitlisterror_" + user.userID;
						listItem.querySelector('.error-display').id = "waitlisterror_" + user.userID;
						if (userSearch.dataset.nameusage == "seamail") {
							checkbox.addEventListener('click', addToNamedParticipants);
						}
						else {
							checkbox.addEventListener('click', spinnerButtonAction);
						}
					}
					let anchorButton = listItem.querySelector('.append-userid-to-href')
					if (anchorButton != null) {
						anchorButton.href = anchorButton.href + user.userID;
					}
				}
			})
		
	}, 200);
})

function addToNamedParticipants(event) {
	let listItem = event.target.closest('li');
	let participantsDiv = document.getElementById('named_participants');
	for (index = 0; index < participantsDiv.children.length; ++index) {
		if (participantsDiv.children[index].dataset.userid == listItem.dataset.userid) {
			return;
		}
	} 
	let divCopy = listItem.cloneNode(true);
	divCopy.querySelector('.button-title-here').innerText = "Remove";
	participantsDiv.append(divCopy);
	updateParticipantFormElement(participantsDiv);
	divCopy.addEventListener('click', function(event) {
		divCopy.remove();
		updateParticipantFormElement(participantsDiv);
	});
}

function updateParticipantFormElement(participantsDiv) {
	let names = [];
	for (index = 1; index < participantsDiv.children.length; ++index) {
		names.push(participantsDiv.children[index].dataset.userid);
	} 
	let hiddenFormElem = document.getElementById('participants_hidden');
	hiddenFormElem.value = names;
}

// MARK: - User Profile Handlers

// In Edit User Avatar photo card, handles 'Reset and 'Default' buttons
for (let btn of document.querySelectorAll('.twitarr-image-reset')) {
	btn.addEventListener("click", resetAvatarImage);
}
function resetAvatarImage() {
	let cardElement = event.target.closest('.card');
	cardElement.querySelector('.image-upload-input').value = null
	let hiddenElem = cardElement.querySelector('input[type="hidden"]');
	hiddenElem.value = hiddenElem.dataset.originalvalue;
	updatePhotoCardState(cardElement);
}
for (let btn of document.querySelectorAll('.twitarr-image-default')) {
	btn.addEventListener("click", setDefaultAvatarImage);
}
function setDefaultAvatarImage() {
	let cardElement = event.target.closest('.card');
	cardElement.querySelector('.image-upload-input').value = null
	let hiddenElem = cardElement.querySelector('input[type="hidden"]');
	hiddenElem.value = hiddenElem.dataset.defaultvalue;
	updatePhotoCardState(cardElement);
}

document.getElementById('imageCarouselModal')?.addEventListener('show.bs.modal', function(event) {
	let pageImg = event.relatedTarget.querySelector('img');
	let modalImg = event.target.querySelector('.swiftarr-closeup-image');
	if (pageImg && modalImg) {
		modalImg.src = pageImg.src;
	}
	deleteBtn.setAttribute('data-delete-postid', postElem.dataset.postid);
})

// It would be really nice if we could easily break this out into a time-only script. But since
// we don't have a pattern for that yet I'm not looking to re-invent the wheel just yet.
window.addEventListener('DOMContentLoaded', function() {
	if (document.getElementById('browserTimeDisplay')) {
		browserTime = new Date();
		// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat/formatToParts
		var formatter = new Intl.DateTimeFormat('en-us', {
			month: 'long',
			day: '2-digit',
			hour: 'numeric', // Swift is supposed to give 2-digit but it isn't working. At least this matches.
			minute: '2-digit',
			hour12: true,
			timeZoneName: 'long'
		  });
		document.getElementById('browserTimeDisplay').innerHTML = formatter.format(browserTime)
	}
})

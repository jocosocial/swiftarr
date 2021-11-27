function startLiveMessageStream() {
	let endDiv = document.getElementById("fez-list-end")
	let socketURL = endDiv.dataset.url
	ws = new WebSocket("ws://" + window.location.host + socketURL)
 
	ws.onopen = () => {
		// Maybe show something here to indicate we're live updating?
	}

	ws.onmessage = (event) => {
		let message = JSON.parse(event.data);
		let endDiv = document.getElementById("fez-list-end");
		endDiv?.insertAdjacentHTML('beforebegin', message.html);
		if (message.text) {
			let postCountSpan = document.getElementById("post-count-span")
			if (postCountSpan) {
				let postCount = parseInt(postCountSpan.innerText);
				postCountSpan.innerText = String(postCount + 1);
			}
		}
	};

	ws.onclose = () => {
	};
}
startLiveMessageStream();

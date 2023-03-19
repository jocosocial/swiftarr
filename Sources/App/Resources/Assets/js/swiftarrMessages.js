function startLiveMessageStream() {
	let endDiv = document.getElementById("fez-list-end")
	let socketURL = endDiv.dataset.url
	let wsProtocol = "ws://"
	if (window.location.href.startsWith("https")) {
		wsProtocol = "wss://"
	}
	ws = new WebSocket(wsProtocol + window.location.host + socketURL)

	ws.onopen = () => {
		let statusDiv = document.getElementById("socket-status")
		statusDiv.innerText = "live messaging: active"
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
		let statusDiv = document.getElementById("socket-status")
		statusDiv.innerText = "live messaging: off"
	};
}
startLiveMessageStream();

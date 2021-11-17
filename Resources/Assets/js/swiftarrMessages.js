function startLiveMessageStream() {
	let endDiv = document.getElementById("fez-list-end")
	let socketURL = endDiv.dataset.url
	ws = new WebSocket("ws://" + window.location.host + socketURL)
 
	ws.onopen = () => {
		// Maybe show something here to indicate we're live updating?
	}

	ws.onmessage = (event) => {
		let endDiv = document.getElementById("fez-list-end");
		endDiv.insertAdjacentHTML('beforebegin', event.data);
	};

	ws.onclose = () => {
	};
}
startLiveMessageStream();

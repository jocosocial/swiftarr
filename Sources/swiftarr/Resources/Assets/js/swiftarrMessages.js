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
		if (message.reactionUpdate === true) {
			// Updates for posts not yet rendered are discarded. If an older post fragment is still in
			// flight, it can subsequently show stale counts until another reaction update or refresh.
			// We accept this narrow display race rather than buffer snapshots for unloaded posts.
			const post = document.querySelector(`[data-postid="${message.postID}"]`);
			const revision = message.reactionRevision ?? 0;
			if (revision < Number(post?.dataset.reactionRevision ?? 0)) return;
			let reactionContainer = document.querySelector(`[data-postid="${message.postID}"] [data-reaction-container]`);
			if (reactionContainer && typeof message.html === 'string') {
				reactionContainer.outerHTML = message.html;
				post.dataset.reactionRevision = String(revision);
			}
			return;
		}
		let endDiv = document.getElementById("fez-list-end");
		endDiv?.insertAdjacentHTML('beforebegin', message.html);
		if (message.text) {
			let postCountSpan = document.getElementById("post-count-span")
			if (postCountSpan) {
				let postCount = parseInt(postCountSpan.innerText);
				postCountSpan.innerText = String(postCount + 1);
			}
		}
		// The post was just rendered live into the page, so tell the server we've read it too.
		// This keeps the "new"/unread badges from lighting up for content the user already saw.
		let markReadURL = socketURL.replace(/\/socket$/, '/markRead');
		fetch(markReadURL, { method: 'POST' });
	};

	ws.onclose = () => {
		let statusDiv = document.getElementById("socket-status")
		statusDiv.innerText = "live messaging: off"
	};
}
startLiveMessageStream();

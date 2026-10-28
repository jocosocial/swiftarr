import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {runInNewContext} from "node:vm";

test("browser reload waits through rebuild downtime and refreshes only for a new revision", async () => {
	const script = readFileSync(new URL("../../Sources/swiftarr/Resources/Assets/js/devReload.js", import.meta.url), "utf8");
	let poll;
	let reloads = 0;
	let revision = "first";
	let offline = true;
	const document = {hidden: false};
	runInNewContext(script, {
		document,
		location: {reload: () => reloads++},
		fetch: async () => {
			if (offline) throw new Error("server restarting");
			return {ok: true, text: async () => revision};
		},
		setInterval: callback => poll = callback,
	});
	await new Promise(resolve => setImmediate(resolve));
	assert.equal(typeof poll, "function");
	assert.equal(reloads, 0, "initial connection failure must keep the poller alive");
	offline = false;
	await poll();
	assert.equal(reloads, 0);
	offline = true;
	await poll();
	assert.equal(reloads, 0);
	offline = false;
	revision = "second";
	document.hidden = true;
	await poll();
	assert.equal(reloads, 0);
	document.hidden = false;
	await poll();
	assert.equal(reloads, 1);
});

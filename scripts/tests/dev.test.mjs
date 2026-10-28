import test from "node:test";
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync, existsSync, realpathSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {setTimeout as pause} from "node:timers/promises";

/** Wait for an observable runner result, with a bounded timeout and captured diagnostics. */
async function until(predicate, diagnostic) {
	const deadline = Date.now() + 15000;
	while (!predicate()) {
		if (Date.now() > deadline) throw new Error(`Timed out: ${diagnostic()}`);
		await pause(50);
	}
}

test("development runner reloads resources, debounces rebuilds, recovers, and stops its server", async () => {
	const root = realpathSync(mkdtempSync(join(tmpdir(), "swiftarr-dev-test-")));
	let runner;
	let stopped;
	let output = "";
	const source = join(root, "Sources/swiftarr/main.swift");
	const asset = join(root, "Sources/swiftarr/Resources/Views/page.html");
	const builds = join(root, "builds");
	const starts = join(root, "starts");
	const state = join(root, "server-state");
	const count = path => existsSync(path) ? readFileSync(path, "utf8").trim().split("\n").length : 0;
	try {
		for (const dir of ["scripts", "bin", "Sources/swiftarr/Resources/Views"]) mkdirSync(join(root, dir), {recursive: true});
		copyFileSync(fileURLToPath(new URL("../dev.mjs", import.meta.url)), join(root, "scripts/dev.mjs"));
		writeFileSync(source, "initial");
		writeFileSync(asset, "initial");
		writeFileSync(join(root, "Package.swift"), "fixture");
		writeFileSync(join(root, "bin/swift"), `#!/usr/bin/env node
const fs = require('node:fs');
const root = process.env.DEV_TEST_ROOT;
if (process.argv.includes('--show-bin-path')) console.log(root + '/bin');
else {
 fs.appendFileSync(root + '/builds', 'build\\n');
 const delay = fs.existsSync(root + '/slow') ? 1800 : 100;
 setTimeout(() => process.exit(fs.existsSync(root + '/fail') ? 1 : 0), delay);
}
`, {mode: 0o755});
		writeFileSync(join(root, "bin/swiftarr"), `#!/usr/bin/env node
const fs = require('node:fs');
const root = process.env.DEV_TEST_ROOT;
fs.appendFileSync(root + '/starts', 'start\\n');
fs.writeFileSync(root + '/server-state', JSON.stringify({pid: process.pid, revision: process.env.SWIFTARR_DEV_RELOAD_FILE, resources: process.env.SWIFTARR_DEV_RESOURCES, args: process.argv.slice(2)}));
setInterval(() => {}, 1000);
process.on('SIGTERM', () => process.exit(0));
`, {mode: 0o755});
		runner = spawn(process.execPath, [join(root, "scripts/dev.mjs")], {
			env: {...process.env, PATH: `${join(root, "bin")}:${process.env.PATH}`, DEV_TEST_ROOT: root,
				SWIFTARR_DEV_DEBOUNCE_MS: "1200", SWIFTARR_DEV_RELOAD_MS: "200"},
			stdio: ["ignore", "pipe", "pipe"],
		});
		runner.stdout.on("data", data => output += data);
		runner.stderr.on("data", data => output += data);
		stopped = new Promise(resolve => runner.once("exit", resolve));
		await until(() => existsSync(state), () => output);
		const initial = JSON.parse(readFileSync(state));
		assert.equal(initial.resources, join(root, "Sources/swiftarr/Resources"));
		assert.deepEqual(initial.args, ["serve", "--env", "development"]);
		const revision = readFileSync(initial.revision, "utf8");
		writeFileSync(asset, "resource edit");
		await until(() => readFileSync(initial.revision, "utf8") !== revision, () => output);
		assert.equal(count(builds), 1, "resource edits must not compile");
		assert.equal(count(starts), 1, "resource edits must not restart the server");

		writeFileSync(source, "first Swift edit");
		await pause(600);
		writeFileSync(source, "second Swift edit in the same batch");
		await until(() => count(starts) === 2, () => output);
		assert.equal(count(builds), 2, "one rebuild for the Swift edit batch");

		writeFileSync(join(root, "fail"), "fail the next compile");
		writeFileSync(source, "invalid Swift");
		await until(() => output.includes("Build failed"), () => output);
		assert.equal(count(starts), 2, "a failed build must not launch a stale binary");
		rmSync(join(root, "fail"));
		writeFileSync(source, "fixed Swift");
		await until(() => count(starts) === 3, () => output);
		assert.equal(count(builds), 4);

		writeFileSync(join(root, "slow"), "slow compilation");
		writeFileSync(source, "begin a slow build");
		await until(() => count(builds) === 5, () => output);
		writeFileSync(source, "edit while the build is running");
		await until(() => count(starts) === 4, () => output);
		assert.equal(count(builds), 6, "an edit during compilation must build again before launching");
		const final = JSON.parse(readFileSync(state));
		runner.kill("SIGTERM");
		await stopped;
		assert.equal(existsSync(final.revision), false, "shutdown removes the revision file");
		assert.throws(() => process.kill(final.pid, 0), {code: "ESRCH"}, "shutdown stops the server");
	}
	finally {
		if (runner && runner.exitCode === null) {
			runner.kill("SIGTERM");
			await stopped;
		}
		rmSync(root, {recursive: true, force: true});
	}
});

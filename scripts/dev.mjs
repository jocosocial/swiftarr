import {spawn} from "node:child_process";
import {randomUUID} from "node:crypto";
import {mkdtempSync, readdirSync, statSync, writeFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join, relative} from "node:path";
import {fileURLToPath} from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const scratch = mkdtempSync(join(tmpdir(), "swiftarr-dev-"));
const revisionFile = join(scratch, "revision");
const environment = {
	...process.env,
	SWIFTARR_DEV_RESOURCES: join(root, "Sources/swiftarr/Resources"),
	SWIFTARR_DEV_RELOAD_FILE: revisionFile,
};

/** Read a positive debounce setting without silently accepting a broken configuration. */
function delaySetting(name, fallback) {
	const value = Number(process.env[name] ?? fallback);
	if (!Number.isFinite(value) || value < 1) throw new Error(`${name} must be a positive number of milliseconds`);
	return value;
}
const rebuildDelay = delaySetting("SWIFTARR_DEV_DEBOUNCE_MS", 2000);
const reloadDelay = delaySetting("SWIFTARR_DEV_RELOAD_MS", 1000);
let revision = 0;
const session = randomUUID();
let child;
let timer;
let stopping = false;
let building = false;
let buildFailed = false;
let buildGeneration = 0;
let buildDue = Date.now();
let reloadDue = Infinity;

/** Snapshot source files, including additions/deletions and atomic editor saves, without watching build outputs. */
function snapshot() {
	const files = new Map();
	function visit(path) {
		try {
			const info = statSync(path, {bigint: true});
			if (info.isDirectory()) {
				for (const entry of readdirSync(path, {withFileTypes: true})) {
					if (!entry.name.startsWith(".") && !entry.isSymbolicLink()) visit(join(path, entry.name));
				}
			}
			else files.set(relative(root, path), `${info.mtimeNs}:${info.size}`);
		}
		catch (error) {
			if (error.code !== "ENOENT" && error.code !== "ENOTDIR") throw error;
		}
	}
	for (const path of ["Sources", "Package.swift", "Package.resolved"]) visit(join(root, path));
	return files;
}

/** Tell connected development pages to reload after a resource batch or successful rebuild. */
function publishRevision() {
	writeFileSync(revisionFile, `${session}:${++revision}`);
}

/** Start a process in its own group so shutdown also reaches compiler/server descendants. */
function launch(command, args, capture = false) {
	const process = spawn(command, args, {
		cwd: root, env: environment, detached: true,
		stdio: capture ? ["ignore", "pipe", "inherit"] : "inherit",
	});
	child = process;
	let output = "";
	process.stdout?.on("data", data => output += data);
	const done = new Promise(resolve => {
		process.once("error", error => {
			console.error(`[dev] ${error.message}`);
			resolve({code: 1, output});
		});
		process.once("exit", code => resolve({code, output}));
	});
	process.done = done;
	return process;
}

/** Stop only the child group owned by this runner, escalating after five seconds. */
async function stopChild() {
	const target = child;
	if (!target) return;
	child = undefined;
	if (target.exitCode !== null || target.signalCode !== null || !target.pid) return;
	const signal = name => {
		try { process.kill(-target.pid, name); }
		catch (error) { if (error.code !== "ESRCH") throw error; }
	};
	signal("SIGTERM");
	const killTimer = setTimeout(() => signal("SIGKILL"), 5000);
	await target.done;
	clearTimeout(killTimer);
}

/** Build serially; source edits during compilation schedule a fresh build before starting a server. */
async function rebuild() {
	building = true;
	buildDue = Infinity;
	const generation = buildGeneration;
	try {
		await stopChild();
		if (stopping) return;
		console.log("[dev] Building Swiftarr…");
		const result = await launch("swift", ["build", "--product", "swiftarr"]).done;
		if (stopping) return;
		if (result.code !== 0) {
			buildFailed = true;
			console.error("[dev] Build failed. Watching for the next edit.");
			return;
		}
		if (generation !== buildGeneration) return;
		buildFailed = false;
		const location = await launch("swift", ["build", "--show-bin-path"], true).done;
		if (stopping || generation !== buildGeneration || location.code !== 0) return;
		publishRevision();
		reloadDue = Infinity;
		const args = process.argv.slice(2).filter((arg, index) => index !== 0 || arg !== "--");
		const server = launch(join(location.output.trim(), "swiftarr"), ["serve", "--env", "development", ...args]);
		console.log("[dev] Server started. Resource edits reload pages; Swift edits rebuild after the debounce.");
		server.done.then(result => {
			if (!stopping && child === server) console.log(`[dev] Server exited (${result.code}). Watching for edits.`);
		});
	}
	finally { building = false; }
}

/** Release the watcher, child processes, and temporary revision file on Ctrl-C or termination. */
async function shutdown() {
	if (stopping) return;
	stopping = true;
	clearInterval(timer);
	await stopChild();
	rmSync(scratch, {recursive: true, force: true});
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

publishRevision();
let previous = snapshot();
timer = setInterval(() => {
	try {
		const next = snapshot();
		const changed = [...new Set([...previous.keys(), ...next.keys()])]
			.filter(path => previous.get(path) !== next.get(path));
		previous = next;
		const now = Date.now();
		if (changed.some(path => !path.startsWith("Sources/swiftarr/Resources/")) || (buildFailed && changed.length > 0)) {
			buildGeneration++;
			buildDue = now + rebuildDelay;
		}
		if (changed.some(path => path.startsWith("Sources/swiftarr/Resources/"))) {
			reloadDue = now + reloadDelay;
			if (buildDue !== Infinity) buildDue = now + rebuildDelay;
		}
		if (!building && now >= buildDue) rebuild().catch(error => { console.error(error); shutdown(); });
		else if (!building && buildDue === Infinity && now >= reloadDue) {
			publishRevision();
			reloadDue = Infinity;
			console.log("[dev] Resources changed; reloading browsers.");
		}
	}
	catch (error) { console.error(error); shutdown(); }
}, 500);
await rebuild();

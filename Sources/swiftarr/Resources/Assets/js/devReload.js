// Included only by an explicitly enabled development run.
let initialRevision;
let checking = false;

/** Keep polling through rebuilds, including a restart during the initial page load. */
async function checkDevelopmentRevision() {
	if (checking || document.hidden) return;
	checking = true;
	try {
		const response = await fetch("/__dev/revision", {cache: "no-store"});
		if (!response.ok) return;
		const revision = await response.text();
		if (initialRevision === undefined) initialRevision = revision;
		else if (revision !== initialRevision) location.reload();
	}
	catch { /* A Swift rebuild temporarily takes the server offline. */ }
	finally { checking = false; }
}
setInterval(checkDevelopmentRevision, 1000);
checkDevelopmentRevision();

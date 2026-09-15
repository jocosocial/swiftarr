// Dark mode runtime: cycle the toggle button (auto → light → dark → auto),
// persist the choice to a cookie, and respond to OS preference flips while in 'auto'.

(function() {
	var ORDER = ['auto', 'light', 'dark'];
	var COOKIE = 'swiftarr_theme';
	var ONE_YEAR = 60 * 60 * 24 * 365;

	function readCookie() {
		var m = document.cookie.match(/(?:^|; )swiftarr_theme=(auto|light|dark)/);
		return m ? m[1] : 'auto';
	}

	function writeCookie(value) {
		document.cookie = COOKIE + '=' + value + '; path=/; max-age=' + ONE_YEAR + '; samesite=lax';
	}

	function resolve(pref) {
		if (pref === 'auto') {
			return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
		}
		return pref;
	}

	function applyTheme(pref) {
		document.documentElement.setAttribute('data-theme-pref', pref);
		document.documentElement.setAttribute('data-bs-theme', resolve(pref));
	}

	function cycle() {
		var current = readCookie();
		var next = ORDER[(ORDER.indexOf(current) + 1) % ORDER.length];
		writeCookie(next);
		applyTheme(next);
	}

	// Wire up the toggle button if it exists on this page.
	var btn = document.getElementById('themeToggle');
	if (btn) {
		btn.addEventListener('click', cycle);
	}

	// React to OS preference flips while in 'auto'.
	window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
		if (readCookie() === 'auto') {
			applyTheme('auto');
		}
	});
})();

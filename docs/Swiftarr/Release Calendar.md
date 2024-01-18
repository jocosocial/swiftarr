Release Calendar
================

Roughly 30 days before boat we implement a "code frost". The main purpose is to lock any internet-sourced dependencies so that they get cached on the server before it ships to the warehouse. What this means in practice:

* No new Swift packages or versions of packages can be imported because we can't easily insert them into the build cache of the now offline server.
* No breaking API changes. This is to allow mobile app developers to finalize their submissions to various app stores.

Roughly two weeks before boat the mobile apps typically get submitted to the app stores. This provides just enough time to get reviewed and published. Links to download the apps are withheld from public distribution until the latest versions are live in the app stores. This is to ensure people download the latest version and don't get stuck with an old version when they board because their phone didn't auto-update.
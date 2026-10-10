{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own service worker is a deprecated stub
// that unregisters itself, and registering it at the site root would replace
// push_sw.js - the worker that receives reminders - and drop the push
// subscription with it.
_flutter.loader.load();

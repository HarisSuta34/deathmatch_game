extends RefCounted
# Where the client finds the game server.

const DEFAULT_PORT := 9080
const LOCAL_URL := "ws://localhost:9080"
# Set this to your deployed server (must be wss:// when the site is served over https),
# e.g. "wss://my-game-server.example.com". See docs/DEPLOY.md.
const PRODUCTION_URL := "wss://deathmatch-game.onrender.com"


static func server_url() -> String:
	if OS.has_feature("web"):
		# A "?server=wss://..." in the page address overrides everything.
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		if q is String and q != "":
			return q
		var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
		if PRODUCTION_URL != "" and not (host in ["localhost", "127.0.0.1"]):
			return PRODUCTION_URL
	return LOCAL_URL

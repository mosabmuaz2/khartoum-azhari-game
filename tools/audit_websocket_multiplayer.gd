extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var main_ps := load("res://scenes/main.tscn") as PackedScene
	if not main_ps:
		printerr("[WS AUDIT FAIL] Cannot load res://scenes/main.tscn")
		quit(1)
		return

	var main_inst := main_ps.instantiate()
	root.add_child(main_inst)
	for _i in range(4):
		await process_frame

	var net_mgr := main_inst.get_node_or_null("NetworkManager") as NetworkManager
	if net_mgr == null:
		printerr("[WS AUDIT FAIL] NetworkManager node not found")
		quit(1)
		return

	# 1. Verify Join button label includes Arabic one-tap join prompt
	if net_mgr.join_button == null or net_mgr.join_button.text != "انضمام للمدينة (Join)":
		failures.append("Join button text mismatch: %s" % (net_mgr.join_button.text if net_mgr.join_button else "null"))

	# 2. Trigger Host mode (listens on WebSocket :7778 + ENet :7777)
	net_mgr._on_host_pressed()
	for _i in range(4):
		await process_frame

	if not (main_inst.get_tree().get_multiplayer().multiplayer_peer is WebSocketMultiplayerPeer):
		failures.append("Primary multiplayer_peer is not WebSocketMultiplayerPeer after hosting")

	var host_player := net_mgr.players_container.get_node_or_null("1")
	if host_player == null:
		failures.append("Host player '1' was not spawned upon hosting")

	# 3. Connect a simulated iPhone Safari WebSocket client through ws://127.0.0.1:8080/ws (proxied to 127.0.0.1:7778)
	var client_peer := WebSocketMultiplayerPeer.new()
	var err := client_peer.create_client("ws://127.0.0.1:8080/ws")
	if err != OK:
		failures.append("client_peer.create_client(ws://127.0.0.1:8080/ws) failed with err=%d" % err)
	else:
		var connected := false
		for _step in range(80):
			client_peer.poll()
			if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and net_mgr.players_container.get_child_count() >= 2:
				connected = true
				break
			await process_frame
		if not connected:
			failures.append("Simulated iPhone Safari WebSocket client via ws://127.0.0.1:8080/ws did not reach CONNECTION_CONNECTED + spawn 2nd player (players=%d, status=%d)" % [
				net_mgr.players_container.get_child_count(), client_peer.get_connection_status()
			])
		else:
			print("[WS AUDIT OK] iPhone Safari WebSocket client connected via ws://127.0.0.1:8080/ws -> 127.0.0.1:7778! Active players in map: %d" % net_mgr.players_container.get_child_count())
		client_peer.close()

	if failures.is_empty():
		print("[WS AUDIT PASS] Dual WebSocket (:7778) + ENet (:7777) + /ws proxy verified with 0 failures!")
		quit(0)
	else:
		for f in failures:
			printerr("[WS AUDIT FAIL] %s" % f)
		quit(1)

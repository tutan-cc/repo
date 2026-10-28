extends Node3D

const MJRules = preload("res://rules.gd")
## 重生2 · 麻将（纯 Godot 3D）
## 规则照搬 mahjong.js：四组一对 / 七对 / 龙七对 / 碰碰胡 / 大吊车 + 碰杠胡优先级

const KINDS := 34
const TW := 34.0
const TD := 44.0
const TH := 19.0
const GAP := 2.0
const RINX := 360.0
const RINY := 300.0
const PER_SIDE := 17

const HAND_W := 52.0
const HAND_H := 74.0
const HAND_STEP := 56.0
const HAND_T := 24.0
const RIVER_S := 50.0
const SIDE_T := 19.0
const HAND_Z := 392.0
const HAND_X := 436.0
const SEAT_NAMES := ["你", "下家", "对家", "上家"]
const TILE_NAMES := ["一万","二万","三万","四万","五万","六万","七万","八万","九万","一筒","二筒","三筒","四筒","五筒","六筒","七筒","八筒","九筒","一条","二条","三条","四条","五条","六条","七条","八条","九条","东风","南风","西风","北风","红中","发财","白板"]
const CLAIM_DELAY := 1.0
const AI_DRAW_DELAY := 1.0
const AI_THINK := 1.3
const STAKE := 2
const CAM_H := 720.0     # 相机高度（越大越俯视）
const CAM_D := 1180.0      # 相机到桌心的水平距离
const CAM_FOV := 43.0
const HAND_TILT := 14.0   # 手牌后仰角度
const SAVE_VERSION := 3
const SAVE_PATH := "user://match_state.json"

var wall: Array = []
var hands: Array = [[], [], [], []]
var rivers: Array = [[], [], [], []]
var melds: Array = [[], [], [], []]
var turn := 0
var phase := "discard"
var drawn_index := -1
var game_over := false
var scores: Array[int] = [0, 0, 0, 0]
var dealer := 0
var hand_no := 1
var ai_level := 1
var master_volume := 1.0
var _persist_enabled := true
var _save_path := SAVE_PATH
var _round_label: Label
var _score_label: Label
var _rules_btn: Button
var _rules_overlay: ColorRect
var _rules_text: RichTextLabel
var _rules_close: Button
var _rules_open := false
var _ai_buttons: Array[Button] = []
var _main_menu_open := false
var _pause_open := false
var _settings_open := false
var _main_menu_overlay: ColorRect
var _main_menu_info: Label
var _main_menu_start: Button
var _pause_overlay: ColorRect
var _pause_resume: Button
var _settings_overlay: ColorRect
var _settings_slider: HSlider
var _volume_value_label: Label
var _settings_fullscreen_btn: Button
var _settings_close: Button
var _turn_token := 0
var _queue: Array = []
var _human_pending := {}
var _total_checks := 0
var busy := false
var _claim_choice := ""
var _claim_row: HBoxContainer
var evt_log: RichTextLabel
var evt_lines: Array = []
var toast: Label
var result_detail: Label
var restart_btn: Button
var auto_pass := false
var auto_peng := false
var _last_discard_seat := -1
var _drop_seat := -1
var _anim_draw := true
var _anim_deal := false
var sfx := {}

# ── 表现层状态 ──────────────────────────────────────────────
var _hand_nodes: Array[Node3D] = []
var _hovered_index := -1
var _hover_label: Label
var _hud_hint: Label
var _status_panel: PanelContainer
var _status_style: StyleBoxFlat
var _claim_panel: PanelContainer
var _toast_panel: PanelContainer
var _toast_tween: Tween
var _result_overlay: ColorRect
var _result_panel: PanelContainer
var _cam_base_pos := Vector3.ZERO
var _shake_trauma := 0.0
var _muted := false
var _mute_btn: Button
var _fullscreen := false
var _hud_root: Control
var _win_context := {}
var result_source: Label
var result_hands_panel: PanelContainer
var result_hands_box: VBoxContainer

func _init_audio() -> void:
	for bus_name in ["SFX", "Voice", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
			AudioServer.set_bus_volume_db(idx, 0.0)

func _apply_audio_settings() -> void:
	var idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(idx, _muted)
	AudioServer.set_bus_volume_linear(idx, maxf(master_volume, 0.0001))

func _toggle_mute() -> void:
	_muted = not _muted
	_apply_audio_settings()
	if _mute_btn:
		_mute_btn.text = "已静音  M" if _muted else "声音  M"
	_save_match_state()

func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if _settings_fullscreen_btn:
		_settings_fullscreen_btn.text = "全屏：开  F11" if _fullscreen else "全屏：关  F11"

func _init_sfx() -> void:
	for n in ["peng", "gang", "hu", "draw", "discard"]:
		var p := AudioStreamPlayer.new()
		var s = load("res://sounds/%s.wav" % n)
		if s:
			p.stream = s
		p.volume_db = -6.0
		p.max_polyphony = 2
		p.bus = &"SFX"
		add_child(p)
		sfx[n] = p

var voice_player: AudioStreamPlayer
var voice_streams := {}
var call_player: AudioStreamPlayer
var call_streams: Array = []

func _init_calls() -> void:
	call_player = AudioStreamPlayer.new()
	call_player.volume_db = -4.0
	call_player.bus = &"Voice"
	add_child(call_player)
	for i in range(34):
		var s = load("res://sounds/calls/%d.wav" % i)
		call_streams.append(s)

func _init_voice() -> void:
	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = -1.0
	voice_player.bus = &"Voice"
	add_child(voice_player)
	for n in ["vo_peng", "vo_gang", "vo_hu", "vo_zimo"]:
		var s = load("res://sounds/%s.wav" % n)
		if s:
			voice_streams[n] = s

func _say(n: String) -> void:
	if call_player:
		call_player.stop()
	if voice_player and voice_streams.has(n):
		voice_player.stream = voice_streams[n]
		voice_player.play()

## 等牌名播报念完，再喊碰/杠/胡
func _say_after(n: String) -> void:
	if call_player and call_player.playing:
		var cb := func(): _say(n)
		call_player.finished.connect(cb, CONNECT_ONE_SHOT)
	else:
		_say(n)

func _announce(kind: int) -> void:
	if call_player == null or kind < 0 or kind >= call_streams.size():
		return
	var s = call_streams[kind]
	if s:
		call_player.stream = s
		call_player.play()

func _play(n: String, vol: float = -6.0) -> void:
	if sfx.has(n):
		var p: AudioStreamPlayer = sfx[n]
		p.volume_db = vol
		p.pitch_scale = randf_range(0.97, 1.03) if n in ["draw", "discard"] else 1.0
		p.play()

# ── UI 小工具：统一面板、按钮和文字样式 ─────────────────────
func _panel_style(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	s.shadow_color = Color(0, 0, 0, 0.32)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s

func _ui_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.68))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _panel_style(bg, border, 10)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 2)
	return s

func _style_button(b: Button, bg: Color, accent: Color) -> void:
	b.add_theme_stylebox_override("normal", _button_style(bg, accent.darkened(0.25)))
	b.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.08), accent))
	b.add_theme_stylebox_override("pressed", _button_style(bg.darkened(0.12), accent.lightened(0.15)))
	b.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0.08), accent.lightened(0.25)))
	b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 20)

func _add_trauma(amount: float) -> void:
	_shake_trauma = clampf(_shake_trauma + amount, 0.0, 1.0)

func _update_camera_shake(delta: float) -> void:
	if cam == null:
		return
	if _shake_trauma <= 0.0:
		cam.position = _cam_base_pos
		return
	_shake_trauma = maxf(_shake_trauma - delta * 1.9, 0.0)
	var strength := _shake_trauma * _shake_trauma
	var t := Time.get_ticks_msec() * 0.001 * 28.0
	cam.position = _cam_base_pos + Vector3(sin(t * 1.7) * 14.0, sin(t * 2.3) * 9.0, 0.0) * strength

var mat_ivory: StandardMaterial3D
var mat_green: StandardMaterial3D
var mat_felt: StandardMaterial3D
var mat_groove: StandardMaterial3D
var mat_plate: StandardMaterial3D
var mat_gold: StandardMaterial3D
var mat_rim: StandardMaterial3D
var mat_back: StandardMaterial3D
var board: Node3D
var cam: Camera3D
var hud: Label
var big: Label


func _ready() -> void:
	DisplayServer.window_set_title("重生2 · 3D麻将")
	_fix_window_title()
	_materials()
	_env()
	_init_audio()
	_init_sfx()
	_init_calls()
	_init_voice()
	var user_args := OS.get_cmdline_user_args()
	_persist_enabled = user_args.is_empty()
	if _persist_enabled:
		_load_match_state()
	_apply_audio_settings()
	_new_game()
	_build()
	_make_hud()
	if _persist_enabled:
		_open_main_menu(false)
	var args: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--zimo"):
		_zimo_test()
		return
	if args.has("--aitest"):
		_ai_test()
		return
	if args.has("--audiotest"):
		_audio_test()
		return
	if args.has("--matchtest"):
		_match_test()
		return
	if args.has("--kongscore"):
		_kong_score_test()
		return
	if args.has("--shantentest"):
		_shanten_test()
		return
	if args.has("--scoreshot"):
		_score_shot_test()
		return
	if args.has("--menushot"):
		_panel_shot_test("menu")
		return
	if args.has("--pauseshot"):
		_panel_shot_test("pause")
		return
	if args.has("--settingsshot"):
		_panel_shot_test("settings")
		return
	if args.has("--dealwintest"):
		_deal_win_test()
		return
	if args.has("--flowtest"):
		_flow_test()
		return
	if args.has("--savetest"):
		_save_test()
		return
	if args.has("--nopoint"):
		_no_point_test()
		return
	if args.has("--rulesshot"):
		_rules_shot_test()
		return
	if args.has("--uishot"):
		_ui_shot_test()
		return
	if args.has("--hovertest"):
		_hover_test()
		return
	if args.has("--resultshot"):
		_result_shot_test()
		return
	if args.has("--showdownshot"):
		_showdown_shot_test()
		return
	if args.has("--resulttest"):
		_result_test()
		return
	if args.has("--claimtest"):
		_claim_test()
		return
	if args.has("--robtest"):
		_rob_test()
		return
	if args.has("--kongtest"):
		_kong_test()
		return
	if args.has("--rivertest"):
		_river_test()
		return
	if args.has("--labeltest"):
		_label_test()
		return
	if args.has("--aipeng"):
		_ai_peng_test()
		return
	if args.has("--pengtest"):
		_peng_test()
		return
	if args.has("--autopeng"):
		auto_peng = true
		_auto_run()
		return
	if args.has("--fast"):
		Engine.time_scale = 8.0
	if args.has("--auto"):
		auto_pass = true
		_auto_run()
		return
	if args.has("--slowshot"):
		await get_tree().create_timer(18.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shot.png")
		get_tree().quit()
	if args.has("--shot"):
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shot.png")
		get_tree().quit()

# ────────────────────────── 局 ──────────────────────────
func _new_game() -> void:
	var all: Array = []
	for k in range(KINDS):
		for c in range(4):
			all.append(k)
	all.shuffle()
	wall = all
	for s in range(4):
		hands[s] = []
		rivers[s] = []
		melds[s] = []
	# 发牌：逆时针 0(你) → 1(下家) → 2(对家) → 3(上家)，每人一张，共 13 轮
	for r in range(13):
		for s in range(4):
			hands[s].append(wall.pop_back())
	dealer = clampi(dealer, 0, 3)
	hands[dealer].append(wall.pop_back())
	turn = dealer
	phase = "discard"
	game_over = false
	_win_context = {}
	_anim_draw = false
	_anim_deal = true
	if dealer == 0:
		drawn_index = hands[0].size() - 1
		_sort_hand(0)
		_anim_draw = true
		_set_state(St.HUMAN_DISCARD)
	else:
		drawn_index = -1
		_sort_hand(0)
		_set_state(St.AI_DISCARD, AI_THINK)
	evt_lines.clear()
	_ev("第 %d 局开始 · 庄家 %s · %s" % [hand_no, SEAT_NAMES[dealer], "请出牌" if dealer == 0 else "等待"])
	print("DEAL hand=", hand_no, " dealer=", dealer, " ai=", ai_level, " wall=", wall.size())

func _load_match_state() -> void:
	for path in [_save_path, _save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var raw := FileAccess.get_file_as_string(path)
		if raw.is_empty():
			continue
		var data: Variant = JSON.parse_string(raw)
		if not (data is Dictionary):
			continue
		var dict: Dictionary = data
		if int(dict.get("version", 0)) > SAVE_VERSION:
			continue
		var loaded_scores: Variant = dict.get("scores", [])
		if not (loaded_scores is Array) or loaded_scores.size() != 4:
			continue
		var arr: Array = loaded_scores
		for i in range(4):
			scores[i] = int(arr[i])
		dealer = clampi(int(dict.get("dealer", 0)), 0, 3)
		hand_no = maxi(1, int(dict.get("hand_no", 1)))
		ai_level = clampi(int(dict.get("ai_level", 1)), 0, 2)
		master_volume = clampf(float(dict.get("master_volume", 1.0)), 0.0, 1.0)
		_muted = bool(dict.get("muted", false))
		return

func _save_match_state() -> void:
	if not _persist_enabled:
		return
	var payload := {
		"version": SAVE_VERSION,
		"scores": scores.duplicate(),
		"dealer": dealer,
		"hand_no": hand_no,
		"ai_level": ai_level,
		"master_volume": master_volume,
		"muted": _muted,
	}
	var tmp := _save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("match save: cannot open temp file")
		return
	file.store_string(JSON.stringify(payload))
	file.close()
	var final_abs := ProjectSettings.globalize_path(_save_path)
	var bak_abs := ProjectSettings.globalize_path(_save_path + ".bak")
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(_save_path):
		if FileAccess.file_exists(_save_path + ".bak"):
			DirAccess.remove_absolute(bak_abs)
		DirAccess.rename_absolute(final_abs, bak_abs)
	var err := DirAccess.rename_absolute(tmp_abs, final_abs)
	if err != OK:
		push_warning("match save: cannot replace save file (%s)" % error_string(err))

func _record_win_result(seat: int, pay: Dictionary) -> void:
	var per := int(pay.get("per", 0))
	var total := int(pay.get("total", per * 3))
	for i in range(4):
		scores[i] += total if i == seat else -per
	if seat != dealer:
		dealer = (dealer + 1) % 4
	hand_no += 1
	_save_match_state()

func _record_kong_score(kind: String, seat: int, from_seat: int = -1) -> void:
	match kind:
		"angang":
			scores[seat] += 6
			_show_score_delta(seat, 6)
			for i in range(4):
				if i != seat:
					scores[i] -= 2
					_show_score_delta(i, -2)
		"bugang":
			scores[seat] += 3
			_show_score_delta(seat, 3)
			for i in range(4):
				if i != seat:
					scores[i] -= 1
					_show_score_delta(i, -1)
		"gang":
			scores[seat] += 3
			_show_score_delta(seat, 3)
			if from_seat >= 0 and from_seat != seat:
				scores[from_seat] -= 3
				_show_score_delta(from_seat, -3)
		_:
			return
	_save_match_state()
	_update_match_hud()

func _record_rob_result(seat: int, payer: int) -> void:
	scores[seat] += 20
	if payer >= 0 and payer != seat:
		scores[payer] -= 20
	if seat != dealer:
		dealer = (dealer + 1) % 4
	hand_no += 1
	_save_match_state()

func _record_draw_result() -> void:
	hand_no += 1
	_save_match_state()

func _update_match_hud() -> void:
	if _round_label == null:
		return
	var prefix := "下一局  ·  " if game_over else ""
	_round_label.text = "%s第 %d 局  ·  庄家：%s" % [prefix, hand_no, SEAT_NAMES[dealer]]
	if _score_label == null:
		return
	var parts := PackedStringArray()
	for i in range(4):
		var value: int = scores[i]
		var sign := "+" if value > 0 else ""
		parts.append("%s %s%d" % [SEAT_NAMES[i], sign, value])
	_score_label.text = "  ·  ".join(parts)

func _seat_screen_pos(seat: int) -> Vector2:
	var viewport_size := Vector2(1240, 860)
	if _hud_root and _hud_root.size.x > 0 and _hud_root.size.y > 0:
		viewport_size = _hud_root.size
	elif get_viewport():
		viewport_size = get_viewport().get_visible_rect().size
	match seat:
		0:
			return Vector2(viewport_size.x * 0.5, viewport_size.y * 0.92)
		1:
			return Vector2(viewport_size.x * 0.9, viewport_size.y * 0.45)
		2:
			return Vector2(viewport_size.x * 0.5, viewport_size.y * 0.16)
		_:
			return Vector2(viewport_size.x * 0.1, viewport_size.y * 0.45)

func _show_score_delta(seat: int, delta: int) -> void:
	if _hud_root == null or delta == 0:
		return
	var color := Color(0.62, 1.0, 0.70) if delta > 0 else Color(1.0, 0.52, 0.43)
	var text := "%s %s%d" % [SEAT_NAMES[seat], "+" if delta > 0 else "", delta]
	var label := _ui_label(text, 18, color)
	label.name = "ScoreDelta"
	label.set_meta("score_delta", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(140, 30)
	var start := _seat_screen_pos(seat) - Vector2(70, 15)
	label.position = start
	_hud_root.add_child(label)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", start.y - 55.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tw.chain().tween_callback(label.queue_free)

func _ai_level_name() -> String:
	return ["轻松", "标准", "挑战"][clampi(ai_level, 0, 2)]

func _refresh_ai_buttons() -> void:
	if _ai_buttons.is_empty():
		return
	var names := ["轻松", "标准", "挑战"]
	for i in range(_ai_buttons.size()):
		var button := _ai_buttons[i]
		var selected := i == ai_level
		button.text = names[i] + ("  ✓" if selected else "")
		_style_button(
			button,
			Color(0.27, 0.38, 0.28) if selected else Color(0.07, 0.12, 0.10),
			Color(0.82, 0.64, 0.32) if selected else Color(0.35, 0.43, 0.38),
		)
		button.add_theme_font_size_override("font_size", 13)

func _set_ai_level(level: int) -> void:
	ai_level = clampi(level, 0, 2)
	_save_match_state()
	_refresh_ai_buttons()
	if _rules_text:
		_rules_text.text = _rules_content()

func _rules_content() -> String:
	var score_parts := PackedStringArray()
	for i in range(4):
		score_parts.append("%s %d" % [SEAT_NAMES[i], scores[i]])
	var phase_label: String = "下一局" if game_over else "当前"
	return "\n".join([
		"[color=#f2c66e]胡牌[/color]  仅限自摸或抢杠胡；弃牌不能胡，没有点炮。",
		"[color=#f2c66e]天胡[/color]  庄家起手 14 张成牌，直接按自摸计分。",
		"[color=#f2c66e]碰杠[/color]  可响应弃牌；补杠可被抢杠；暗杠不可抢。",
		"[color=#f2c66e]胡牌分[/color]  自摸：小胡 4 分/家、碰碰胡 8、七对 16、龙七对 32；抢杠：杠者单独承包 20 分。",
		"[color=#f2c66e]杠分[/color]  暗杠 +6（其余三家各 -2）；放杠 +3（放杠者 -3）；碰后补杠 +3（其余三家各 -1）。",
		"[color=#f2c66e]抢杠[/color]  被抢的杠不计杠分，改为杠者单独付 20 分，其他两家不付。",
		"[color=#f2c66e]庄家[/color]  庄家胡牌连庄，其他家胡牌由下家坐庄；流局连庄。",
		"[color=#f2c66e]AI[/color]  难度：%s（挑战档会用向听数选择弃牌）。" % _ai_level_name(),
		"",
		"[color=#f2c66e]%s[/color]  第 %d 局 · 庄家 %s" % [phase_label, hand_no, SEAT_NAMES[dealer]],
		"          %s" % " · ".join(score_parts),
		"[color=#81928a]每局结束与每次杠后自动保存；重置需要在规则面板确认。[/color]",
		"",
		"[color=#f2c66e]操作[/color]",
		"左键出牌 · P 碰 · G 杠 · Esc 暂停/过 · R 规则 · M 静音 · F11 全屏",
	])

func _open_rules() -> void:
	if _rules_overlay == null:
		return
	_rules_open = true
	if _rules_text:
		_rules_text.text = _rules_content()
	_rules_overlay.visible = true
	_set_hovered_hand(-1)
	if _rules_close:
		_rules_close.grab_focus()

func _close_rules() -> void:
	_rules_open = false
	if _rules_overlay:
		_rules_overlay.visible = false
	if _rules_close:
		_rules_close.release_focus()
	if _main_menu_open and _main_menu_start:
		_main_menu_start.grab_focus()
	elif _pause_open and _pause_resume:
		_pause_resume.grab_focus()

func _toggle_rules() -> void:
	if _rules_open:
		_close_rules()
	else:
		_open_rules()

func _reset_match() -> void:
	scores = [0, 0, 0, 0]
	dealer = 0
	hand_no = 1
	_save_match_state()
	_close_rules()
	_hide_claim()
	_set_hovered_hand(-1)
	game_over = false
	_win_context = {}
	if _result_overlay:
		_result_overlay.visible = false
	if big:
		big.visible = false
	if result_detail:
		result_detail.visible = false
	if restart_btn:
		restart_btn.visible = false
	_new_game()
	_build()
	_check_initial_win()
	_toast("比赛已重置")

func _count_in(arr: Array, t: int) -> int:
	var n := 0
	for x in arr:
		if x == t:
			n += 1
	return n

## 理牌：按花色/数字排序，刚摸到的单独放到最右
func _sort_hand(seat: int) -> void:
	if hands[seat].is_empty():
		return
	var drawn := -1
	if seat == 0 and drawn_index >= 0 and drawn_index < hands[seat].size():
		drawn = int(hands[seat][drawn_index])
		hands[seat].remove_at(drawn_index)
	hands[seat].sort()
	if drawn >= 0:
		hands[seat].append(drawn)
		if seat == 0:
			drawn_index = hands[seat].size() - 1
	elif seat == 0:
		drawn_index = -1

func _draw_for(seat: int) -> bool:
	if wall.is_empty():
		_finish("牌墙摸完 · 流局")
		return false
	hands[seat].append(wall.pop_back())
	if seat == 0:
		drawn_index = hands[0].size() - 1
		_sort_hand(0)
	_anim_draw = true
	_play("draw", -16.0)
	return true

func _self_draw_win(seat: int) -> bool:
	if hands[seat].is_empty():
		return false
	var ev: Dictionary = MJRules.evaluate(hands[seat], melds[seat])
	if ev.is_empty():
		return false
	_win(seat, int(hands[seat].back()), ev, true)
	return true

# ══════════════════ 回合状态机（不使用 await）══════════════════
# 所有推进由 _process 驱动：AI 摸牌 → AI 出牌 → 停 1 秒 → 碰杠判定 → 下一家
enum St { HUMAN_DISCARD, AI_DRAW, AI_DISCARD, CLAIM_WAIT, HUMAN_CLAIM, OVER }

var st: int = St.HUMAN_DISCARD
var st_deadline := 0.0
var _claim_from := -1
var _claim_tile := -1

func _set_state(s: int, t: float = 0.0) -> void:
	st = s
	st_deadline = Time.get_ticks_msec() * 0.001 + t

func _player_discard(idx: int) -> void:
	if game_over or turn != 0 or st != St.HUMAN_DISCARD:
		return
	if idx < 0 or idx >= hands[0].size():
		return
	var t: int = int(hands[0].pop_at(idx))
	rivers[0].append(t)
	_ev("%s 打 %s" % [SEAT_NAMES[0], TILE_NAMES[t]])
	_last_discard_seat = 0
	_drop_seat = 0
	_play("discard", -8.0)
	_add_trauma(0.06)
	_set_hovered_hand(-1)
	_announce(t)
	drawn_index = -1
	_build()
	_enter_claim(0, t)

## 出牌后进入「等待」：停 CLAIM_DELAY 秒，让播报念完、玩家看清是谁打的
func _enter_claim(from_seat: int, tile: int) -> void:
	_claim_from = from_seat
	_claim_tile = tile
	_set_state(St.CLAIM_WAIT, CLAIM_DELAY)

## 兼容旧调用
func _after_discard(from_seat: int, tile: int) -> void:
	_enter_claim(from_seat, tile)

func _resolve_claims() -> void:
	if game_over:
		return
	var from_seat := _claim_from
	var tile := _claim_tile
	if from_seat < 0:
		return

	# 本规则只有自摸与抢杠胡：打出的牌不能胡，只处理碰/杠。
	# ③ 人类碰 / 杠
	var opts: Array = []
	if _count_in(hands[0], tile) == 3:
		opts.append("gang")
	if _count_in(hands[0], tile) >= 2:
		opts.append("peng")
	if from_seat != 0 and not opts.is_empty():
		_offer_human(opts)
		return

	# ④ 交给 AI
	_ai_claims()

## 摸完牌后：有补杠/暗杠就询问
func _offer_self_kong(seat: int) -> void:
	var opts: Array = []
	var bg := _bugang_tile(seat)
	var ag := _angang_tile(seat)
	if bg >= 0:
		opts.append("bugang")
	if ag >= 0:
		opts.append("angang")
	if opts.is_empty():
		return
	_human_pending = { "opts": opts, "self": true, "bg": bg, "ag": ag }
	if auto_peng:
		_on_claim(opts[0])
	else:
		_set_state(St.HUMAN_CLAIM)
		_show_claim(opts)

func _offer_human(opts: Array) -> void:
	_human_pending = { "opts": opts }
	if auto_peng:
		_on_claim(opts[0])
	else:
		_set_state(St.HUMAN_CLAIM)
		_show_claim(opts)

func _ai_claims() -> void:
	var from_seat := _claim_from
	var tile := _claim_tile
	# AI 杠
	for k in range(1, 4):
		var s2 := (from_seat + k) % 4
		if s2 == 0:
			continue
		if _count_in(hands[s2], tile) == 3:
			for i in range(3):
				hands[s2].erase(tile)
			melds[s2].append({ "type": "gang", "tiles": [tile, tile, tile, tile] })
			if rivers[from_seat].size() > 0:
				rivers[from_seat].pop_back()
			_record_kong_score("gang", s2, from_seat)
			_play("gang", -4.0)
			_add_trauma(0.16)
			_say_after("vo_gang")
			_toast("%s 杠 %s · +3" % [SEAT_NAMES[s2], TILE_NAMES[tile]])
			_ev(">>> %s 杠 %s · +3" % [SEAT_NAMES[s2], TILE_NAMES[tile]])
			if not _draw_for(s2):
				return
			if _self_draw_win(s2):
				return
			turn = s2
			phase = "discard"
			_set_state(St.AI_DISCARD, AI_THINK)
			_build()
			return
	# AI 碰
	for k in range(1, 4):
		var s3 := (from_seat + k) % 4
		if s3 == 0:
			continue
		if _count_in(hands[s3], tile) >= 2:
			hands[s3].erase(tile)
			hands[s3].erase(tile)
			melds[s3].append({ "type": "peng", "tiles": [tile, tile, tile] })
			if rivers[from_seat].size() > 0:
				rivers[from_seat].pop_back()
			_play("peng", -4.0)
			_add_trauma(0.13)
			_say_after("vo_peng")
			_toast("%s 碰 %s" % [SEAT_NAMES[s3], TILE_NAMES[tile]])
			_ev(">>> %s 碰 %s" % [SEAT_NAMES[s3], TILE_NAMES[tile]])
			turn = s3
			phase = "discard"
			_set_state(St.AI_DISCARD, AI_THINK)
			_build()
			return
	# 没人要 → 下一家
	turn = (from_seat + 1) % 4
	_go_draw()

## 补杠：手上有牌能和已有「碰」凑成 4 张
func _bugang_tile(seat: int) -> int:
	for m in melds[seat]:
		if m["type"] == "peng":
			var t: int = int(m["tiles"][0])
			if _count_in(hands[seat], t) >= 1:
				return t
	return -1

## 暗杠：自己手里凑齐 4 张
func _angang_tile(seat: int) -> int:
	var seen := {}
	for x in hands[seat]:
		var t: int = int(x)
		seen[t] = int(seen.get(t, 0)) + 1
		if int(seen[t]) == 4:
			return t
	return -1

## 执行杠（type: bugang / angang），并从牌尾补一张
func _do_self_kong(seat: int, tile: int, kind: String) -> void:
	# 抢杠：补杠的牌若被别人胡，则杠作废，改判抢杠胡（暗杠不可抢）
	if kind == "bugang":
		if seat != 0:
			var ph: Array = hands[0].duplicate()
			ph.append(tile)
			var eh: Dictionary = MJRules.evaluate(ph, melds[0])
			if not eh.is_empty():
				hands[0] = ph
				_ev(">>> 你 抢杠 %s" % TILE_NAMES[tile])
				_win(0, tile, eh, false, seat)
				return
		for k in range(1, 4):
			var sr := (seat + k) % 4
			if sr == seat:
				continue
			var pr: Array = hands[sr].duplicate()
			pr.append(tile)
			var er: Dictionary = MJRules.evaluate(pr, melds[sr])
			if not er.is_empty():
				hands[sr] = pr
				_ev(">>> %s 抢杠 %s" % [SEAT_NAMES[sr], TILE_NAMES[tile]])
				_win(sr, tile, er, false, seat)
				return
	if kind == "bugang":
		for i in range(melds[seat].size()):
			if melds[seat][i]["type"] == "peng" and int(melds[seat][i]["tiles"][0]) == tile:
				melds[seat][i] = { "type": "gang", "tiles": [tile, tile, tile, tile] }
				break
		hands[seat].erase(tile)
	else:
		for i in range(4):
			hands[seat].erase(tile)
		melds[seat].append({ "type": "gang", "tiles": [tile, tile, tile, tile] })
	_record_kong_score(kind, seat)
	var gain := 6 if kind == "angang" else 3
	_say_after("vo_gang")
	_play("gang", -2.0)
	_add_trauma(0.15)
	_toast("%s %s %s · +%d" % [SEAT_NAMES[seat], "补杠" if kind == "bugang" else "暗杠", TILE_NAMES[tile], gain])
	_ev(">>> %s %s %s · +%d" % [SEAT_NAMES[seat], "补杠" if kind == "bugang" else "暗杠", TILE_NAMES[tile], gain])
	# 从牌尾补一张
	if wall.is_empty():
		_finish("牌墙摸完 · 流局")
		return
	hands[seat].append(wall.pop_front())
	_sort_hand(seat)
	if _self_draw_win(seat):
		return
	if seat == 0:
		drawn_index = -1
		turn = 0
		phase = "discard"
		_set_state(St.HUMAN_DISCARD)
		_build()
	else:
		turn = seat
		phase = "discard"
		_set_state(St.AI_DISCARD, AI_THINK)
		_build()
func _go_draw() -> void:
	phase = "draw"
	if turn == 0:
		if not _draw_for(0):
			_set_state(St.OVER)
			return
		if _self_draw_win(0):
			return
		phase = "discard"
		_set_state(St.HUMAN_DISCARD)
		_build()
		_offer_self_kong(0)
	else:
		_set_state(St.AI_DRAW, AI_DRAW_DELAY)
		_build()

func _do_ai_draw() -> void:
	if not _draw_for(turn):
		_set_state(St.OVER)
		return
	var seat := turn
	if _self_draw_win(seat):
		return
	# AI 自己杠：暗杠优先，其次补杠
	var ag := _angang_tile(seat)
	var bg := _bugang_tile(seat)
	if (ag >= 0 or bg >= 0) and randf() < 0.8:
		if ag >= 0:
			_do_self_kong(seat, ag, "angang")
		else:
			_do_self_kong(seat, bg, "bugang")
		return
	phase = "discard"
	_set_state(St.AI_DISCARD, AI_THINK)
	_build()

func _visible_tile_count(t: int, concealed: Array) -> int:
	var n := _count_in(concealed, t)
	for s in range(4):
		n += _count_in(rivers[s], t)
		for m in melds[s]:
			n += _count_in(m["tiles"], t)
	return n

## 14 张上手后，估算「留下这些牌」的搭子/对子质量。数值只用于 AI 比较，不参与规则。
func _shape_score(tiles: Array) -> float:
	var counts: Dictionary = MJRules.counts(tiles)
	var score := 0.0
	var pairs := 0
	for raw_t in counts.keys():
		var t := int(raw_t)
		var n := int(counts[raw_t])
		if n >= 3:
			score += 26.0
			if n == 4:
				score += 6.0
		elif n == 2:
			score += 11.0
			pairs += 1
		if t >= 27:
			if n == 1:
				score -= 1.5
			continue
		var base := t - t % 9
		for d in [-2, -1, 1, 2]:
			var nt: int = t + int(d)
			if nt < base or nt >= base + 9:
				continue
			if counts.has(nt):
				score += 4.5 if abs(d) == 1 else 1.8
	if pairs >= 3:
		score += float(pairs) * 2.5
	return score

func _ai_discard_score(concealed: Array, seat: int) -> float:
	var score := _shape_score(concealed)
	var waits: Array = MJRules.waits(concealed, melds[seat])
	if not waits.is_empty():
		var live := 0
		for t in waits:
			live += maxi(0, 4 - _visible_tile_count(int(t), concealed))
		score += 10000.0 + float(live) * 120.0
	return score

func _ai_choose_discard(seat: int) -> int:
	if hands[seat].is_empty():
		return 0
	if ai_level == 0:
		return randi() % hands[seat].size()
	var best_indices: Array[int] = []
	var best_score := -1.0e20
	var shanten_cache := {}
	for i in range(hands[seat].size()):
		var probe: Array = hands[seat].duplicate()
		probe.remove_at(i)
		var score := _ai_discard_score(probe, seat)
		if ai_level >= 2:
			score += -float(MJRules.shanten(probe, melds[seat], shanten_cache)) * 3000.0
		if score > best_score + 0.0001:
			best_score = score
			best_indices = [i]
		elif abs(score - best_score) <= 0.0001:
			best_indices.append(i)
	if best_indices.is_empty():
		return 0
	return int(best_indices[randi() % best_indices.size()])

func _do_ai_discard() -> void:
	var seat := turn
	if hands[seat].is_empty():
		return
	var best := _ai_choose_discard(seat)
	var tile: int = int(hands[seat].pop_at(best))
	rivers[seat].append(tile)
	_ev("%s 打 %s" % [SEAT_NAMES[seat], TILE_NAMES[tile]])
	_last_discard_seat = seat
	_drop_seat = seat
	_play("discard", -13.0)
	_add_trauma(0.035)
	_announce(tile)
	_build()
	_enter_claim(seat, tile)

func _process(delta: float) -> void:
	_update_camera_shake(delta)
	if _rules_open or _main_menu_open or _pause_open or _settings_open:
		return
	if game_over or st == St.OVER:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now < st_deadline:
		return
	match st:
		St.AI_DRAW:
			_do_ai_draw()
		St.AI_DISCARD:
			_do_ai_discard()
		St.CLAIM_WAIT:
			_resolve_claims()
		_:
			pass
func _ev(msg: String) -> void:
	evt_lines.append(msg)
	if evt_lines.size() > 5:
		evt_lines.pop_front()
	_render_event_log()

func _render_event_log() -> void:
	if evt_log == null:
		return
	if evt_lines.is_empty():
		evt_log.text = "[color=#687872]新局开始 · 等待出牌[/color]"
		return
	var blocks := PackedStringArray()
	for line in evt_lines:
		var color := "#d8e4df"
		if line.begins_with(">>>"):
			color = "#f1cb73"
		elif line.begins_with("你"):
			color = "#9fe0c4"
		elif line.contains("胡"):
			color = "#ffd39a"
		blocks.append("[color=%s]%s[/color]" % [color, line])
	evt_log.text = "\n".join(blocks)

func _toast(msg: String) -> void:
	if toast == null or _toast_panel == null:
		return
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.text = msg
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	_toast_panel.scale = Vector2(0.96, 0.96)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.12)
	_toast_tween.parallel().tween_property(_toast_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.45)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.22)
	_toast_tween.tween_callback(func():
		if _toast_panel:
			_toast_panel.visible = false
	)

func _tile_slot_style(highlight: bool, meld: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.085, 0.075, 0.96)
	var border := Color(0.38, 0.44, 0.40, 0.72)
	if meld:
		border = Color(0.60, 0.51, 0.30, 0.82)
	if highlight:
		border = Color(0.96, 0.73, 0.30, 1.0)
	s.border_color = border
	s.set_border_width_all(2 if highlight else 1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 1.0
	s.content_margin_right = 1.0
	s.content_margin_top = 1.0
	s.content_margin_bottom = 1.0
	return s

func _make_result_tile(kind: int, highlight: bool = false, meld: bool = false) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(32, 44)
	slot.tooltip_text = TILE_NAMES[kind]
	slot.add_theme_stylebox_override("panel", _tile_slot_style(highlight, meld))
	var tex := load("res://faces/%s.png" % _face_key(kind)) as Texture2D
	if tex:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(28, 40)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(img)
	else:
		var fallback := _ui_label(TILE_NAMES[kind], 10, Color(0.95, 0.92, 0.82))
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(fallback)
	return slot

func _showdown_source_text() -> String:
	if _win_context.is_empty():
		return ""
	var seat: int = int(_win_context.get("seat", -1))
	var tile: int = int(_win_context.get("tile", -1))
	var self_draw: bool = bool(_win_context.get("self_draw", false))
	var initial_deal: bool = bool(_win_context.get("initial_deal", false))
	var from_seat: int = int(_win_context.get("from", -1))
	var kind: String = str(_win_context.get("kind", "rob"))
	var meld_info: String = ""
	if not melds[seat].is_empty():
		meld_info = " · 副露 %d 组" % melds[seat].size()
	if initial_deal:
		return "天胡验证：%s 起手 14 张即和牌\n金框为和牌张 · 暗手 %d 张%s" % [SEAT_NAMES[seat], hands[seat].size(), meld_info]
	if self_draw:
		return "自摸验证：%s 从牌墙摸入「%s」\n金框为和牌张 · 暗手 %d 张%s" % [SEAT_NAMES[seat], TILE_NAMES[tile], hands[seat].size(), meld_info]
	if kind == "rob" and from_seat >= 0:
		return "抢杠来源：%s 补杠「%s」\n金框为和牌张 · %s 抢杠和牌%s" % [SEAT_NAMES[from_seat], TILE_NAMES[tile], SEAT_NAMES[seat], meld_info]
	return "和牌张：%s\n金框为和牌张 · %s 和牌%s" % [TILE_NAMES[tile], SEAT_NAMES[seat], meld_info]

func _populate_showdown() -> void:
	if result_hands_box == null or _win_context.is_empty():
		return
	for c in result_hands_box.get_children():
		result_hands_box.remove_child(c)
		c.queue_free()
	var winner: int = int(_win_context.get("seat", -1))
	var win_tile: int = int(_win_context.get("tile", -1))
	var self_draw: bool = bool(_win_context.get("self_draw", false))
	var initial_deal: bool = bool(_win_context.get("initial_deal", false))
	for seat in range(4):
		var is_winner := seat == winner
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var name := _ui_label(SEAT_NAMES[seat], 14, Color(1.0, 0.82, 0.46) if is_winner else Color(0.78, 0.86, 0.82))
		name.custom_minimum_size = Vector2(48, 0)
		row.add_child(name)
		var std_count: int = hands[seat].size() + melds[seat].size() * 3
		var status_text: String = "%d 张" % std_count
		if is_winner:
			var source_name := "天胡" if initial_deal else ("自摸" if self_draw else "抢杠")
			status_text = "%s · %d 张" % [source_name, std_count]
		var status := _ui_label(status_text, 11, Color(1.0, 0.84, 0.52) if is_winner else Color(0.62, 0.71, 0.66))
		status.custom_minimum_size = Vector2(86, 0)
		row.add_child(status)

		var concealed: Array = hands[seat].duplicate()
		var win_at := -1
		if is_winner:
			for i in range(concealed.size() - 1, -1, -1):
				if int(concealed[i]) == win_tile:
					win_at = i
					break
			if win_at >= 0:
				concealed.remove_at(win_at)
		concealed.sort()
		for tile in concealed:
			row.add_child(_make_result_tile(int(tile)))
		if is_winner:
			if win_at >= 0:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(7, 0)
				row.add_child(gap)
				row.add_child(_make_result_tile(win_tile, true))
				var cap := _ui_label("自摸牌" if self_draw else "和牌张", 10, Color(1.0, 0.84, 0.52))
				cap.custom_minimum_size = Vector2(42, 0)
				cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				row.add_child(cap)
		if not melds[seat].is_empty():
			var gap2 := Control.new()
			gap2.custom_minimum_size = Vector2(8, 0)
			row.add_child(gap2)
			var meld_cap := _ui_label("副露", 10, Color(0.73, 0.64, 0.42))
			meld_cap.custom_minimum_size = Vector2(26, 0)
			meld_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(meld_cap)
			for m in melds[seat]:
				for tile in m["tiles"]:
					row.add_child(_make_result_tile(int(tile), false, true))
				var mgap := Control.new()
				mgap.custom_minimum_size = Vector2(3, 0)
				row.add_child(mgap)
		result_hands_box.add_child(row)

func _show_result(title: String, detail: String) -> void:
	_hide_claim()
	_set_hovered_hand(-1)
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	if _toast_panel:
		_toast_panel.visible = false
	var showdown := not _win_context.is_empty()
	if _result_panel:
		_result_panel.custom_minimum_size = Vector2(960, 580) if showdown else Vector2(540, 320)
		_result_panel.pivot_offset = Vector2(480, 290) if showdown else Vector2(270, 160)
	if big:
		big.text = title
		big.add_theme_font_size_override("font_size", 40 if showdown else 46)
		big.add_theme_color_override("font_color", Color(1.0, 0.83, 0.45) if title.contains("胡") or title.contains("自摸") else Color(0.85, 0.90, 0.86))
		big.visible = true
	if result_detail:
		result_detail.text = detail
		result_detail.add_theme_font_size_override("font_size", 15 if showdown else 20)
		result_detail.custom_minimum_size = Vector2(0, 48 if showdown else 72)
		result_detail.visible = true
	if result_source:
		result_source.visible = showdown
		result_source.text = _showdown_source_text() if showdown else ""
	if result_hands_panel:
		result_hands_panel.visible = showdown
		if showdown:
			_populate_showdown()
		else:
			for c in result_hands_box.get_children():
				result_hands_box.remove_child(c)
				c.queue_free()
	if restart_btn:
		restart_btn.visible = true
	if _result_overlay and _result_panel:
		_result_overlay.visible = true
		_result_overlay.modulate.a = 0.0
		_result_panel.scale = Vector2(0.94, 0.94)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_result_overlay, "modulate:a", 1.0, 0.18)
		tw.tween_property(_result_panel, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if restart_btn:
			restart_btn.call_deferred("grab_focus")

func _restart() -> void:
	_set_hovered_hand(-1)
	_hide_claim()
	_shake_trauma = 0.0
	if cam:
		cam.position = _cam_base_pos
	if _result_overlay:
		_result_overlay.visible = false
	if big:
		big.visible = false
	if result_detail:
		result_detail.visible = false
	if restart_btn:
		restart_btn.visible = false
	if _toast_panel:
		_toast_panel.visible = false
	_new_game()
	_build()
	_check_initial_win()

func _win(seat: int, tile: int, ev: Dictionary, self_draw: bool = false, from_seat: int = -1, initial_deal: bool = false) -> void:
	game_over = true
	var kind: String = "deal" if initial_deal else ("self" if self_draw else "rob")
	_win_context = {
		"seat": seat,
		"tile": tile,
		"ev": ev,
		"self_draw": self_draw,
		"from": from_seat,
		"kind": kind,
		"initial_deal": initial_deal,
	}
	_add_trauma(0.58 if not self_draw else 0.66)
	_play("hu", 0.0)
	_say("vo_zimo" if self_draw or initial_deal else "vo_hu")
	var who: String = ["你", "下家", "对家", "上家"][seat]
	var title := ""
	var detail := ""
	if kind == "rob":
		_record_rob_result(seat, from_seat)
		var payer: String = SEAT_NAMES[from_seat] if from_seat >= 0 else "杠者"
		title = "%s 抢杠胡！" % who
		detail = "%s\n抢杠 · %s 承包 20 分" % [ev["name"], payer]
	else:
		var pay: Dictionary = MJRules.payout(ev["tier"], STAKE)
		_record_win_result(seat, pay)
		title = ("%s 天胡！" % who) if initial_deal else ("%s 自摸！" % who)
		detail = "%s\n每家 %d 分 · 三家共 %d 分" % [ev["name"], pay["per"], pay["total"]]
	_show_result(title, detail)
	_build()
	print("WIN seat=", seat, " self_draw=", self_draw, " initial_deal=", initial_deal, " kind=", kind, " name=", ev["name"], " tile=", tile, " scores=", scores)

func _finish(msg: String) -> void:
	if not game_over:
		_record_draw_result()
	game_over = true
	_win_context = {}
	_show_result(msg, "")
	_update_hud()

# ────────────────────────── 场景 ──────────────────────────
func _fix_window_title() -> void:
	await get_tree().create_timer(0.4).timeout
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("重生2 · 3D麻将")

func _materials() -> void:
	mat_ivory = StandardMaterial3D.new()
	mat_ivory.albedo_color = Color(0.97, 0.955, 0.905)
	mat_ivory.roughness = 0.55
	mat_green = StandardMaterial3D.new()
	mat_green.albedo_color = Color(0.10, 0.52, 0.28)
	mat_green.roughness = 0.5
	mat_felt = StandardMaterial3D.new()
	mat_felt.albedo_color = Color(0.055, 0.30, 0.285)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.85
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	mat_felt.albedo_texture = nt
	mat_felt.uv1_scale = Vector3(34, 34, 34)
	mat_felt.roughness = 0.96
	mat_back = StandardMaterial3D.new()
	mat_back.albedo_color = Color(0.10, 0.52, 0.28)
	mat_back.roughness = 0.5
	mat_groove = StandardMaterial3D.new()
	mat_groove.albedo_color = Color(0.30, 0.29, 0.26)
	mat_groove.roughness = 0.9
	mat_plate = StandardMaterial3D.new()
	mat_plate.albedo_color = Color(1.0, 0.985, 0.955)
	mat_plate.roughness = 0.38
	mat_gold = StandardMaterial3D.new()
	mat_gold.albedo_color = Color(0.72, 0.55, 0.20)
	mat_gold.metallic = 0.75
	mat_gold.roughness = 0.32

	mat_rim = StandardMaterial3D.new()
	mat_rim.albedo_color = Color(0.185, 0.105, 0.062)
	mat_rim.roughness = 0.55

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.66, 0.72)
	env.ambient_light_energy = 0.66
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_radius = 26.0
	env.ssao_intensity = 1.9
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.06
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-62, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.position = Vector3(0, CAM_H, CAM_D)
	_cam_base_pos = cam.position
	cam.fov = CAM_FOV
	cam.near = 1.0
	cam.far = 6000.0
	add_child(cam)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)

func _box(size: Vector3, pos: Vector3, ry: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = ry
	board.add_child(mi)
	return mi

func _face_key(kind: int) -> String:
	if kind < 9:
		return "wan_%d" % (kind + 1)
	if kind < 18:
		return "tong_%d" % (kind - 8)
	if kind < 27:
		return "tiao_%d" % (kind - 17)
	var honor := ["feng_dong", "feng_nan", "feng_xi", "feng_bei", "jian_zhong", "jian_fa", "jian_bai"]
	return honor[kind - 27]

func _face_quad(kind: int, pos: Vector3, size: Vector2, rot: Vector3) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := StandardMaterial3D.new()
	var tex = load("res://faces/%s.png" % _face_key(kind))
	if tex:
		m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = m
	q.position = pos
	q.rotation = rot
	board.add_child(q)

# ────────────────────────── 重建 ──────────────────────────
func _build() -> void:
	_hand_nodes.clear()
	_hovered_index = -1
	if _hover_label:
		_hover_label.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if board and is_instance_valid(board):
		board.visible = false
		board.queue_free()
	board = Node3D.new()
	board.name = "Board"
	add_child(board)
	_box(Vector3(1300, 46, 1090), Vector3(0, -24, 0), 0, mat_rim)
	_box(Vector3(1210, 26, 1010), Vector3(0, -13, 0), 0, mat_felt)
# 桌面金边
	_box(Vector3(1150, 2, 3), Vector3(0, 0.6, 468), 0, mat_gold)
	_box(Vector3(1150, 2, 3), Vector3(0, 0.6, -468), 0, mat_gold)
	_box(Vector3(3, 2, 940), Vector3(577, 0.6, 0), 0, mat_gold)
	_box(Vector3(3, 2, 940), Vector3(-577, 0.6, 0), 0, mat_gold)

	_build_wall()
	_build_rivers()
	_build_hand()
	_build_other_hands()
	_build_melds()
	_build_center()
	_build_seats()
	_drop_seat = -1
	_anim_draw = false
	_anim_deal = false
	_update_hud()


## 把一个牌的所有零件装进同一个容器，方便整体做补间
func _tile_group(pos: Vector3, ry: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = ry
	board.add_child(root)
	return root

func _part(root: Node3D, size: Vector3, off: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = off
	root.add_child(mi)

func _part_face(root: Node3D, kind: int, off: Vector3, size: Vector2, rot: Vector3) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := StandardMaterial3D.new()
	var tex = load("res://faces/%s.png" % _face_key(kind))
	if tex:
		m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 牌面图 224×312 缩到 ~34px：必须开各向异性 + mipmap，否则糊成一片
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	q.material_override = m
	q.position = off
	q.rotation = rot
	root.add_child(q)

## 立着的牌（手牌）：牌厚 = HAND_T，凹槽和面片贴在正面外侧
func _tile_upright(pos: Vector3, kind: int, sc: float = 1.0) -> Node3D:
	var root := _tile_group(pos, 0.0)
	root.scale = Vector3.ONE * sc
	root.rotation.x = deg_to_rad(-HAND_TILT)
	var T := HAND_T
	var F := T * 0.5                       # 正面所在的 z
	_part(root, Vector3(HAND_W, HAND_H * 0.80, T), Vector3(0, -HAND_H * 0.10, 0), mat_ivory)
	_part(root, Vector3(HAND_W - 1.8, HAND_H * 0.20, T - 1.6), Vector3(0, HAND_H * 0.40, 0), mat_ivory)
	_part(root, Vector3(HAND_W - 3.0, HAND_H - 3.0, 1.2), Vector3(0, 0, F + 0.6), mat_groove)
	_part(root, Vector3(HAND_W - 5.0, HAND_H - 5.0, 1.2), Vector3(0, 0, F + 1.4), mat_plate)
	_part_face(root, kind, Vector3(0, 0, F + 2.1), Vector2(HAND_W - 6.0, HAND_H - 6.0), Vector3.ZERO)
	return root

## 平躺的牌（牌河 / 副露）：牌厚 = SIDE_T，底面贴桌
func _tile_flat(pos: Vector3, ry: float, kind: int, sc: float = 1.0) -> Node3D:
	var root := _tile_group(pos, ry)
	root.scale = Vector3.ONE * sc
	var T := SIDE_T
	_part(root, Vector3(RIVER_S, T, RIVER_S), Vector3(0, T * 0.5, 0), mat_ivory)
	_part(root, Vector3(RIVER_S - 3.0, 1.2, RIVER_S - 3.0), Vector3(0, T + 0.6, 0), mat_groove)
	_part(root, Vector3(RIVER_S - 5.0, 1.2, RIVER_S - 5.0), Vector3(0, T + 1.4, 0), mat_plate)
	_part_face(root, kind, Vector3(0, T + 2.1, 0), Vector2(RIVER_S - 9, RIVER_S - 9), Vector3(-PI * 0.5, 0, 0))
	return root
func _build_wall() -> void:
	var slots: Array = []
	var step := TW + GAP
	var half := (PER_SIDE - 1) * step * 0.5
	for side in ["top", "right", "bottom", "left"]:
		for k in range(PER_SIDE):
			var idx: int = (PER_SIDE - 1 - k) if (side == "bottom" or side == "left") else k
			var off: float = idx * step - half
			var p := Vector3.ZERO
			var ry := 0.0
			if side == "top":
				p = Vector3(off, 0, -(RINY + TD * 0.5))
			elif side == "bottom":
				p = Vector3(off, 0, RINY + TD * 0.5)
			elif side == "left":
				p = Vector3(-(RINX + TD * 0.5), 0, off)
				ry = PI * 0.5
			else:
				p = Vector3(RINX + TD * 0.5, 0, off)
				ry = PI * 0.5
			slots.append({ "pos": p, "ry": ry })
	var remain: int = wall.size()
	var keep: int = int(ceil(remain / 2.0))
	if keep <= 0:
		return
	var use: Array = slots.slice(max(0, slots.size() - keep), slots.size())
	# 余牌为奇数时，破墙那一墩只剩下面一张（上面那张已被摸走）
	for k in range(use.size()):
		var s = use[k]
		var layers := 2
		if remain % 2 == 1 and k == 0:
			layers = 1
		for i in range(layers):
			var y0 := i * (TH + 0.8)
			_box(Vector3(TW, TH, TD), s["pos"] + Vector3(0, y0 + TH * 0.5, 0), s["ry"], mat_ivory)
			_box(Vector3(TW - 0.6, 1.2, TD - 0.6), s["pos"] + Vector3(0, y0 + TH - 0.3, 0), s["ry"], mat_green)

func _river_slot(seat: int, i: int) -> Dictionary:
	var per_row := 6
	var row := i / per_row
	var col := i % per_row
	# 各行从「自己的左前方」起，依次向右；放满 6 张换下一行
	var along := -103.0 + col * 41.0
	var depth := 160.0 + row * 41.0
	var p := Vector3.ZERO
	var ry := 0.0
	match seat:
		0:
			p = Vector3(along, 0, depth)
		2:
			p = Vector3(-along, 0, -depth)
			ry = PI
		1:
			# 下家在右手边
			p = Vector3(depth, 0, -along)
			ry = PI * 0.5
		3:
			# 上家在左手边
			p = Vector3(-depth, 0, along)
			ry = -PI * 0.5
	return { "pos": p, "ry": ry }

func _build_rivers() -> void:
	var rcols := [Color(0.10, 0.17, 0.28), Color(0.11, 0.21, 0.15), Color(0.26, 0.13, 0.12), Color(0.24, 0.21, 0.10)]
	for s in range(4):
		var rm := StandardMaterial3D.new()
		rm.albedo_color = rcols[s]
		rm.roughness = 0.95
		var rp := Vector3.ZERO
		var rs := Vector3(272, 0.8, 84)
		match s:
			0:
				rp = Vector3(0, 0.4, 150)
			2:
				rp = Vector3(0, 0.4, -150)
			1:
				rp = Vector3(-150, 0.4, 0)
				rs = Vector3(84, 0.8, 272)
			3:
				rp = Vector3(150, 0.4, 0)
				rs = Vector3(84, 0.8, 272)
		_box(rs, rp, 0, rm)
	for seat in range(4):
		for i in range(rivers[seat].size()):
			var sl := _river_slot(seat, i)
			var kind: int = int(rivers[seat][i])
			var rf: Node3D = _tile_flat(sl["pos"], sl["ry"], kind, 0.78)
			if seat == _drop_seat and i == rivers[seat].size() - 1:
				rf.position.y += 70.0
				rf.scale = Vector3(0.86, 0.86, 0.86)
				var tw2 := create_tween()
				tw2.set_parallel(true)
				tw2.tween_property(rf, "position:y", sl["pos"].y, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw2.tween_property(rf, "scale", Vector3.ONE, 0.22)

func _hand_x(i: int, n: int) -> float:
	var half := (n - 1) * HAND_STEP * 0.5
	return -half + i * HAND_STEP

func _hand_shift() -> float:
	return 40.0 if not melds[0].is_empty() else 0.0

func _build_hand() -> void:
	var n: int = hands[0].size()
	var shift := _hand_shift()
	var animate_deal := _anim_deal
	for i in range(n):
		var x := _hand_x(i, n) - shift
		var lift := 8.0 if i == drawn_index else 0.0
		var p := Vector3(x, HAND_H * 0.5 + lift, HAND_Z)
		var tn: Node3D = _tile_upright(p, int(hands[0][i]))
		tn.set_meta("hover_base_scale", tn.scale)
		_hand_nodes.append(tn)
		if animate_deal:
			tn.position.y -= 62.0
			var tw := tn.create_tween()
			tw.tween_interval(float(i) * 0.022)
			tw.tween_property(tn, "position:y", p.y, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif i == drawn_index and drawn_index >= 0 and _anim_draw:
			tn.position.y -= 46.0
			var tw := tn.create_tween()
			tw.tween_property(tn, "position:y", p.y, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_other_hands() -> void:
	for seat in [1, 2, 3]:
		var n: int = hands[seat].size()
		for i in range(n):
			var x := _hand_x(i, n)
			match seat:
				2:
					_box(Vector3(HAND_W, HAND_H, HAND_T), Vector3(-x, HAND_H * 0.5, -HAND_Z), 0, mat_ivory)
					_box(Vector3(HAND_W - 3, HAND_H - 3, 1.2), Vector3(-x, HAND_H * 0.5, -HAND_Z + HAND_T * 0.5 + 0.4), 0, mat_back)
				1:
					_box(Vector3(HAND_T, HAND_H, HAND_W), Vector3(HAND_X, HAND_H * 0.5, x), 0, mat_ivory)
					_box(Vector3(1.2, HAND_H - 3, HAND_W - 3), Vector3(HAND_X - HAND_T * 0.5 - 0.4, HAND_H * 0.5, x), 0, mat_back)
				3:
					_box(Vector3(HAND_T, HAND_H, HAND_W), Vector3(-HAND_X, HAND_H * 0.5, -x), 0, mat_ivory)
					_box(Vector3(1.2, HAND_H - 3, HAND_W - 3), Vector3(-HAND_X + HAND_T * 0.5 + 0.4, HAND_H * 0.5, -x), 0, mat_back)

func _build_melds() -> void:
	for seat in range(4):
		var list: Array = melds[seat]
		if list.is_empty():
			continue
		# 锚在各家「右下角」的外圈，新牌往右加、旧牌往左挤（锚点固定 = 右对齐）
		var anchor := Vector3.ZERO
		var dir := Vector3.ZERO
		match seat:
			0:
				anchor = Vector3(470, 0, 468)
				dir = Vector3(-50, 0, 0)
			1:
				anchor = Vector3(500, 0, -430)
				dir = Vector3(0, 0, 50)
			2:
				anchor = Vector3(-470, 0, -468)
				dir = Vector3(50, 0, 0)
			3:
				anchor = Vector3(-500, 0, 430)
				dir = Vector3(0, 0, -50)
		# 摊平成一条，最新的牌放在最右（锚点），旧的依次往左推
		var flat: Array = []
		for m in list:
			for t in m["tiles"]:
				flat.append(int(t))
		var mry := 0.0
		match seat:
			1:
				mry = PI * 0.5
			2:
				mry = PI
			3:
				mry = -PI * 0.5
		var idx := 0.0
		for i in range(flat.size() - 1, -1, -1):
			_tile_flat(anchor + dir * idx, mry, flat[i])
			idx += 1.0
			if (flat.size() - 1 - i) % 3 == 2:
				idx += 0.35
func _build_center() -> void:
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 56.0
	cm.bottom_radius = 56.0
	cm.height = 6.0
	cyl.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.18, 0.14)
	m.roughness = 0.45
	cyl.material_override = m
	cyl.position = Vector3(0, 3, 0)
	board.add_child(cyl)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 74.0
	tm.outer_radius = 84.0
	ring.mesh = tm
	ring.material_override = mat_gold
	ring.position = Vector3(0, 5.5, 0)
	board.add_child(ring)
	# (已在上方 add_child)

## 四家名牌 + 中央剩余张数
func _build_seats() -> void:
	var names := ["你", "下家", "对家", "上家"]
	# 座位 0 下、1 右（下家）、2 上、3 左（上家）—— 逆时针出牌
	var spots := [Vector3(0, 60, 545), Vector3(500, 150, 0), Vector3(0, 150, -470), Vector3(-500, 150, 0)]
	for s in range(4):
		var l := Label3D.new()
		var cnt: int = hands[s].size()
		for m in melds[s]:
			cnt += m["tiles"].size()
		l.text = "%s  %d 张" % [names[s], cnt]
		l.font_size = 48
		l.pixel_size = 0.34
		l.outline_size = 9
		l.outline_modulate = Color(0, 0, 0, 0.62)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1, 0.86, 0.45) if s == turn else Color(0.78, 0.86, 0.82, 0.88)
		l.position = spots[s]
		board.add_child(l)
		if s == turn:
			var pulse := l.create_tween()
			pulse.set_loops()
			pulse.tween_property(l, "modulate:a", 0.55, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			pulse.tween_property(l, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var c := Label3D.new()
	c.text = str(wall.size())
	c.font_size = 110
	c.pixel_size = 0.5
	c.outline_size = 12
	c.outline_modulate = Color(0, 0, 0, 0.55)
	c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	c.no_depth_test = true
	c.modulate = Color(0.95, 0.93, 0.75)
	c.position = Vector3(0, 18, 0)
	board.add_child(c)

	var wall_cap := Label3D.new()
	wall_cap.text = "牌墙"
	wall_cap.font_size = 36
	wall_cap.pixel_size = 0.32
	wall_cap.outline_size = 6
	wall_cap.outline_modulate = Color(0, 0, 0, 0.5)
	wall_cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wall_cap.no_depth_test = true
	wall_cap.modulate = Color(0.86, 0.90, 0.80, 0.94)
	wall_cap.position = Vector3(0, 68, 0)
	board.add_child(wall_cap)

# ────────────────────────── HUD ──────────────────────────
func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var root := Control.new()
	root.name = "HudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root = root

	# 左上角品牌
	var brand := _ui_label("重生2 · 麻将", 20, Color(0.96, 0.82, 0.49))
	brand.position = Vector2(28, 18)
	root.add_child(brand)
	var brand_sub := _ui_label("广东麻将  ·  底分 %d" % STAKE, 12, Color(0.73, 0.80, 0.76, 0.88))
	brand_sub.position = Vector2(30, 47)
	root.add_child(brand_sub)
	_round_label = _ui_label("", 12, Color(0.92, 0.80, 0.53, 0.94))
	_round_label.position = Vector2(30, 71)
	root.add_child(_round_label)
	_score_label = _ui_label("", 11, Color(0.70, 0.78, 0.73, 0.92))
	_score_label.position = Vector2(30, 91)
	root.add_child(_score_label)

	_rules_btn = Button.new()
	_rules_btn.text = "规则  R"
	_rules_btn.anchor_left = 1.0
	_rules_btn.anchor_right = 1.0
	_rules_btn.offset_left = -266.0
	_rules_btn.offset_right = -158.0
	_rules_btn.offset_top = 18.0
	_rules_btn.offset_bottom = 52.0
	_rules_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_rules_btn, Color(0.035, 0.070, 0.060, 0.88), Color(0.47, 0.56, 0.49))
	_rules_btn.add_theme_font_size_override("font_size", 13)
	_rules_btn.pressed.connect(_toggle_rules)
	root.add_child(_rules_btn)

	_mute_btn = Button.new()
	_mute_btn.text = "已静音  M" if _muted else "声音  M"
	_mute_btn.anchor_left = 1.0
	_mute_btn.anchor_right = 1.0
	_mute_btn.offset_left = -150.0
	_mute_btn.offset_right = -24.0
	_mute_btn.offset_top = 18.0
	_mute_btn.offset_bottom = 52.0
	_mute_btn.focus_mode = Control.FOCUS_NONE
	_style_button(_mute_btn, Color(0.035, 0.070, 0.060, 0.88), Color(0.47, 0.56, 0.49))
	_mute_btn.add_theme_font_size_override("font_size", 13)
	_mute_btn.pressed.connect(_toggle_mute)
	root.add_child(_mute_btn)

	# 顶部中央：当前回合 / 牌墙 / 听牌
	_status_panel = PanelContainer.new()
	_status_panel.anchor_left = 0.5
	_status_panel.anchor_right = 0.5
	_status_panel.offset_left = -266.0
	_status_panel.offset_right = 266.0
	_status_panel.offset_top = 14.0
	_status_panel.offset_bottom = 82.0
	_status_style = _panel_style(Color(0.025, 0.070, 0.060, 0.92), Color(0.69, 0.53, 0.23, 0.72), 14)
	_status_panel.add_theme_stylebox_override("panel", _status_style)
	root.add_child(_status_panel)
	var status_box := VBoxContainer.new()
	status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	status_box.add_theme_constant_override("separation", 0)
	_status_panel.add_child(status_box)
	hud = _ui_label("", 22, Color(1.0, 0.92, 0.72))
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(hud)
	_hud_hint = _ui_label("", 12, Color(0.72, 0.82, 0.76, 0.92))
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(_hud_hint)

	# 左下：牌局记录
	var log_panel := PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 24.0
	log_panel.offset_right = 354.0
	log_panel.offset_top = -164.0
	log_panel.offset_bottom = -24.0
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.03, 0.035, 0.72), Color(0.36, 0.42, 0.38, 0.55), 14))
	root.add_child(log_panel)
	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 4)
	log_panel.add_child(log_box)
	var log_title := _ui_label("牌局记录", 12, Color(0.85, 0.72, 0.43, 0.92))
	log_box.add_child(log_title)
	evt_log = RichTextLabel.new()
	evt_log.bbcode_enabled = true
	evt_log.fit_content = false
	evt_log.scroll_active = false
	evt_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evt_log.custom_minimum_size = Vector2(0, 92)
	evt_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	evt_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	evt_log.add_theme_font_size_override("normal_font_size", 14)
	evt_log.add_theme_color_override("default_color", Color(0.84, 0.91, 0.87, 0.92))
	log_box.add_child(evt_log)

	# 顶部通知条：碰 / 杠 / 胡
	_toast_panel = PanelContainer.new()
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.offset_left = -320.0
	_toast_panel.offset_right = 320.0
	_toast_panel.offset_top = 92.0
	_toast_panel.offset_bottom = 142.0
	_toast_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.16, 0.10, 0.035, 0.94), Color(0.89, 0.64, 0.24, 0.85), 12))
	_toast_panel.pivot_offset = Vector2(320, 25)
	_toast_panel.visible = false
	root.add_child(_toast_panel)
	toast = _ui_label("", 20, Color(1.0, 0.91, 0.65))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_panel.add_child(toast)

	# 手牌悬停提示
	_hover_label = _ui_label("", 18, Color(1.0, 0.87, 0.56))
	_hover_label.anchor_left = 0.5
	_hover_label.anchor_right = 0.5
	_hover_label.anchor_top = 1.0
	_hover_label.anchor_bottom = 1.0
	_hover_label.offset_left = -220.0
	_hover_label.offset_right = 220.0
	_hover_label.offset_top = -208.0
	_hover_label.offset_bottom = -178.0
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.visible = false
	root.add_child(_hover_label)

	var control_hint := _ui_label("左键出牌  ·  P/G 响应  ·  Esc 暂停/过  ·  R 规则  ·  M 静音  ·  F11 全屏", 12, Color(0.66, 0.74, 0.70, 0.72))
	control_hint.anchor_left = 0.5
	control_hint.anchor_right = 0.5
	control_hint.anchor_top = 1.0
	control_hint.anchor_bottom = 1.0
	control_hint.offset_left = -260.0
	control_hint.offset_right = 260.0
	control_hint.offset_top = -34.0
	control_hint.offset_bottom = -10.0
	control_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(control_hint)

	# 右下：响应按钮
	_claim_panel = PanelContainer.new()
	_claim_panel.anchor_left = 1.0
	_claim_panel.anchor_right = 1.0
	_claim_panel.anchor_top = 1.0
	_claim_panel.anchor_bottom = 1.0
	_claim_panel.offset_left = -440.0
	_claim_panel.offset_right = -24.0
	_claim_panel.offset_top = -164.0
	_claim_panel.offset_bottom = -24.0
	_claim_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.065, 0.055, 0.94), Color(0.75, 0.58, 0.26, 0.75), 14))
	_claim_panel.visible = false
	root.add_child(_claim_panel)
	var claim_box := VBoxContainer.new()
	claim_box.add_theme_constant_override("separation", 8)
	_claim_panel.add_child(claim_box)
	var claim_title := _ui_label("可以响应 · 点击或按快捷键", 12, Color(0.88, 0.76, 0.50, 0.92))
	claim_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	claim_box.add_child(claim_title)
	_claim_row = HBoxContainer.new()
	_claim_row.alignment = BoxContainer.ALIGNMENT_END
	_claim_row.add_theme_constant_override("separation", 8)
	_claim_row.visible = false
	claim_box.add_child(_claim_row)
	_human_pending = {}

	# 主菜单（正常启动时显示）
	_main_menu_overlay = ColorRect.new()
	_main_menu_overlay.color = Color(0.010, 0.020, 0.024, 0.95)
	_main_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_menu_overlay.visible = false
	root.add_child(_main_menu_overlay)
	_main_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var main_center := CenterContainer.new()
	main_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_menu_overlay.add_child(main_center)
	var main_panel := PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(560, 500)
	main_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.060, 0.052, 0.99), Color(0.83, 0.62, 0.27, 0.94), 20))
	main_center.add_child(main_panel)
	var main_margin := MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 36)
	main_margin.add_theme_constant_override("margin_right", 36)
	main_margin.add_theme_constant_override("margin_top", 30)
	main_margin.add_theme_constant_override("margin_bottom", 30)
	main_panel.add_child(main_margin)
	var main_box := VBoxContainer.new()
	main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main_box.add_theme_constant_override("separation", 10)
	main_margin.add_child(main_box)
	var main_title := _ui_label("重生2 · 3D麻将", 38, Color(1.0, 0.83, 0.46))
	main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(main_title)
	var main_sub := _ui_label("广东麻将  ·  仅自摸 / 抢杠胡", 14, Color(0.78, 0.86, 0.80))
	main_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_box.add_child(main_sub)
	_main_menu_info = _ui_label("", 13, Color(0.74, 0.82, 0.77))
	_main_menu_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_menu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_menu_info.custom_minimum_size = Vector2(0, 42)
	main_box.add_child(_main_menu_info)
	_main_menu_start = Button.new()
	_main_menu_start.text = "开始游戏"
	_main_menu_start.custom_minimum_size = Vector2(260, 52)
	_main_menu_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_main_menu_start, Color(0.27, 0.38, 0.28), Color(0.82, 0.64, 0.32))
	_main_menu_start.add_theme_font_size_override("font_size", 21)
	_main_menu_start.pressed.connect(_start_from_main_menu)
	main_box.add_child(_main_menu_start)
	var menu_rules := Button.new()
	menu_rules.text = "规则与计分"
	menu_rules.custom_minimum_size = Vector2(260, 44)
	menu_rules.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(menu_rules, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	menu_rules.add_theme_font_size_override("font_size", 17)
	menu_rules.pressed.connect(_open_rules)
	main_box.add_child(menu_rules)
	var menu_settings := Button.new()
	menu_settings.text = "设置"
	menu_settings.custom_minimum_size = Vector2(260, 44)
	menu_settings.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(menu_settings, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	menu_settings.add_theme_font_size_override("font_size", 17)
	menu_settings.pressed.connect(_open_settings)
	main_box.add_child(menu_settings)
	var menu_quit := Button.new()
	menu_quit.text = "退出游戏"
	menu_quit.custom_minimum_size = Vector2(260, 44)
	menu_quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(menu_quit, Color(0.14, 0.10, 0.10), Color(0.45, 0.33, 0.29))
	menu_quit.add_theme_font_size_override("font_size", 17)
	menu_quit.pressed.connect(func(): get_tree().quit())
	main_box.add_child(menu_quit)

	# 暂停菜单
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.010, 0.020, 0.024, 0.82)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	root.add_child(_pause_overlay)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pause_center := CenterContainer.new()
	pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(pause_center)
	var pause_panel := PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(420, 430)
	pause_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.060, 0.052, 0.99), Color(0.83, 0.62, 0.27, 0.94), 18))
	pause_center.add_child(pause_panel)
	var pause_margin := MarginContainer.new()
	pause_margin.add_theme_constant_override("margin_left", 28)
	pause_margin.add_theme_constant_override("margin_right", 28)
	pause_margin.add_theme_constant_override("margin_top", 24)
	pause_margin.add_theme_constant_override("margin_bottom", 24)
	pause_panel.add_child(pause_margin)
	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 10)
	pause_margin.add_child(pause_box)
	var pause_title := _ui_label("暂停", 30, Color(1.0, 0.83, 0.46))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_title)
	_pause_resume = Button.new()
	_pause_resume.text = "继续游戏"
	_pause_resume.custom_minimum_size = Vector2(240, 46)
	_pause_resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_pause_resume, Color(0.27, 0.38, 0.28), Color(0.82, 0.64, 0.32))
	_pause_resume.add_theme_font_size_override("font_size", 18)
	_pause_resume.pressed.connect(_close_pause)
	pause_box.add_child(_pause_resume)
	var pause_rules := Button.new()
	pause_rules.text = "规则与计分"
	pause_rules.custom_minimum_size = Vector2(240, 42)
	pause_rules.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(pause_rules, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	pause_rules.add_theme_font_size_override("font_size", 16)
	pause_rules.pressed.connect(_open_rules)
	pause_box.add_child(pause_rules)
	var pause_settings := Button.new()
	pause_settings.text = "设置"
	pause_settings.custom_minimum_size = Vector2(240, 42)
	pause_settings.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(pause_settings, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	pause_settings.add_theme_font_size_override("font_size", 16)
	pause_settings.pressed.connect(_open_settings)
	pause_box.add_child(pause_settings)
	var pause_main := Button.new()
	pause_main.text = "返回主菜单"
	pause_main.custom_minimum_size = Vector2(240, 42)
	pause_main.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(pause_main, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	pause_main.add_theme_font_size_override("font_size", 16)
	pause_main.pressed.connect(_go_to_main_menu)
	pause_box.add_child(pause_main)
	var pause_quit := Button.new()
	pause_quit.text = "退出游戏"
	pause_quit.custom_minimum_size = Vector2(240, 42)
	pause_quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(pause_quit, Color(0.14, 0.10, 0.10), Color(0.45, 0.33, 0.29))
	pause_quit.add_theme_font_size_override("font_size", 16)
	pause_quit.pressed.connect(func(): get_tree().quit())
	pause_box.add_child(pause_quit)

	# 设置面板
	_settings_overlay = ColorRect.new()
	_settings_overlay.color = Color(0.010, 0.020, 0.024, 0.88)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.visible = false
	root.add_child(_settings_overlay)
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings_center := CenterContainer.new()
	settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(settings_center)
	var settings_panel := PanelContainer.new()
	settings_panel.custom_minimum_size = Vector2(520, 380)
	settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.060, 0.052, 0.99), Color(0.83, 0.62, 0.27, 0.94), 18))
	settings_center.add_child(settings_panel)
	var settings_margin := MarginContainer.new()
	settings_margin.add_theme_constant_override("margin_left", 30)
	settings_margin.add_theme_constant_override("margin_right", 30)
	settings_margin.add_theme_constant_override("margin_top", 24)
	settings_margin.add_theme_constant_override("margin_bottom", 24)
	settings_panel.add_child(settings_margin)
	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 16)
	settings_margin.add_child(settings_box)
	var settings_title := _ui_label("设置", 28, Color(1.0, 0.83, 0.46))
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_box.add_child(settings_title)
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	settings_box.add_child(volume_row)
	var volume_caption := _ui_label("主音量", 15, Color(0.82, 0.89, 0.84))
	volume_caption.custom_minimum_size = Vector2(70, 0)
	volume_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_caption)
	_settings_slider = HSlider.new()
	_settings_slider.min_value = 0
	_settings_slider.max_value = 100
	_settings_slider.step = 1
	_settings_slider.value = int(round(master_volume * 100.0))
	_settings_slider.custom_minimum_size = Vector2(260, 24)
	_settings_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_slider.value_changed.connect(_on_master_volume_changed)
	_settings_slider.drag_ended.connect(func(_changed): _save_match_state())
	volume_row.add_child(_settings_slider)
	_volume_value_label = _ui_label("%d%%" % int(round(master_volume * 100.0)), 13, Color(0.82, 0.89, 0.84))
	_volume_value_label.custom_minimum_size = Vector2(50, 0)
	_volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(_volume_value_label)
	var settings_note := _ui_label("AI 难度在规则面板中调整；音量与静音状态会自动保存。", 12, Color(0.66, 0.75, 0.69))
	settings_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(settings_note)
	_settings_fullscreen_btn = Button.new()
	_settings_fullscreen_btn.text = "全屏：开  F11" if _fullscreen else "全屏：关  F11"
	_settings_fullscreen_btn.custom_minimum_size = Vector2(240, 42)
	_settings_fullscreen_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_settings_fullscreen_btn, Color(0.07, 0.12, 0.10), Color(0.47, 0.56, 0.49))
	_settings_fullscreen_btn.add_theme_font_size_override("font_size", 16)
	_settings_fullscreen_btn.pressed.connect(_toggle_fullscreen)
	settings_box.add_child(_settings_fullscreen_btn)
	_settings_close = Button.new()
	_settings_close.text = "返回"
	_settings_close.custom_minimum_size = Vector2(240, 44)
	_settings_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_settings_close, Color(0.27, 0.38, 0.28), Color(0.82, 0.64, 0.32))
	_settings_close.add_theme_font_size_override("font_size", 17)
	_settings_close.pressed.connect(_close_settings)
	settings_box.add_child(_settings_close)

	# 结算层：压暗 + 居中卡片
	_result_overlay = ColorRect.new()
	_result_overlay.color = Color(0.008, 0.018, 0.022, 0.78)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	root.add_child(_result_overlay)
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(center)
	_result_panel = PanelContainer.new()
	_result_panel.custom_minimum_size = Vector2(540, 320)
	_result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.060, 0.052, 0.98), Color(0.83, 0.62, 0.27, 0.9), 18))
	_result_panel.pivot_offset = Vector2(270, 160)
	center.add_child(_result_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_result_panel.add_child(margin)
	var result_box := VBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.add_theme_constant_override("separation", 14)
	margin.add_child(result_box)
	big = _ui_label("", 46, Color(1.0, 0.83, 0.45))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.custom_minimum_size = Vector2(0, 66)
	big.visible = false
	result_box.add_child(big)
	result_detail = _ui_label("", 20, Color(0.88, 0.93, 0.89))
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.custom_minimum_size = Vector2(0, 72)
	result_detail.visible = false
	result_box.add_child(result_detail)

	result_source = _ui_label("", 14, Color(0.95, 0.82, 0.56))
	result_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_source.custom_minimum_size = Vector2(0, 38)
	result_source.visible = false
	result_box.add_child(result_source)

	result_hands_panel = PanelContainer.new()
	result_hands_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.028, 0.024, 0.82), Color(0.34, 0.43, 0.36, 0.65), 12))
	result_hands_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_hands_panel.visible = false
	result_box.add_child(result_hands_panel)
	result_hands_box = VBoxContainer.new()
	result_hands_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_hands_box.add_theme_constant_override("separation", 5)
	result_hands_panel.add_child(result_hands_box)

	restart_btn = Button.new()
	restart_btn.text = "再来一局"
	restart_btn.custom_minimum_size = Vector2(190, 54)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(_restart)
	_style_button(restart_btn, Color(0.27, 0.38, 0.28), Color(0.82, 0.64, 0.32))
	restart_btn.add_theme_font_size_override("font_size", 22)
	restart_btn.visible = false
	result_box.add_child(restart_btn)

	# 规则 / 计分面板（位于结算层之上）
	_rules_overlay = ColorRect.new()
	_rules_overlay.color = Color(0.008, 0.018, 0.022, 0.86)
	_rules_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_rules_overlay.visible = false
	root.add_child(_rules_overlay)
	_rules_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rules_center := CenterContainer.new()
	rules_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_overlay.add_child(rules_center)
	var rules_panel := PanelContainer.new()
	rules_panel.custom_minimum_size = Vector2(780, 560)
	rules_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.060, 0.052, 0.99), Color(0.83, 0.62, 0.27, 0.9), 18))
	rules_center.add_child(rules_panel)
	var rules_margin := MarginContainer.new()
	rules_margin.add_theme_constant_override("margin_left", 28)
	rules_margin.add_theme_constant_override("margin_right", 28)
	rules_margin.add_theme_constant_override("margin_top", 22)
	rules_margin.add_theme_constant_override("margin_bottom", 22)
	rules_panel.add_child(rules_margin)
	var rules_box := VBoxContainer.new()
	rules_box.add_theme_constant_override("separation", 10)
	rules_margin.add_child(rules_box)
	var rules_title := _ui_label("本桌规则 · 计分", 26, Color(1.0, 0.82, 0.46))
	rules_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_box.add_child(rules_title)
	_rules_text = RichTextLabel.new()
	_rules_text.bbcode_enabled = true
	_rules_text.scroll_active = true
	_rules_text.custom_minimum_size = Vector2(0, 330)
	_rules_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules_text.add_theme_font_size_override("normal_font_size", 15)
	_rules_text.add_theme_color_override("default_color", Color(0.84, 0.91, 0.87))
	rules_box.add_child(_rules_text)
	var ai_row := HBoxContainer.new()
	ai_row.alignment = BoxContainer.ALIGNMENT_END
	ai_row.add_theme_constant_override("separation", 8)
	rules_box.add_child(ai_row)
	var ai_caption := _ui_label("AI 难度", 12, Color(0.76, 0.83, 0.78, 0.92))
	ai_caption.custom_minimum_size = Vector2(60, 0)
	ai_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ai_row.add_child(ai_caption)
	_ai_buttons.clear()
	for level in range(3):
		var ai_button := Button.new()
		ai_button.custom_minimum_size = Vector2(84, 36)
		ai_button.focus_mode = Control.FOCUS_NONE
		ai_button.pressed.connect(_set_ai_level.bind(level))
		ai_row.add_child(ai_button)
		_ai_buttons.append(ai_button)
	_refresh_ai_buttons()
	var rules_actions := HBoxContainer.new()
	rules_actions.add_theme_constant_override("separation", 10)
	rules_actions.alignment = BoxContainer.ALIGNMENT_END
	rules_box.add_child(rules_actions)
	var reset_btn := Button.new()
	reset_btn.text = "重置比赛"
	reset_btn.custom_minimum_size = Vector2(140, 44)
	_style_button(reset_btn, Color(0.30, 0.15, 0.14), Color(0.67, 0.35, 0.30))
	reset_btn.add_theme_font_size_override("font_size", 16)
	rules_actions.add_child(reset_btn)
	_rules_close = Button.new()
	_rules_close.text = "继续  R"
	_rules_close.custom_minimum_size = Vector2(150, 44)
	_style_button(_rules_close, Color(0.27, 0.38, 0.28), Color(0.82, 0.64, 0.32))
	_rules_close.add_theme_font_size_override("font_size", 16)
	_rules_close.pressed.connect(_close_rules)
	rules_actions.add_child(_rules_close)
	var reset_confirm := ConfirmationDialog.new()
	reset_confirm.title = "重置比赛"
	reset_confirm.dialog_text = "清零四家分数，并从第 1 局重新开始？"
	reset_confirm.ok_button_text = "重置"
	reset_confirm.cancel_button_text = "取消"
	reset_confirm.confirmed.connect(_reset_match)
	root.add_child(reset_confirm)
	reset_btn.pressed.connect(func(): reset_confirm.popup_centered(Vector2i(420, 160)))

	_render_event_log()
	_update_match_hud()
	_update_hud()

func _open_main_menu(from_pause: bool = false) -> void:
	if _main_menu_overlay == null:
		return
	_pause_open = false
	if _pause_overlay:
		_pause_overlay.visible = false
	_settings_open = false
	if _settings_overlay:
		_settings_overlay.visible = false
	_main_menu_open = true
	_main_menu_overlay.visible = true
	_main_menu_start.text = "继续游戏" if from_pause else "开始游戏"
	var score_parts := PackedStringArray()
	for i in range(4):
		score_parts.append("%s %d" % [SEAT_NAMES[i], scores[i]])
	_main_menu_info.text = "第 %d 局 · 庄家 %s\n%s" % [hand_no, SEAT_NAMES[dealer], " · ".join(score_parts)]
	_set_hovered_hand(-1)
	_main_menu_start.grab_focus()
	print("MAIN_MENU open from_pause=", from_pause, " hand=", hand_no, " dealer=", dealer)

func _start_from_main_menu() -> void:
	_main_menu_open = false
	if _main_menu_overlay:
		_main_menu_overlay.visible = false
	if _main_menu_start:
		_main_menu_start.release_focus()
	_check_initial_win()

func _open_pause() -> void:
	if game_over or _main_menu_open or _rules_open or _settings_open:
		return
	_pause_open = true
	if _pause_overlay:
		_pause_overlay.visible = true
	_set_hovered_hand(-1)
	if _pause_resume:
		_pause_resume.grab_focus()

func _close_pause() -> void:
	_pause_open = false
	if _pause_overlay:
		_pause_overlay.visible = false
	if _pause_resume:
		_pause_resume.release_focus()

func _open_settings() -> void:
	if _settings_overlay == null:
		return
	_settings_open = true
	_settings_overlay.visible = true
	if _settings_slider:
		_settings_slider.value = int(round(master_volume * 100.0))
	if _volume_value_label:
		_volume_value_label.text = "%d%%" % int(round(master_volume * 100.0))
	if _settings_fullscreen_btn:
		_settings_fullscreen_btn.text = "全屏：开  F11" if _fullscreen else "全屏：关  F11"
	if _settings_close:
		_settings_close.grab_focus()

func _close_settings() -> void:
	_settings_open = false
	if _settings_overlay:
		_settings_overlay.visible = false
	if _settings_close:
		_settings_close.release_focus()
	_save_match_state()
	if _main_menu_open and _main_menu_start:
		_main_menu_start.grab_focus()
	elif _pause_open and _pause_resume:
		_pause_resume.grab_focus()

func _on_master_volume_changed(value: float) -> void:
	master_volume = clampf(value / 100.0, 0.0, 1.0)
	_apply_audio_settings()
	if _volume_value_label:
		_volume_value_label.text = "%d%%" % int(round(master_volume * 100.0))

func _go_to_main_menu() -> void:
	_pause_open = false
	if _pause_overlay:
		_pause_overlay.visible = false
	_open_main_menu(true)

func _check_initial_win(force: bool = false) -> void:
	if (not _persist_enabled and not force) or game_over:
		return
	var ev: Dictionary = MJRules.evaluate(hands[dealer], melds[dealer])
	if ev.is_empty():
		return
	_win(dealer, int(hands[dealer].back()), ev, true, -1, true)

func _show_claim(opts: Array) -> void:
	_set_hovered_hand(-1)
	for c in _claim_row.get_children():
		c.queue_free()
	var names := { "gang": "杠  G", "peng": "碰  P" }
	var accents := {
		"gang": Color(0.76, 0.56, 0.24),
		"peng": Color(0.30, 0.58, 0.46),
	}
	var first_btn: Button
	for o in opts:
		var b := Button.new()
		b.text = names[o]
		b.custom_minimum_size = Vector2(84, 46)
		b.focus_mode = Control.FOCUS_ALL
		_style_button(b, Color(0.11, 0.16, 0.14), accents.get(o, Color(0.55, 0.65, 0.58)))
		b.pressed.connect(_on_claim.bind(o))
		_claim_row.add_child(b)
		if first_btn == null:
			first_btn = b
	var p := Button.new()
	p.text = "过  Esc"
	p.custom_minimum_size = Vector2(84, 46)
	p.focus_mode = Control.FOCUS_ALL
	_style_button(p, Color(0.14, 0.15, 0.15), Color(0.52, 0.56, 0.53))
	p.pressed.connect(_on_claim.bind("pass"))
	_claim_row.add_child(p)
	if first_btn == null:
		first_btn = p
	_claim_row.visible = true
	_claim_panel.visible = true
	first_btn.call_deferred("grab_focus")

func _on_claim(kind: String) -> void:
	if _human_pending.is_empty():
		return
	_hide_claim()
	_apply_human_claim(_claim_from, _claim_tile, kind)

func _claim_available(kind: String) -> bool:
	return not _human_pending.is_empty() and kind in _human_pending.get("opts", [])

func _apply_human_claim(from_seat: int, tile: int, kind: String) -> void:
	if kind == "bugang":
		_do_self_kong(0, _bugang_tile(0), "bugang")
		return
	if kind == "angang":
		_do_self_kong(0, _angang_tile(0), "angang")
		return
	if kind == "pass" or kind == "":
		_ev("你 过")
		_ai_claims()
		return
	if kind == "gang":
		for i in range(3):
			hands[0].erase(tile)
		melds[0].append({ "type": "gang", "tiles": [tile, tile, tile, tile] })
		if rivers[from_seat].size() > 0:
			rivers[from_seat].pop_back()
		_record_kong_score("gang", 0, from_seat)
		_play("gang", 0.0)
		_add_trauma(0.18)
		_say_after("vo_gang")
		_toast("%s 杠 %s · +3" % [SEAT_NAMES[0], TILE_NAMES[tile]])
		_ev(">>> 你 杠 %s · +3" % TILE_NAMES[tile])
		if not _draw_for(0):
			return
		if _self_draw_win(0):
			return
		turn = 0
		phase = "discard"
		_set_state(St.HUMAN_DISCARD)
		_build()
		return
	if kind == "peng":
		hands[0].erase(tile)
		hands[0].erase(tile)
		melds[0].append({ "type": "peng", "tiles": [tile, tile, tile] })
		if rivers[from_seat].size() > 0:
			rivers[from_seat].pop_back()
		_play("peng", 0.0)
		_add_trauma(0.15)
		_say_after("vo_peng")
		_toast("%s 碰 %s" % [SEAT_NAMES[0], TILE_NAMES[tile]])
		_ev(">>> 你 碰 %s" % TILE_NAMES[tile])
		turn = 0
		phase = "discard"
		_set_state(St.HUMAN_DISCARD)
		_build()
		return
func _hide_claim() -> void:
	if _claim_row:
		_claim_row.visible = false
	if _claim_panel:
		_claim_panel.visible = false
	_human_pending = {}

func _update_hud() -> void:
	if hud == null:
		return
	var who: String = ["你", "下家", "对家", "上家"][turn]
	var ting := ""
	var state := ""
	if game_over:
		state = "本局结束"
	elif st == St.HUMAN_CLAIM:
		state = "轮到你 · 请选择操作"
	elif turn == 0 and st == St.HUMAN_DISCARD:
		state = "轮到你 · 请出牌"
	elif st == St.CLAIM_WAIT:
		state = "等待其他家响应"
	else:
		state = "轮到 %s · 思考中" % who
	if turn == 0 and not hands[0].is_empty() and (hands[0].size() + melds[0].size() * 3) % 3 == 1:
		var w: Array = MJRules.waits(hands[0], melds[0])
		if not w.is_empty():
			ting = " · 听 %d 张" % w.size()
	hud.text = state
	hud.add_theme_color_override("font_color", Color(1.0, 0.91, 0.66) if turn == 0 and not game_over else Color(0.89, 0.94, 0.90))
	_hud_hint.text = "牌墙 %d / 136 · 底分 %d%s" % [wall.size(), STAKE, ting]
	_update_match_hud()

func _set_hovered_hand(index: int) -> void:
	if index < 0 or index >= _hand_nodes.size():
		index = -1
	if index == _hovered_index:
		return
	if _hovered_index >= 0 and _hovered_index < _hand_nodes.size():
		var old := _hand_nodes[_hovered_index]
		if is_instance_valid(old):
			var base: Vector3 = old.get_meta("hover_base_scale", Vector3.ONE)
			var out := create_tween()
			out.tween_property(old, "scale", base, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hovered_index = index
	if index >= 0:
		var node := _hand_nodes[index]
		var base_scale: Vector3 = node.get_meta("hover_base_scale", Vector3.ONE)
		var tw := create_tween()
		tw.tween_property(node, "scale", base_scale * 1.06, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _hover_label:
			var tile: int = int(hands[0][index])
			_hover_label.text = "%s  ·  左键打出" % TILE_NAMES[tile]
			_hover_label.visible = true
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		if _hover_label:
			_hover_label.visible = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _update_hover(mouse_pos: Vector2) -> void:
	if game_over or turn != 0 or st != St.HUMAN_DISCARD or _claim_panel.visible:
		_set_hovered_hand(-1)
		return
	for i in range(hands[0].size()):
		if _hand_screen_rect(i).has_point(mouse_pos):
			_set_hovered_hand(i)
			return
	_set_hovered_hand(-1)

func _hand_screen_rect(i: int) -> Rect2:
	var n: int = hands[0].size()
	var x := _hand_x(i, n) - _hand_shift()
	var a := cam.unproject_position(Vector3(x - HAND_W * 0.5, 0, HAND_Z))
	var b := cam.unproject_position(Vector3(x + HAND_W * 0.5, HAND_H, HAND_Z))
	return Rect2(min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M:
				_toggle_mute()
				get_viewport().set_input_as_handled()
				return
			KEY_F11:
				_toggle_fullscreen()
				get_viewport().set_input_as_handled()
				return
			KEY_R:
				_toggle_rules()
				get_viewport().set_input_as_handled()
				return
		if _rules_open:
			if event.keycode == KEY_ESCAPE:
				_close_rules()
				get_viewport().set_input_as_handled()
			return
		if _settings_open:
			if event.keycode == KEY_ESCAPE:
				_close_settings()
				get_viewport().set_input_as_handled()
			return
		if _pause_open:
			if event.keycode == KEY_ESCAPE:
				_close_pause()
				get_viewport().set_input_as_handled()
			return
		if _main_menu_open:
			return
		if game_over:
			return
		if _claim_row and _claim_row.visible:
			match event.keycode:
				KEY_P:
					if _claim_available("peng"):
						_on_claim("peng")
						get_viewport().set_input_as_handled()
				KEY_G:
					if _claim_available("gang"):
						_on_claim("gang")
						get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_claim("pass")
					get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			_open_pause()
			get_viewport().set_input_as_handled()
		return
	if _main_menu_open or _pause_open or _settings_open or _rules_open:
		return
	if game_over:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if turn != 0 or phase != "discard" or st != St.HUMAN_DISCARD or _claim_panel.visible:
		return
	for i in range(hands[0].size()):
		if _hand_screen_rect(i).has_point(event.position):
			_player_discard(i)
			return

func _auto_run() -> void:
	auto_pass = true
	var guard := 0
	var limit := 6000 if Engine.time_scale > 1.5 else 6000
	while not game_over and guard < limit:
		guard += 1
		await get_tree().create_timer(0.02).timeout
		if turn == 0 and phase == "discard" and hands[0].size() > 0:
			_player_discard(randi() % hands[0].size())
	var total_disc := 0
	for s4 in range(4):
		total_disc += rivers[s4].size()
	print("AUTO end wall=", wall.size(), " discards=", total_disc)
	for s5 in range(4):
		if melds[s5].size() > 0:
			print("MELDS seat", s5, " = ", melds[s5])
	get_tree().quit()

func _hover_test() -> void:
	await get_tree().process_frame
	_set_hovered_hand(5)
	var label_ok := _hover_label.visible and _hover_label.text.contains(TILE_NAMES[int(hands[0][5])])
	var node_ok := is_instance_valid(_hand_nodes[5])
	print("HOVER index=", _hovered_index, " node=", node_ok, " label=", label_ok, " text=", _hover_label.text)
	_set_hovered_hand(-1)
	print("HOVEROUT hidden=", not _hover_label.visible)
	get_tree().quit(0 if label_ok and node_ok and not _hover_label.visible else 1)

func _zimo_test() -> void:
	_new_game()
	hands[0] = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 17]
	melds[0] = []
	wall = [3, 4, 17]
	_go_draw()
	await get_tree().process_frame
	var title: String = big.text if big else ""
	var ok: bool = game_over and hands[0].size() == 14 and title.contains("自摸")
	print("ZIMOTEST over=", game_over, " hand=", hands[0].size(), " title=", title)
	get_tree().quit(0 if ok else 1)

func _ai_test() -> void:
	_new_game()
	hands[1] = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 5, 33]
	melds[1] = []
	ai_level = 1
	var idx := _ai_choose_discard(1)
	var chosen: int = int(hands[1][idx])
	var probe: Array = hands[1].duplicate()
	probe.remove_at(idx)
	var waits: Array = MJRules.waits(probe, [])
	var started := Time.get_ticks_usec()
	ai_level = 2
	var hard_idx := _ai_choose_discard(1)
	var hard_probe: Array = hands[1].duplicate()
	hard_probe.remove_at(hard_idx)
	var hard_waits: Array = MJRules.waits(hard_probe, [])
	var elapsed := Time.get_ticks_usec() - started
	var ok: bool = not waits.is_empty() and not hard_waits.is_empty()
	print("AITEST normal=", TILE_NAMES[chosen], " waits=", waits, " hard=", TILE_NAMES[int(hands[1][hard_idx])], " hard_waits=", hard_waits, " hard_usec=", elapsed)
	get_tree().quit(0 if ok else 1)

func _audio_test() -> void:
	var buses := PackedStringArray()
	for i in range(AudioServer.bus_count):
		buses.append(AudioServer.get_bus_name(i))
	var routed := buses.has("SFX") and buses.has("Voice") and buses.has("UI")
	_toggle_mute()
	var muted := AudioServer.is_bus_mute(0)
	_toggle_mute()
	var restored := not AudioServer.is_bus_mute(0)
	print("AUDIOTEST buses=", buses, " routed=", routed, " muted=", muted, " restored=", restored)
	get_tree().quit(0 if routed and muted and restored else 1)

func _match_test() -> void:
	_persist_enabled = false
	scores = [0, 0, 0, 0]
	dealer = 0
	hand_no = 1
	_record_win_result(1, { "per": 8, "total": 24 })
	var ok1: bool = scores == [-8, 24, -8, -8] and dealer == 1 and hand_no == 2
	scores = [0, 0, 0, 0]
	dealer = 2
	hand_no = 5
	_record_win_result(2, { "per": 4, "total": 12 })
	var ok2: bool = scores[2] == 12 and dealer == 2 and hand_no == 6
	scores = [0, 0, 0, 0]
	dealer = 1
	hand_no = 3
	_record_draw_result()
	var ok3: bool = dealer == 1 and hand_no == 4
	dealer = 1
	hand_no = 2
	_new_game()
	var ok4: bool = turn == 1 and hands[1].size() == 14 and hands[0].size() == 13 and st == St.AI_DISCARD
	_reset_match()
	var ok5: bool = scores == [0, 0, 0, 0] and dealer == 0 and hand_no == 1 and not game_over and not _rules_open
	print("MATCHTEST ok1=", ok1, " ok2=", ok2, " ok3=", ok3, " ok4=", ok4, " ok5=", ok5)
	get_tree().quit(0 if ok1 and ok2 and ok3 and ok4 and ok5 else 1)

func _kong_score_test() -> void:
	_persist_enabled = false
	scores = [0, 0, 0, 0]
	_record_kong_score("angang", 0)
	var ok_a: bool = scores == [6, -2, -2, -2]
	scores = [0, 0, 0, 0]
	_record_kong_score("bugang", 1)
	var ok_b: bool = scores == [-1, 3, -1, -1]
	scores = [0, 0, 0, 0]
	_record_kong_score("gang", 2, 0)
	var ok_c: bool = scores == [-3, 0, 3, 0]
	scores = [0, 0, 0, 0]
	dealer = 0
	hand_no = 1
	_record_rob_result(1, 2)
	var ok_d: bool = scores == [0, 20, -20, 0] and dealer == 1 and hand_no == 2
	print("KONGSCORETEST angang=", ok_a, " bugang=", ok_b, " gang=", ok_c, " rob=", ok_d, " scores=", scores)
	get_tree().quit(0 if ok_a and ok_b and ok_c and ok_d else 1)

func _shanten_test() -> void:
	var complete: Array = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 17, 17]
	var tenpai: Array = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 17]
	var one_shanten: Array = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 17, 33]
	var seven_tenpai: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]
	var seven_complete: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]
	var s_complete := MJRules.shanten(complete, [])
	var s_tenpai := MJRules.shanten(tenpai, [])
	var s_one := MJRules.shanten(one_shanten, [])
	var s_seven_tenpai := MJRules.shanten(seven_tenpai, [])
	var s_seven_complete := MJRules.shanten(seven_complete, [])
	var started := Time.get_ticks_usec()
	var perf := MJRules.shanten(tenpai, [])
	var elapsed := Time.get_ticks_usec() - started
	var ok: bool = s_complete == -1 and s_tenpai == 0 and s_one == 1 and s_seven_tenpai == 0 and s_seven_complete == -1
	print("SHANTENTEST complete=", s_complete, " tenpai=", s_tenpai, " one=", s_one, " seven_tenpai=", s_seven_tenpai, " seven_complete=", s_seven_complete, " perf=", perf, " usec=", elapsed)
	get_tree().quit(0 if ok else 1)

func _score_shot_test() -> void:
	scores = [0, 0, 0, 0]
	_record_kong_score("angang", 0)
	await get_tree().create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_score.png")
	var labels := 0
	for child in _hud_root.get_children():
		if child.has_meta("score_delta"):
			labels += 1
	print("SCORESHOT labels=", labels, " scores=", scores)
	get_tree().quit(0 if labels >= 4 and scores == [6, -2, -2, -2] else 1)

func _panel_shot_test(kind: String) -> void:
	match kind:
		"menu":
			_open_main_menu(false)
		"pause":
			_open_pause()
		"settings":
			_open_settings()
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_%s.png" % kind)
	print("PANELSHOT kind=", kind, " main=", _main_menu_open, " pause=", _pause_open, " settings=", _settings_open)
	get_tree().quit(0 if (_main_menu_open or _pause_open or _settings_open) else 1)

func _deal_win_test() -> void:
	_persist_enabled = false
	game_over = false
	dealer = 0
	hand_no = 1
	hands[0] = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 17, 17]
	melds[0] = []
	_check_initial_win(true)
	await get_tree().process_frame
	var title: String = big.text if big else ""
	var ok: bool = game_over and title.contains("天胡") and bool(_win_context.get("initial_deal", false))
	print("DEALWINTEST over=", game_over, " title=", title, " scores=", scores)
	get_tree().quit(0 if ok else 1)

func _flow_test() -> void:
	_persist_enabled = false
	_open_main_menu(false)
	var a: bool = _main_menu_open and _main_menu_overlay.visible
	_start_from_main_menu()
	var b: bool = not _main_menu_open and not _main_menu_overlay.visible
	_open_pause()
	var c: bool = _pause_open and _pause_overlay.visible
	_open_settings()
	var d: bool = _settings_open and _settings_overlay.visible
	_close_settings()
	var e: bool = not _settings_open
	_close_pause()
	var f: bool = not _pause_open
	_open_pause()
	_open_main_menu(true)
	var g: bool = _main_menu_open and _main_menu_start.text == "继续游戏"
	print("FLOWTEST menu=", a, " start=", b, " pause=", c, " settings=", d, " close_settings=", e, " close_pause=", f, " back_to_menu=", g)
	get_tree().quit(0 if a and b and c and d and e and f and g else 1)
func _save_test() -> void:
	_persist_enabled = true
	_save_path = "user://match_state_test.json"
	for path in [_save_path, _save_path + ".bak", _save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	scores = [1, -2, 3, 4]
	dealer = 2
	hand_no = 7
	ai_level = 2
	master_volume = 0.35
	_muted = true
	_save_match_state()
	var exists := FileAccess.file_exists(_save_path)
	scores = [0, 0, 0, 0]
	dealer = 0
	hand_no = 1
	ai_level = 1
	master_volume = 1.0
	_muted = false
	_load_match_state()
	var ok := exists and scores == [1, -2, 3, 4] and dealer == 2 and hand_no == 7 and ai_level == 2 and is_equal_approx(master_volume, 0.35) and _muted
	print("SAVETEST exists=", exists, " scores=", scores, " dealer=", dealer, " hand=", hand_no, " ai=", ai_level, " vol=", master_volume, " muted=", _muted, " ok=", ok, " dir=", OS.get_user_data_dir())
	for path in [_save_path, _save_path + ".bak", _save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_save_path = SAVE_PATH
	get_tree().quit(0 if ok else 1)

func _rules_shot_test() -> void:
	_open_rules()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_rules.png")
	print("RULESSHOT open=", _rules_open, " visible=", _rules_overlay.visible)
	get_tree().quit(0 if _rules_open and _rules_overlay.visible else 1)

func _no_point_test() -> void:
	_new_game()
	# 4 组顺子 + 单张 17（九筒）：若存在点炮胡，别人打 17 就会直接结算。
	hands[0] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 17]
	hands[2] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 17]
	hands[1] = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]
	hands[3] = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]
	melds[0] = []
	melds[2] = []
	rivers[1] = [17]
	_claim_from = 1
	_claim_tile = 17
	_resolve_claims()
	await get_tree().process_frame
	var ok: bool = not game_over and not _human_pending.has("hu")
	print("NOPOINT over=", game_over, " pending=", _human_pending)
	get_tree().quit(0 if ok else 1)

func _ui_shot_test() -> void:
	_ev("你 打 六万")
	_ev("下家 打 九筒")
	_ev(">>> 对家 碰 九筒")
	_ev(">>> 对家 打 三万")
	rivers[0] = [0, 1, 2, 9, 10, 11]
	rivers[1] = [18, 19, 20]
	rivers[2] = [27, 28]
	rivers[3] = [31, 32]
	melds[1] = [{ "type": "peng", "tiles": [5, 5, 5] }]
	_build()
	_human_pending = { "opts": ["peng", "gang"] }
	_set_state(St.HUMAN_CLAIM)
	_show_claim(["peng", "gang"])
	_toast("对家 碰 九筒")
	_update_hud()
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_ui.png")
	get_tree().quit()

func _claim_test() -> void:
	var ok := 0
	_new_game()
	_total_checks = 4
	_show_claim(["peng", "gang"])
	await get_tree().process_frame
	if _claim_row and _claim_row.get_child_count() == 3:
		ok += 1
	print("C1 按钮=", _claim_row.get_child_count())
	for q in range(1, 4):
		hands[q] = [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18]
	hands[0] = [5, 5, 0, 1, 2, 9, 10, 11, 18, 19, 20, 27, 28]
	melds[0] = []
	rivers[1] = [5]
	_human_pending = { "opts": ["peng"] }
	_claim_from = 1
	_claim_tile = 5
	_on_claim("peng")
	await get_tree().process_frame
	if melds[0].size() == 1 and melds[0][0]["tiles"] == [5, 5, 5]:
		ok += 1
	print("C2 碰后副露=", melds[0])
	_new_game()
	rivers[1] = [5]
	_human_pending = { "opts": ["peng"] }
	_claim_from = 1
	_claim_tile = 5
	_on_claim("pass")
	await get_tree().process_frame
	if _human_pending.is_empty():
		ok += 1
	print("C3 过=", _human_pending)
	if _claim_row and not _claim_row.visible:
		ok += 1
	print("CLAIMTEST ", ok, "/4")
	get_tree().quit()
func _result_shot_test() -> void:
	_show_result("你 胡了！", "碰碰胡\n每家 8 张 · 三家共 24")
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_result.png")
	get_tree().quit()

func _showdown_shot_test() -> void:
	hands[0] = [0, 1, 2, 4, 5, 6, 9, 10, 11, 18, 19, 20, 27]
	hands[1] = [0, 0, 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 17, 17]
	hands[2] = [0, 1, 2, 3, 4, 5, 9, 10, 11, 33]
	melds[2] = [{ "type": "peng", "tiles": [28, 28, 28] }]
	hands[3] = [1, 2, 3, 4, 5, 6, 10, 11, 12, 19, 20, 21, 31]
	melds[0] = []
	melds[1] = []
	melds[3] = []
	_win(1, 17, { "tier": "small", "name": "小胡" }, true)
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot_showdown.png")
	print("SHOWDOWNSHOT rows=", result_hands_box.get_child_count(), " source=", result_source.text.replace("\n", " | "))
	get_tree().quit(0 if result_hands_box.get_child_count() == 4 else 1)

func _result_test() -> void:
	var ok := 0
	_show_result("你 胡了！", "碰碰胡\n每家 8 张 · 三家共 24")
	await get_tree().process_frame
	if big and big.visible: ok += 1
	if result_detail and result_detail.visible: ok += 1
	if restart_btn and restart_btn.visible: ok += 1
	print("RESULTTEST ", ok, "/3  big=", big.visible, " detail=", result_detail.visible, " btn=", restart_btn.visible)
	_restart()
	await get_tree().process_frame
	print("RESTART ok hands=", hands[0].size(), " wall=", wall.size(), " big=", big.visible)
	get_tree().quit()

func _peng_test() -> void:
	var ok := 0
	# 用例1：手里两张 5（六万），别人打 5 → 应该碰，且副露必须是三张 5
	_new_game()
	for q in range(1, 4):
		hands[q] = [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18]
	hands[0] = [5, 5, 0, 1, 2, 9, 10, 11, 18, 19, 20, 27, 28]
	rivers[1] = [5]
	auto_peng = true
	_after_discard(1, 5)
	_resolve_claims()
	await get_tree().process_frame
	if melds[0].size() == 1:
		ok += 1
	var mt: Array = melds[0][0]["tiles"] if melds[0].size() > 0 else []
	print("T1 副露=", mt, " 手牌=", hands[0].size(), " 手里5=", _count_in(hands[0], 5), " 河1=", rivers[1])
	if mt == [5, 5, 5]:
		ok += 1
	else:
		print("T1 FAIL 副露牌不对")
	if _count_in(hands[0], 5) == 0:
		ok += 1
	else:
		print("T1 FAIL 手牌里还剩 5")

	# 用例2：手里没有 7 的对子，别人打 7 → 不该碰
	_new_game()
	for q in range(1, 4):
		hands[q] = [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18]
	hands[0] = [0, 1, 2, 9, 10, 11, 18, 19, 20, 27, 28, 31, 32]
	rivers[2] = [7]
	_after_discard(2, 7)
	_resolve_claims()
	await get_tree().process_frame
	print("T2 副露数=", melds[0].size())
	if melds[0].size() == 0:
		ok += 1
	else:
		print("T2 FAIL 不该碰却碰了: ", melds[0])

	# 用例3：手里只有一张 9，别人打 9 → 不该碰
	_new_game()
	for q in range(1, 4):
		hands[q] = [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18]
	hands[0] = [9, 1, 2, 10, 11, 18, 19, 20, 27, 28, 31, 32, 33]
	rivers[1] = [9]
	_after_discard(1, 9)
	_resolve_claims()
	await get_tree().process_frame
	print("T3 副露数=", melds[0].size())
	if melds[0].size() == 0:
		ok += 1
	else:
		print("T3 FAIL 单张也碰了")

	print("PENGTEST ", ok, "/5")
	get_tree().quit()

func _ai_peng_test() -> void:
	_new_game()
	hands[0] = [5, 0, 1, 2, 9, 10, 11, 18, 19, 20, 27, 28, 31, 32]
	hands[2] = [5, 5, 3, 4, 12, 13, 21, 22, 29, 30, 33, 6, 7]
	rivers[0] = []
	rivers[2] = []
	melds[2] = []
	_build()
	# 我打出 5（一万？不，5=六万），对家有两张应碰，然后必须由对家出牌
	_player_discard(0)
	await get_tree().create_timer(3.0).timeout
	print("AIPENG melds2=", melds[2].size(), " rivers2=", rivers[2].size(), " turn=", turn)
	if melds[2].size() == 1 and rivers[2].size() >= 1:
		print("AIPENG OK 对家碰后自己出了牌")
	else:
		print("AIPENG FAIL 对家碰后没出牌")
	get_tree().quit()


func _label_test() -> void:
	_new_game()
	melds[2] = [{ "type": "peng", "tiles": [28, 28, 28] }]
	melds[0] = [{ "type": "gang", "tiles": [5, 5, 5, 5] }]
	_build()
	await get_tree().process_frame
	var found := 0
	for c in board.get_children():
		if c is Label3D:
			print("LABEL ", c.text)
			found += 1
	print("LABELTEST found=", found)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


func _river_test() -> void:
	_new_game()
	rivers[1] = [5, 5, 5]
	rivers[3] = [8, 8, 8]
	rivers[0] = [0, 0]
	rivers[2] = [9]
	_build()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


func _kong_test() -> void:
	_new_game()
	melds[0] = [{ "type": "peng", "tiles": [5, 5, 5] }]
	hands[0] = [5, 0, 1, 2, 9, 10, 11, 18, 19, 20, 27, 28]
	wall = [3, 4, 6, 7, 8, 12]
	auto_peng = true
	_offer_self_kong(0)
	await get_tree().process_frame
	var g: int = melds[0][0]["tiles"].size() if melds[0].size() > 0 else 0
	print("KONG type=", melds[0][0]["type"] if melds[0].size() > 0 else "-", " tiles=", g, " hand=", hands[0].size(), " wall=", wall.size())
	var ok := 0
	if g == 4 and melds[0][0]["type"] == "gang": ok += 1
	if _count_in(hands[0], 5) == 0: ok += 1
	if hands[0].size() == 12: ok += 1
	if scores == [3, -1, -1, -1]: ok += 1
	print("KONGTEST ", ok, "/4 scores=", scores)
	get_tree().quit(0 if ok == 4 else 1)


func _rob_test() -> void:
	# 场景：你听 5（六万），对家补杠 5 → 应该抢杠胡
	_new_game()
	var ok := 0
	hands[0] = [0, 1, 2, 3, 4, 9, 10, 11, 18, 19, 20, 27, 27]
	melds[0] = []
	melds[2] = [{ "type": "peng", "tiles": [5, 5, 5] }]
	hands[2] = [5, 6, 7, 12, 13, 14, 21, 22, 23, 30, 31, 32, 33]
	_do_self_kong(2, 5, "bugang")
	await get_tree().process_frame
	if game_over: ok += 1
	print("ROB over=", game_over, " meld2=", melds[2], " hand0=", hands[0].size())
	if hands[0].size() == 14: ok += 1
	if scores == [20, 0, -20, 0]: ok += 1
	if result_detail and result_detail.text.contains("承包 20 分"): ok += 1
	print("ROBTEST ", ok, "/4 scores=", scores)
	get_tree().quit(0 if ok == 4 else 1)


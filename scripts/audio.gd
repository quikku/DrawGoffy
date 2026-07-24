extends Node

const SFX_PATHS := {
	"attack_start": "res://assets/sfx/attack_start.wav",
	"card_deselect": "res://assets/sfx/card_deselect.wav",
	"card_draw": "res://assets/sfx/card_draw.wav",
	"card_select": "res://assets/sfx/card_select.wav",
	"death": "res://assets/sfx/death.wav",
	"gold_gain": "res://assets/sfx/gold_gain.wav",
	"heal": "res://assets/sfx/heal.wav",
	"reflect": "res://assets/sfx/reflect.wav",
	"ui_button": "res://assets/sfx/ui_button.wav",
}

const POOL_SIZE := 8

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0

func _ready() -> void:
	for name: String in SFX_PATHS:
		streams[name] = load(String(SFX_PATHS[name]))
	for _index: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		players.append(player)

func play_sfx(name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not streams.has(name) or streams[name] == null or players.is_empty():
		return
	var player: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stop()
	player.stream = streams[name]
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

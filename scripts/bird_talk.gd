class_name BirdTalk
extends Node
# Birds say what's happening, instead of text on the screen: when the
# weather turns, a power-up kicks in or you take a tumble, the nearest bird
# that can talk (a rival, a crow on a ledge or a wire) comments on it, and
# if there's no one about, your own bird mutters to itself. Now and then a
# bird just caws, or remarks on the view.

const RANGE := 16.0                  # how far away a bird can be and still chip in
const GAP := 2.2                     # seconds between comments, so they don't pile up

const LINES := {
	"sunny": ["Sun's out. Finally.", "Warm feathers, happy bird.", "Ah, clear skies!"],
	"cloudy": ["Clouds coming in.", "Grey again.", "Clouds. Could rain. Could not."],
	"foggy": ["Can't see my own beak.", "Fog. Stay close to the wall.", "Where did everything go?"],
	"rainy": ["Rain! Ugh, wet feathers.", "Slippery ledges. Careful.", "Drip. Drip. Drip."],
	"snowy": ["Snow! My toes!", "Brr. Keep flapping, keep warm."],
	"storm": ["Storm's coming. Hide your shiny bits.", "Lightning! Keep low!", "I don't like that sky."],
	"windy": ["Hold on to something!", "Wind's up. Glide with it, not against it.", "Whoooosh!"],
	"sunseed": ["A Sun Seed! Flap all you like!", "Ooh, glowing. Endless wings for a bit!"],
	"spring": ["Spring Berry! Big bouncy jumps!", "Boing! You'll jump like a frog."],
	"cloud": ["Cloud Puff! You'll float down like a feather.", "Light as air, you are."],
	"charm": ["Crow's Charm! Shiny things come to you.", "The charm pulls treasure in. Lucky."],
	"feather": ["Ooh, a gold feather!", "Shiny! Your wings look stronger.", "Gold! Save some for me."],
	"plume": ["Keep it, I've got plenty.", "Hey, that was mine!", "Finders keepers."],
	"poison": ["Don't eat the purple ones!", "Ew. Purple berries.", "You look a bit green."],
	"fall": ["Ouch!", "That looked like it hurt.", "Up you get.", "Gravity wins again.", "Caw! You alright?"],
	"long_fall": ["Aaaaaaah!", "Nooooo!", "Down we go!"],
	"carried": ["Whoa, the wind caught me!", "Back down to the start of it..."],
	"boss_hit": ["Take that, clockwork!", "Wind down, you old tin owl!", "Ha! Felt that one, did you?"],
	"hurt": ["Ow! My feathers!", "Hot, hot, hot!", "Hey!"],
	"caw": ["Caw!", "Caw caw.", "Kraa!", "Caw?", "...caw.", "CAW!", "Caw caw caw!"],
	"idle": ["Long way up.", "Don't look down.", "Seen any shiny things?", "My wings ache.",
		"Keep to the wall, the wind's worse out there."],
	"night": ["Can't see a thing.", "Owls about. Careful.", "The tower hums at night."],
	"high": ["Thin air up here.", "Is that the ground? It's tiny.", "Clouds below us. Weird."],
	"tired": ["You look winded. Rest on a ledge.", "Catch your breath first."],
}

var tower: TowerGenerator
var player: Player
var rivals: Climbers
var weather: Weather
var enabled := false                 # only while playing
var cool := 0.0
var chatter := 6.0
var own: SpeechBubble                # your bird's own thoughts

func _process(delta: float) -> void:
	if own:
		own.tick(delta, false)
	cool = max(cool - delta, 0.0)
	if not enabled or player == null:
		return
	chatter -= delta
	if chatter > 0.0:
		return
	chatter = randf_range(7.0, 15.0)
	var others := _speakers()
	if others.is_empty():
		# Nobody about: your own bird thinks aloud, now and then
		if randf() < 0.3:
			_say_self(_remark())
		return
	var line: String = LINES.caw.pick_random() if randf() < 0.55 else _remark()
	others.pick_random().say.call(line)

# Something to say about how things are going
func _remark() -> String:
	if player.stamina < Tuning.FLAP_COST and not player.grounded:
		return LINES.tired.pick_random()
	if weather and weather.dayness < 0.3 and randf() < 0.5:
		return LINES.night.pick_random()
	if player.y > 200.0 and randf() < 0.4:
		return LINES.high.pick_random()
	if weather and weather.state_name == "sunny" and randf() < 0.3:
		return "Nice day for a climb."
	return LINES.idle.pick_random()

# A bird near the player comments on `topic` (or your own bird does, if
# `self_ok` and no one's around)
func comment(topic: String, self_ok := true, chance := 1.0) -> void:
	if not LINES.has(topic) or cool > 0.0 or randf() > chance:
		return
	cool = GAP
	var line: String = LINES[topic].pick_random()
	var others := _speakers()
	if not others.is_empty():
		others.pick_random().say.call(line)
	elif self_ok:
		_say_self(line)

# Your own bird, whatever else is going on
func say_self(topic: String) -> void:
	cool = GAP
	_say_self(LINES[topic].pick_random())

func _say_self(line: String) -> void:
	if own == null:
		own = SpeechBubble.new()
		own.position = Vector3(0, 1.6, 0)
		player.add_child(own)
	own.say(line, 2.6)

# The birds near enough to chip in: [{say: Callable}]
func _speakers() -> Array:
	var out := []
	var p := player.world_position()
	for b in rivals.birds:
		if b.world_position().distance_to(p) < RANGE:
			out.append({"say": b.say})
	var c := TowerShape.chunk_at(p.y)
	for k in [c - 1, c, c + 1]:
		if not tower.chunks.has(k):
			continue
		var ch: TowerChunk = tower.chunks[k]
		for n in ch.npcs:
			if not n.data.get("talks", false) and n.global_position.distance_to(p) < RANGE:
				out.append({"say": n.say})
		for w in ch.wires:
			for b: Node3D in w.perched:
				if b.global_position.distance_to(p) < RANGE:
					out.append({"say": func(line): ch._crow_says(b, line)})
	return out

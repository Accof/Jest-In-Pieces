class_name Records
extends RefCounted
## Lifetime records kept in the save: what has been killed and how, runs,
## floors, event medals, and the trophies those unlock in the base.

## In the order they are chalked up on the board: [key, label].
const STATS := [
	["kills", "Total kills"],
	["clowns", "Clowns killed"],
	["soldiers", "WitzSoldats killed"],
	["headshots", "Headshots"],
	["blown_up", "Blown up"],
	["staked", "Staked to the wall"],
	["limbs", "Limbs taken off"],
	["skulls", "Skulls opened"],
	["through", "Shot clean through"],
	["knees", "Knees broken"],
	["halves", "Torn in half"],
	["seated", "Killed at the table"],
	["knockdowns", "Knocked down the stairs"],
	["best_pierce", "Most in one rifle round"],
	["runs", "Runs"],
	["floors", "Floors cleared"],
	["best_floor", "Deepest floor"],
	["events", "Steel doors opened"],
	["golds", "Gold medals"],
	["tickets_earned", "Tickets earned"],
]

## Trophies on the wall: id, name, what it takes, the stat and the number,
## and what sits on the plaque.
const TROPHIES := [
	{id = "first", name = "First Laugh", desc = "Kill a clown", stat = "kills", need = 1, model = "nose"},
	{id = "k100", name = "Century", desc = "100 kills", stat = "kills", need = 100, model = "cup_bronze"},
	{id = "k500", name = "Big Top Butcher", desc = "500 kills", stat = "kills", need = 500, model = "cup_silver"},
	{id = "k2000", name = "Ringmaster of Death", desc = "2000 kills", stat = "kills", need = 2000, model = "cup_gold"},
	{id = "heads", name = "Pop Goes the Clown", desc = "50 headshots", stat = "headshots", need = 50, model = "skull"},
	{id = "boom", name = "Fireworks Night", desc = "25 blown up", stat = "blown_up", need = 25, model = "drum"},
	{id = "stake", name = "Pinned Up", desc = "10 staked to the wall", stat = "staked", need = 10, model = "stake"},
	{id = "masks", name = "Gas Mask Gallery", desc = "25 WitzSoldats killed", stat = "soldiers", need = 25, model = "mask"},
	{id = "limbs", name = "Some Assembly Required", desc = "50 limbs taken off", stat = "limbs", need = 50, model = "bone"},
	{id = "through", name = "Daylight", desc = "10 shot clean through", stat = "through", need = 10, model = "ring"},
	{id = "kebab", name = "Shish Kebab", desc = "3 in one rifle round", stat = "best_pierce", need = 3, model = "medal_bronze"},
	{id = "strike", name = "Strike!", desc = "25 knocked down the stairs", stat = "knockdowns", need = 25, model = "pin"},
	{id = "dinner", name = "Dinner Is Served", desc = "10 killed at the table", stat = "seated", need = 10, model = "plate"},
	{id = "deep5", name = "Deep Cover", desc = "Reach floor 5", stat = "best_floor", need = 5, model = "medal_silver"},
	{id = "deep10", name = "Down Among the Dead", desc = "Reach floor 10", stat = "best_floor", need = 10, model = "medal_gold"},
	{id = "gold", name = "Hold the Line", desc = "A gold medal behind a steel door", stat = "golds", need = 1, model = "cup_gold"},
]
const TROPHY_BONUS := 10            ## tickets for each new trophy


static func stat(save: Dictionary, key: String) -> int:
	if key == "kills":
		return int(save.get("total_kills", 0))
	if key == "best_floor":
		return int(save.get("best_floor", 0))
	return int((save.get("stats", {}) as Dictionary).get(key, 0))


static func add(save: Dictionary, key: String, n: int = 1) -> void:
	if not save.has("stats") or not (save.stats is Dictionary):
		save.stats = {}
	save.stats[key] = int(save.stats.get(key, 0)) + n


static func at_least(save: Dictionary, key: String, n: int) -> void:
	if not save.has("stats") or not (save.stats is Dictionary):
		save.stats = {}
	save.stats[key] = maxi(int(save.stats.get(key, 0)), n)


## One kill, filed under everything it counts for.
static func kill(save: Dictionary, c: Clown) -> void:
	save.total_kills = int(save.get("total_kills", 0)) + 1
	var d: Dictionary = c.death
	add(save, "soldiers" if c.body in ["witzsoldat", "klappersoldat"] else "clowns")
	if d.get("zone", &"") == &"Neck":
		add(save, "headshots")
	if d.get("blast", false):
		add(save, "blown_up")
	if d.get("stake", false):
		add(save, "staked")
	if int(d.get("limbs", 0)) > 0:
		add(save, "limbs", int(d.limbs))
	if d.get("head_open", false):
		add(save, "skulls")
	if d.get("through", false):
		add(save, "through")
	if d.get("broken_leg", false):
		add(save, "knees")
	if d.get("crawler", false):
		add(save, "halves")
	if c.has_meta(&"seated"):
		add(save, "seated")
	var w: String = d.get("weapon", "")
	if w != "":
		if not save.has("weapon_kills") or not (save.weapon_kills is Dictionary):
			save.weapon_kills = {}
		save.weapon_kills[w] = int(save.weapon_kills.get(w, 0)) + 1


## Trophies earned and not yet on the wall: marks them, pays the bonus, and
## returns their names.
static func new_trophies(save: Dictionary) -> Array[String]:
	if not save.has("trophies") or not (save.trophies is Array):
		save.trophies = []
	var out: Array[String] = []
	for t: Dictionary in TROPHIES:
		if t.id in save.trophies:
			continue
		if stat(save, t.stat) >= int(t.need):
			save.trophies.append(t.id)
			save.tickets = int(save.get("tickets", 0)) + TROPHY_BONUS
			out.append(t.name)
	return out


static func has_trophy(save: Dictionary, id: String) -> bool:
	return save.has("trophies") and save.trophies is Array and id in save.trophies

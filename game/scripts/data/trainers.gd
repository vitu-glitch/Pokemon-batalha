class_name TrainerData
## The trainers you can be (the profile): each one's name and its front sprite, the
## games' own as Pokémon Showdown serves them (80 × 80 px, game/trainers/). "foot" is the
## sprite's lowest row of pixels, which stands on the ground; "back", if a back sprite is
## added one day, is shown when the camera is behind the trainer.

const PX := 0.027              # meters per pixel: a person is about 1.75 m tall

const LIST := {
	"red": {"name": "Red", "sprite": "red", "foot": 77},
	"ash": {"name": "Ash", "sprite": "ash", "foot": 77},
	"lucas": {"name": "Lucas", "sprite": "lucas", "foot": 79},
	"dawn": {"name": "Dawn", "sprite": "dawn", "foot": 79},
	"ethan": {"name": "Ethan", "sprite": "ethan", "foot": 77},
	"lyra": {"name": "Lyra", "sprite": "lyra", "foot": 75},
	"hilbert": {"name": "Hilbert", "sprite": "hilbert", "foot": 79},
	"hilda": {"name": "Hilda", "sprite": "hilda", "foot": 79},
	"cynthia": {"name": "Cynthia", "sprite": "cynthia", "foot": 80},
}

const DEFAULT := "red"


static func ids() -> Array:
	return LIST.keys()


static func valid(id: String) -> String:
	return id if LIST.has(id) else DEFAULT


static var _textures := {}


## As an ImageTexture of its pixels (the menus' canvas drew the imported one in white).
static func texture(id: String) -> Texture2D:
	id = valid(id)
	if not _textures.has(id):
		var t: Texture2D = load("res://trainers/%s.png" % LIST[id].sprite)
		_textures[id] = ImageTexture.create_from_image(t.get_image())
	return _textures[id]


## A rival for the AI: not the same as yours, the same one for the same pair of Pokémon
## (no dice, so a rematch keeps it).
static func rival_for(mine: String, species: String) -> String:
	var all := ids()
	all.erase(valid(mine))
	return all[absi(hash(species)) % all.size()]

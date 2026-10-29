class_name EnemyLook
extends RefCounted
## Placeholder look per enemy type: capsule colour and scale. The cutout
## workstream replaces the "Visual" node; gameplay never depends on this.

const COLORS := {
	"zombieSlow": Color(0.45, 0.6, 0.25), "zombieFast": Color(0.55, 0.65, 0.25),
	"zombieSprint": Color(0.7, 0.6, 0.2), "zombieRiser": Color(0.35, 0.45, 0.35),
	"zombieFat": Color(0.6, 0.55, 0.35), "zombieFatSprint": Color(0.7, 0.45, 0.3),
	"zombieRiot": Color(0.2, 0.25, 0.4), "zombieRiotShield": Color(0.25, 0.3, 0.55),
	"zombieRiotNoHelmet": Color(0.3, 0.35, 0.5), "zombieArmy": Color(0.3, 0.4, 0.2),
	"zombieArmySprint": Color(0.35, 0.45, 0.15), "zombieArmyNoHelmet": Color(0.4, 0.45, 0.25),
	"zombiePolice": Color(0.2, 0.3, 0.6), "zombieCrawl": Color(0.5, 0.4, 0.3),
	"zombieSurvivor": Color(0.5, 0.5, 0.45), "zombieHatchet": Color(0.6, 0.25, 0.2),
	"zombieCleaver": Color(0.65, 0.3, 0.25), "zombieHammer": Color(0.55, 0.2, 0.3),
	"zombieHatchetSprint": Color(0.75, 0.2, 0.15), "zombieCleaverSprint": Color(0.8, 0.3, 0.2),
	"zombieHammerSprint": Color(0.7, 0.15, 0.3), "zombieDog": Color(0.4, 0.3, 0.2),
}
## Visual scale (x, y, z); collision stays one shape for all kinds.
const SCALES := {
	"zombieFat": Vector3(1.4, 1.0, 1.4), "zombieFatSprint": Vector3(1.4, 1.0, 1.4),
	"zombieCrawl": Vector3(1.0, 0.4, 1.0), "zombieRiser": Vector3(1.0, 0.9, 1.0),
	"zombieDog": Vector3(0.8, 0.4, 0.8),
}


static func color_for(ref: String) -> Color:
	return COLORS.get(ref, Color(0.45, 0.6, 0.25))


static func scale_for(ref: String) -> Vector3:
	return SCALES.get(ref, Vector3.ONE)

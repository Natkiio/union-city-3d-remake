class_name StoryExtras
extends RefCounted
## NPC records the extracted npc table does not have. Quest 500 ("Kill 3
## Zombies") names its owner Fred, but the original has no Fred NPC; this
## gives him the same shape as the others so dialogue and the NPC scene work.
## Quests merges these into Data.table("npc") at startup when absent. Put him
## in the Ballincollig street (section 16, street 2) in the level data.

## Where those NPCs stand: room id -> [{npc_id, x (Flash px), facing}].
## Fred waits near the west end of Old Road (section 16, street 2), the street
## his kill quest (killStreet 2) is about.
const PLACEMENTS := {
	"l16_s2_b0_f0_r1": [{"npc_id": "Fred", "x": 520.0, "facing": "right", "pose": "idle"}],
}

const NPCS := {
	"Fred": {
		"name": "Fred", "fullName": "Fred Dineen", "title": "Neighbour", "sex": "male",
		"enemy": "false", "friendly": true, "skinColour": "White", "hairColour": "Grey",
		"clothesTop": "male_shirtBlue", "clothesBottom": "male_jeansBlue",
		"clothesShoe": "shoeBrown", "faceAccessory": "none", "torsoAccessory": "none",
		"headAccessory": "none", "backpack": false, "hair": "short1", "facialHair": "none",
		"weapon": "none", "state": 1,
		"say1A": "Don't go out there without a weapon.",
		"content1": "Yerra, boy, would you look at the road. There's the Gone all along it and my car is on the far side.\n\nClear three of them off the road for me and I'll get the gate open.",
		"confirm1": "ACCEPT", "decline1": "DECLINE",
		"reqMet1": "THEY'RE DONE", "reqNotMet1": "NOT YET", "compResp1": "THANKS",
		"quest1": "500",
		"content1active": "Three of them, now. Hit them hard and don't let them get hold of you.",
		"content1complete": "Fair play to you. That's the gate open, so.",
	},
}

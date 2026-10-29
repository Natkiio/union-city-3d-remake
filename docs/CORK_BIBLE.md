# Cork bible

Setting and story for the remake. The rules and numbers come from `docs/ORIGINAL_ANALYSIS.md`; this file says what the data in `data/cork/` is trying to be. Everything under `data/cork/` is a sparse override deep-merged over `data/original/` (same file, same keys). Ids, numbers, doors, containers and logic keys never change; only names and text do.

## Tone

- Dark, dry, grounded. People are frightened and funny about it, the way Cork people are funny about everything: understatement, insults as affection, a joke at the worst possible moment.
- Not parody. No leprechauns, no stage-Irish "begorrah". The dialect is light and readable: "boy", "lad", "grand", "yer man", "langer", "gowl", "bleedin'", "sure look", "pet", "above in" / "below in", the Cork sing-song "like" at the end of a line. Soldiers and officials talk plainly; locals talk Cork.
- Real places are real. Real people are not: every named character is fictional, with a plausible Cork name. Real businesses are avoided (shops, pubs, chippers are invented); landmarks (the English Market, Shandon, Kent Station) are named as places only.
- Hope is thin but not absent. The ending is an escape, not a victory.

## Premise

Late October, Samhain week. A neurological infection spreads out of Cork Harbour: fever, a scream that carries for streets, then the walking dead. Locals call the infected **the Gone** ("he's gone, boy") and the strain **the Banshee**, because of the sound.

The state answers with the **Cordon**. The Defence Forces, under a hastily formed **Emergency Response Command (ERC)**, close the city, run road checkpoints, and gather civilians into **Páirc Uí Chaoimh** for "quarantine and registration". The ferries at Cobh are sunk to stop the infection leaving the harbour. Radio says it is under control. It is not.

The player lives in Ballincollig, on the west side. The original's first beat is kept: something is wrong, the partner is not answering, get across the city.

## Player situation

Mirrors the original: the player is an ordinary resident searching for their partner (`{PartnerName}`, gender and address come from the existing placeholders) and, after losing and finding them again, tries to leave by sea. The partner is bitten but has not turned.

## The plot (our twist)

The original hides the infected from the public. Ours is about **who gets saved**.

1. **The leak.** *Lee Valley Biologics*, a contract drug manufacturer at Ringaskiddy, was running a neuroprotective trial (the Banshee strain). It escaped through the plant and the harbour. The company and the government both stand to lose everything if it is public.
2. **The discovery.** A tiny fraction of the bitten do not turn for days, or at all ("slow carriers"). Their blood is the basis for a vaccine.
3. **The Registration.** At Páirc Uí Chaoimh, ERC doctors draw blood from everyone who passes through the gates. Anyone who shows *Marker 101A* is **relocated**. Families are told nothing.
4. **The Lantern List.** Relocated people are held in the old **Butter Exchange** at Shandon and drained for serum. The serum goes to the **Lantern List**: company directors, ministers' families, senior ERC officers and their dependants, to be evacuated by sea before the Cordon closes completely. Everyone else is to be held in the city.
5. **The ship.** The evacuation vessel waits at **Spike Island**, behind a wall of stacked shipping containers the ERC dropped across the Cobh pier road. The Lantern List sails from there.
6. **Haulbowline.** The naval base on Haulbowline holds the armoury, the C4 and the detonators, and the sealed cold store where the first Banshee samples were shipped in from Ringaskiddy. The base itself is nearly empty: its crews were ordered onto the Lantern ship, and the ones who refused are why Jack walked out.

The player's arc: find the partner (hospital), register (stadium), learn what "relocated" means (Barry, the ERC command post), break the partner out of Shandon, get to Cobh, get explosives from Haulbowline, blow the wall, and get on the boat to Spike Island and out past Roche's Point. The partner, now weakening, stays behind on Haulbowline in the original's beat (cutscene 6); the boat is not a clean win.

### Main quests (ids and mechanics unchanged)

| Id | Title in Cork | Beat |
|---|---|---|
| 900 | Breaking Through | Ballincollig; the army fence on the Macroom road blocks Bishopstown |
| 901 | Get Home | The flat off Curraheen Road, Bishopstown |
| 902 | Clues | Partner's note: gone to the Mercy |
| 903 | Hospital | Cross to the Mardyke and the Mercy |
| 904 | Searching | Talk to Shenice (the nurse who saw the soldiers) |
| 905 | Get to Páirc Uí Chaoimh | City centre, Shandon, Kent Station, then out to Blackrock |
| 906 | Registration | Gate, then the registration officer |
| 907 | Relocated | The list says "relocated": where? |
| 908 | Disappeared | Ask around; Barry |
| 909 | The Gents | Meet Barry in the maintenance room behind the Gents |
| 910 | Talk to Barry | His plan |
| 911 | Conspiracy Theory | Break into the ERC command post |
| 912 | Theory Proven | The orders say Butter Exchange |
| 913 | Another Way In | Shandon; Barry meets you at Hegarty's Hardware |
| 914 | Break Out | Culvert into the Butter Exchange; find the partner |
| 915 | Alive | Fetch the cell key from the ERC guard |
| 916 | Seabound | To the Cobh quays for a boat |
| 917 | Naval Base | Haulbowline for explosives |
| 918 | Explosive Components | C4, blasting caps, timer |
| 919 | Tear it down | The container wall at Cobh pier |

### Side quests (mechanics unchanged)

| Ids | Cork version |
|---|---|
| 500 | Fred wants three Gone cleared off the Ballincollig road |
| 001 to 004 | Ed and Ray, bolt cutters for the Ballincollig fence (the garage was where they always were) |
| 002 | Hank Crowley's gun shop on Western Road, his da's rifle |
| 005 | A private offers to follow you |
| 006 to 008 | Dinny Cronin, tinkerer and ex-UN peacekeeper, builds weapons for parts |
| 009, 010 | Lee Security staff stuck on St Patrick's Street; Duggan ran off with the cage key |
| 011 | Kelly in Dinny's Corner Shop (a chipper's cousin) lost her glasses |
| 015 | Jer and Paudie's van breakdown and the Dillinger couple (American tourists) in Carrigaline |
| 016 | Lisa's brother Terry, up in Ballea Woods |
| 017 | Dr Philip Hurley wants four blood samples from corpses in the woods |

A chipper replaces the diner: **The Golden Cod**.

## Section map

Original sections are kept as slots (ids, adjacency, danger, files). Danger values are unchanged.

| Slot | Original | Cork place | Danger | What is there |
|---|---|---|---|---|
| 16 | Pinedale | **Ballincollig** | 1 | Macroom road crash, Main Street, the army fence, Ed and Ray, the old house |
| 9 | Brookvale | **Bishopstown** | 4 | Wilton Road shops, Dinny's Corner Shop, the flat on Curraheen Road, CUH on the horizon |
| 13 | Canal Park | **The Mardyke** | 7 | UCC edge, the Mardyke walk, Western Road, the Mercy, Crowley Guns and Tackle |
| 12 | Newtown | **City Centre** | 9 | St Patrick's Street, Grand Parade, Lee Security, the culvert under the city |
| 5 | Stadium | **Páirc Uí Chaoimh** | 10 | Blackrock, the ground, registration, ERC command post, the culvert |
| 15 | Whistler's Forest | **Carrigaline** | 10 | Airport road, Kinsale Road roundabout, Ballea Woods, the village |
| 11 | Uptown | **Shandon** | 11 | Shandon Street, the Butter Exchange (ERC compound), Clarke's Hill, the pawnbrokers |
| 6 | Docks | **Cobh** | 16 | Harbour Row, the quays, the pier road, the container wall |
| 14 | Waterside | **Ringaskiddy** | 20 | The road to the harbour, the parish church, Haulbowline Naval Base |
| 7 | Union Island | **Spike Island** | 25 | Ferry landing, Fort Mitchel, the parade ground, the Lantern ship |
| 1 | Trenton | **Mahon Point** | none | Retail park (story link) |
| 2 | Green Plains | **Rochestown** | none | Suburban link road |
| 3 | Northwood | **Douglas** | none | Village (story link) |
| 4 | Uptown (small) | **Passage West** | none | Shipyard road (story link) |
| 8 | Riverside | **Tramore Valley** | none | Park and ring road between Bishopstown and Blackrock |
| 10 | Downtown | **Kent Station** | none | Lower Glanmire Road, the rail line to Cobh |

Geography fits the adjacency graph: the west (16, 9, 13) leads in to the centre (12), north over the river to Shandon (11), through Kent Station (10) to Blackrock (5), and east to Cobh (6) and the islands (7). Ringaskiddy (14) is reached by the Carrigaline road (15). The landmarks the brief wanted that are not slots (the English Market, Shandon bells, Butter Exchange, Elizabeth Fort, Blackrock Castle, Kent Station, Mahon Point, Douglas, the airport) live as buildings, streets and notes inside the slots above. Elizabeth Fort and the English Market sit in the City Centre; Blackrock Castle is the Páirc Uí Chaoimh street outside; the airport road is in Carrigaline.

## Characters (all fictional)

| Id | Role in Cork |
|---|---|
| Barry | Barry Cotter, school caretaker turned stadium janitor; wife taken in the first relocation |
| Jack | Jack Cullinane, ex-Naval Service petty officer; walked off Haulbowline when ordered to sail the Lantern ship |
| Jane, Dana, Shawn | Jack's people |
| Shenice | Shenice Adeyemi, nurse at the Mercy |
| Williams, Ramirez, Kowalski, Simmons, Martinez | Soldiers at the gate: Sgt. Kiely, Pte. Twomey, Pte. Coughlan, Pte. Healy, Cpl. Harrington |
| Hammond | Kate Barrett, ERC registration officer |
| King | the pawnbroker in Shandon ("The King has what you need") |

NPC and quest ids stay as in the original (they are keys); only display text is rewritten.

## Organisations

- **ERC**: Emergency Response Command. Replaces HERC. Soldiers and bio-suited doctors. Plain-speaking, clipped.
- **Lee Security**: private security on St Patrick's Street. Replaces Union Security.
- **Garda Station**: stands in for the UCPD.
- **Lee Valley Biologics**: the pharma plant. Never shown, always mentioned.

## Voice sheet

- Soldiers: short sentences, "sir", "ma'am", orders. ("Move on, now.")
- Nurses: tired, kind, black humour.
- Locals: Cork. "Yerra", "boy", "pet", "grand", "langer", "fierce", "feen" for a fellow, "the Northside" and "the Southside" as the two kinds of people.
- Notes on walls: very personal, short, one sentence of Cork humour, then something that breaks the heart.

## Test

`tests/test_cork.gd` checks that every file parses, key sets match the originals, quest ids and rewards are unchanged, and no original-city word survives in any text.

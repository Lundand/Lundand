# The capital

The capital of House Lundand, its forest and the thieves' hideout are generated from data when a server starts.
`ServerStorage/ServerData/CityLayout` holds the plan. `ServerScriptService/Server/Tools/CityBuilder` turns it into
parts. `Server/Domain/LayoutRules` checks the plan without Studio.

![Master plan](city-master-plan.png)

The plan above is drawn by `tools/render_plan.py`. North is up, the forest lies beyond the south gate and the harbour
opens to the sea in the east. Each dot marks a door.

| Colour | Meaning |
| --- | --- |
| blue | For sale: a player can buy it |
| tan | NPC home or business |
| orange | Shop, smithy or tavern |
| gold | Public institution |
| purple | Castle |
| teal | Guild hall |
| red dots | NPCs |
| magenta outlines | Hideout rooms, underground |

## Scale

| | |
| --- | --- |
| Walls | 960 x 840 studs, 30 high, towers every 120 studs |
| Gates | South gate to the forest, north gate to the mountain road, sea gate into the harbour |
| Streets | Main roads 12 to 16 studs, side streets 6 to 8, alleys 4 to 5 |
| Storeys | 12 studs floor to floor (11 clear inside); doors 5 wide (6 for public buildings) and 8.4 high |
| Enterable buildings | 549, almost all two or three storeys, in attached rows sharing walls |
| Homes for sale | 194 houses and 144 flats (in 48 apartment buildings); 347 property IDs with the 6 storefronts and 3 guild halls |
| Parts | About 65,000, of which 542 cast light |

## Districts

- **Merchant Square**: a paved disc 112 studs across with the fountain and the Heart of Realms at its centre. A
  ring of three-storey shops surrounds it, with the Adventurers' Guild and the Square Inn facing it. Market streets
  and the six player storefronts run south of it.
- **Church**: north-west of the square, reached by a lane from the plaza. It has a nave, aisles, stained glass,
  a bell tower, a sacristy and a side chapel. The awakening circle is set into the nave floor; new characters
  appear in the aisle beside it.
- **Castle**: north. Curtain walls and towers enclose a courtyard. Inside are the keep (throne hall, guard room,
  administration, and royal apartments upstairs), the Royal Library (a double-height reading hall with a gallery),
  the guard barracks, the chancery, the servants' hall and the royal gardens. House Lundand's crest (a silver tower
  under a gold rift-star on deep blue) appears on banners, gates and the throne hall.
- **Noble quarter**: north-west. Sixteen walled estates with gardens line the noble avenue; nine are for sale.
- **Old town (residential)**: west and south. Dense rows of townhouses and apartment buildings around courtyards.
- **Craftsman quarter**: north-east, along the north gate road. The City Forge, the apothecary, the Craftsmen's
  Guild, the three guild halls, and workshops with homes above.
- **Harbour**: east. A quay with cranes and cargo, six piers, five ships, warehouses, the customs house, the fish
  market, the Salt and Anchor tavern and the cargo office.
- **Slums**: south-west, against the wall. Small, low, weathered houses on narrow alleys, with laundry lines and a
  well. The Crooked Lantern tavern hides the way down to the hideout.

## Inside the buildings

Every building with a door has rooms you can walk through. Interiors follow the building type:

- **Townhouses**: a living room with a hearth, a kitchen, and bedrooms upstairs.
- **Shops**: a counter, shelves and goods for the trade (weapons, armour, bakery, potions and so on), a storeroom,
  and the shopkeeper's home above.
- **Smithies**: a forge, an anvil and a weapon rack.
- **Taverns and inns**: a bar, tables and a hearth; guest rooms upstairs off a corridor.
- **Apartments**: one flat per floor, with a door onto the shared stair.
- **Mansions**: an entrance hall, a dining hall, a library and grand bedrooms.
- **Slum houses**: one cramped room per floor.

Stairs climb inside a lane along one wall. The walking surface is one smooth ramp with treads drawn on it, so
characters and the camera move cleanly. `tools/inspect-city.luau` builds the whole city and checks that nothing
solid stands in any doorway, at the foot of any flight, or on any landing.

## Owning a home

- **Buying.** Walk up to a building's deed sign (a plaque by the door, or beside each flat's door on the stair) to
  see its price and buy it. The purchase uses the existing four-step protocol in `PropertyOwnership`: reserve,
  charge, commit, record. It is server-checked and safe across servers, and an interrupted purchase is settled on
  the buyer's next join. Each player may own one home and one shop.
- **Visiting.** Walking in never grants ownership. Anyone can look round a home nobody owns.
- **Privacy.** Once a home is owned, `PropertyService` checks twice a second where every player is. It uses a
  64-stud grid of the property volumes, so the cost stays flat at 200 players. Anyone inside a home they aren't
  allowed in is shown out to the door. Owners choose Only me, My friends or Anyone in the property window.
- **What can't be bought.** Public institutions, NPC businesses, the castle, the hideout, warehouses and other story
  places carry no deed. `CityLayout.spec` checks this.

## The forest and the hideout

The forest (`CityBuilder/Forest`) starts at the south gate. A dirt road winds south past a shed and fields into
thickening woods. There are side paths, three clearings, low hills, rocks, roots, fallen logs, a ruined cabin, an
old watchtower and a forgotten shrine. The wolves' den is a ring of boulders around a cave mouth. The spawner and
gathering zones keep their IDs: `ForestEdge`, `ForestDeep` and `ForestDen`.

The hideout (`CityBuilder/Hideout`) is reached on foot. A trapdoor in the Crooked Lantern's back room leads down to
the cellar. Behind a wine rack swung aside, a landing and a long stair lead to the rooms below:

- the entrance
- the stolen-goods store
- the meeting hall
- the bunks
- the guarded inner room
- the leader's room

The spawner zones keep their IDs (`HideoutEntrance`, `HideoutHall`, `HideoutInner`, `HideoutThrone`). The old
teleporting cellar door is gone; `WorldService` still builds any passage listed in the layout.

## Running 50 to 200 players

- **Streaming.** The patched place turns on `Workspace.StreamingEnabled`, so each client loads only what is near
  it. Places, NPC anchors and markers live in a model set to stream as Persistent, so quest guidance and prompts
  always find them.
- **Lights.** Real lights are capped per building. Homes get at most one; past the cap a lamp still glows but
  casts no light.
- **Part budget.** Storeys share wall pieces where windows stack in columns, and furniture uses a few parts per
  piece.
- **Building time.** The city builds in a few seconds at server start, pausing between batches. The ground and the
  spawn point go in first.

To skip building at start, run the builder in Studio edit mode and save the place:

```lua
require(game.ServerScriptService.Server.Tools.CityBuilder).build()
```

## Changing the city

1. Edit `ServerStorage/ServerData/CityLayout`. That covers hand-placed landmarks, district grids (street lines
   and widths), lot sizes, storeys, how many homes are for sale, the forest and the hideout.
2. Run `lune run tools/check-layout.luau`. It reports overlaps, roads through buildings, unreachable doors, stairs
   that don't fit, and property or location IDs that are missing or placed twice.
3. If the number of homes changed, update the counts in `ReplicatedStorage/Shared/Config/World`. The check above
   names the missing or unknown IDs.
4. Run `lune run tools/inspect-city.luau` and `lune run tools/run-tests.luau`.
5. Look at it: `lune run tools/dump-layout.luau && python3 tools/render_plan.py` draws the plan.
   `tools/export-parts.luau` and `tools/render_view.py` draw a rough 3D view of an area or a single building.

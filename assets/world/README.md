# World assets

Drop models into the folder named after what they show. Nothing needs registering: the
folder is scanned when the world map opens. A folder with no files keeps the placeholder.

```
assets/world/
  tiles/<terrain_id>/        the hex ground      grass, hills, forest, marsh, river, lake, mountain, wyrd_forest, ocean
  props/<terrain_id>/        extra scenery on a tile (trees, rocks, reeds), 0-3 per hex
  nodes/<node_id>/           resource nodes      fish, wood, stone, runelith, heartroot, spring ...
  locations/<location_id>/   pre-placed places   ruin, shrine, lair, watchtower ...
  settlements/<kind>/        npc_settlement, player_settlement
  party/party/               the player's party marker
```

The placeholder colours tiles by biome and shows terrain with a model on top. Real tile art for a terrain replaces the whole tile (put the biome look into the model or its materials); `props/<terrain_id>/` models replace the placeholder models and keep the biome-coloured tile underneath only if you also leave `tiles/<terrain_id>/` empty.

The ids are the file names in `content/terrain`, `content/nodes` and `content/locations`.

## Several versions of one thing

Every file in a folder is a variant. A hex picks one with a hash of the world seed and its
coordinates, so the same seed always shows the same picture. Put three models in
`tiles/grass/` and the grassland gets three looks.

## Rotation is free variety

- **Tiles** are turned in steps of 60 degrees. A hex looks the same turned that way, so
  N models give 6 x N looks. Author them so they still fit when turned (the model's
  outline is a regular hexagon).
- **Everything else** (props, nodes, locations, settlements) gets any rotation around the
  vertical axis.

## Model rules

- Formats: `.glb`, `.gltf`, `.tscn`, `.scn`, `.obj`.
- Y is up, one unit is one metre of map. A hex has **circumradius 1.0** and is **pointy-top**
  (corners point along +/-Z, flat sides face +/-X), so the width across the flats is 1.732.
- Origin at the hex centre. A tile's top surface should sit at its terrain `height`
  (see `content/terrain/*.tres`) so props and markers line up. Props, nodes and locations
  have their origin on the ground.
- Props must stay inside the hex (keep them below roughly 0.65 from the centre).
- Keep nodes, locations and settlements to about 1 unit across. They share a hex with other
  things and the party.

## Which things share a hex

A hex has one terrain tile, any number of props, at most one resource node, at most one
location, at most one settlement, and any number of parties. All are drawn together, so keep
the models small and low enough to see each other.

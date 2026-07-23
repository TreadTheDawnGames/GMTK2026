# Terrain Layering Guide

`TerrainManager` owns solid cells, depth, ore yields, and encounter openings.
`TerrainLayerRenderer` turns those results into streamed art. Changing artwork
does not change where the player can stand or how much depth a hit earns.

## Replace terrain art

Edit `resources/mining/default_terrain_layer_profile.tres`.

- `Layer Tints` lists strata from the foreground surface to the deepest dirt.
- `Layer Fill Textures` accepts optional seamless textures in the same order.
- `Small Hole Masks` and `Big Hole Masks` use transparent areas as the
  opening made by a strike.
- `Layer Z Indices` keeps the foreground above the miner and lower strata
  behind the miner.

All layer arrays should describe the same number of strata. Fill textures are
sampled in continuous terrain coordinates, so chunk boundaries do not restart
the pattern.

## Author hole masks

Use a square transparent PNG. Opaque pixels preserve terrain and transparent
pixels define the organic opening. Keep transparent space fully enclosed by
the image so the renderer can measure and scale it.

The foreground mask is expanded most, and each deeper mask is expanded less.
Each layer is also offset from the impact center. This reveals uneven circular
rims instead of one repeated silhouette. Overlapping impacts are combined in
the persistent chunk masks rather than drawn as separate decals.

## Tuning

- `Rim Width` controls the visible distance between strata.
- `Core Hole Padding` keeps the central fall path visually open.
- `Big Hole Minimum Size` selects the large mask family.
- `Keep Back Layer Solid` uses the deepest color as a back wall.
- `Mask Pixels Per Cell` controls edge detail and upload cost. The default of
  four keeps normal impacts inexpensive while retaining smooth silhouettes.

Chunks outside the camera range are released. Their impact records remain and
are replayed when the player returns to that depth.

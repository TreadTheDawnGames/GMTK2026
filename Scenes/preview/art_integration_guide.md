# Art integration

The gameplay scenes keep their current stand-in art until an authored resource is
assigned. Use the two preview scenes to check art without starting a run.

## Miner art

1. Duplicate `res://resources/characters/default_miner_skin.tres`.
2. Assign aligned cutout textures to the new `MinerSkin`.
3. Open `res://Scenes/preview/miner_rig_preview.tscn`.
4. Assign the skin to the preview root and run the scene.
5. Use the guide toggle to check the body, head, arm, pickaxe, and fixed
   `ChipOrigin` anchors.

All miner textures should share the same canvas size and origin. Empty texture
slots preserve the black-and-white stand-ins. Animation clips continue to move
the existing pivots, so replacing textures does not change mining timing.

## Pickaxe art and effects

Duplicate a resource in `res://resources/pickaxes/` and assign its handle texture,
head texture, head offset, scale, swing sound, impact sound, or optional impact
particle scene. Set `impact_offset` to the head's striking tip so art, particles,
and terrain contact stay aligned. The equipped definition supplies gameplay
tuning and its matching presentation. The shop coordinator applies it to the
mining controller, miner rig, and hit particles together.

Impact effect scenes must use a `GPUParticles2D` or `CPUParticles2D` root and
finish on their own. Keep browser variants brief and low-count; runtime limits
overlap, but it cannot reduce an authored scene's particle amount.

## Terrain art

1. Duplicate `res://resources/art/default_terrain_art.tres`.
2. Assign repeating surface variants and optional cavity, fresh-edge, and ore
   textures.
3. Choose `surface_variant_index` and set `layered_rendering_enabled` to `true`.
4. Open `res://Scenes/preview/terrain_art_preview.tscn`.
5. Assign the profile to `TerrainManager > Art Profile Override`.
6. Run the scene and switch between final, solid, edge, and ore views.

Surface textures sample continuous world coordinates, so chunk boundaries do not
restart the texture. Depth bands in `MiningConfig` select profiles during normal
play. One chunk uses one profile, so a depth-band transition snaps to the next
loaded chunk rather than splitting a texture inside that chunk.

The non-legacy brush shapes are preview tools only. Normal play keeps the current
tunnel rules. Visible terrain damage is revealed in bounded pixel batches by
`TerrainBreakAnimator`; its speed and per-frame cap are editable on the mining
scene. The physical surface and player depth advance with those revealed pixels,
while reserved cells keep queued hits from collecting the same terrain twice.

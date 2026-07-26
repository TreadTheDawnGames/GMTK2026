# Pickaxe authoring

This is the single checklist for adding a pickaxe and making it available in
the production run. The collectible pickaxe and the gameplay progression level
are deliberately separate:

- `PickaxeDefinition` identifies the reward, prevents duplicate ownership, and
  selects the newest visible wood, silver, or gold pose set.
- `EncounterProgressionLevel` controls production mining and timing behavior.
- `DepthCharacterEncounter.pickaxe_reward` decides which encounter grants the
  collectible.
- `PickaxeProgression` owns the current loadout. UI code must not search for it
  or read `loadout.equipped` directly.

## Add the collectible

1. In Godot, create a `PickaxeDefinition` resource under
   `res://resources/pickaxes/` using a `snake_case.tres` filename.
2. Fill out its identity:
   - `id`: a unique, non-empty `snake_case` `StringName`. Match the filename
     when practical. Duplicate IDs are treated as the same owned pickaxe.
   - `display_name`: the player-facing name.
   - `description`: the player-facing explanation.
3. Set `visual_tier` to the authored wood, silver, or gold pose set. Keep
   `hammer_head_color` as the layered-preview/future-art fallback.
4. Keep the legacy mining multipliers at `1.0`, `special_effect` at `NONE`,
   and `target_scenes` empty unless an isolated legacy preview explicitly
   needs those values. Production gameplay overrides those fields with an
   `EncounterProgressionLevel`.
5. Open the intended resource in `res://resources/encounters/` and assign the
   new resource to `pickaxe_reward`. The encounter controller calls
   `PickaxeProgression.grant_upgrade()`, so no UI lookup or extra scene
   connection is required.

For a starting tool instead of an encounter reward, assign the definition to
`GameRoot/MiningScene/Systems/PickaxeProgression.starter_pickaxe` in
`res://Scenes/mining/mining_proof.tscn`.

## Add the production gameplay change

The starting rules are `progression_level_0.tres`. Completing encounter index
`N` applies `progression_level_(N + 1).tres`. Edit the matching resource under
`res://resources/mining/`; do not put production timing or mining rules on the
pickaxe merely because the same encounter awards it.

Fill every `EncounterProgressionLevel` field:

- `impact_size`: complete base hit width and depth tier.
- `double_hit`: whether one timing success queues a second mining swing.
- `mine_animation_speed`: authored successful-swing speed tier.
- `combo_impact_scale`: multiplier for only the combo-added impact.
- `target_scenes`: non-empty pool of valid `TimingTarget` scenes.
- `slider_speed`: pixels per second for the main timing bar.
- `starting_target_count`: baseline target count, at least one.
- `bonus_target_combos`: strictly increasing, positive combo thresholds.

`MiningConfig.progression_levels` must continue to contain levels zero through
nine in order. Each level is complete and replaces the previous one; values do
not inherit from an earlier resource.

## Add a new pickaxe-era rule

A production rule such as “show a second recovery bar” belongs on
`EncounterProgressionLevel`, not on `PickaxeDefinition`, because production
behavior is level-owned and pickaxes accumulate.

1. Add one typed exported field to `EncounterProgressionLevel`.
2. Validate it in `EncounterProgressionLevel.is_valid()` when invalid authored
   combinations are possible.
3. Pass it in `EncounterProgression.apply_level()` to the owning gameplay or
   timing component through a named typed method.
4. Store and apply it in that component. Do not make `MiningUI` locate
   `PickaxeProgression`, inspect the scene tree, or read the global run state.
5. `/find` the field and setter names. The resource declaration, coordinator
   handoff, and consumer must all be visible in the results.

## Verify

Run:

```powershell
godot --headless --path . --script res://tests/smoke_verify.gd
godot --headless --path . --script res://local_tests/integration_verify.gd
```

Then play through the granting encounter and verify the reward is granted once,
the full pose set changes tier, the intended progression level activates, a new
run restores level zero, and the timing/mining behavior matches the authored
level.

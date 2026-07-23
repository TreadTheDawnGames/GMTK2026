# Miner Animation Guide

The playable miner uses the seven-frame drawing in
`Assets/Characters/MrNotOffensiveName-Sheet.png`. `MinerRig` keeps animation,
impact timing, facing, audio, and playback speed in one scene.

## Scene controls

```text
MinerRig                 Fixed player screen position
├── VisualRoot           Flips the complete miner for left/right aim
│   ├── DrawnMinerSprite Seven-frame visible animation
│   └── DrawnImpactPoint Hammer contact location on the strike frame
├── ChipOrigin           Fixed center used to calculate the player's fall
└── AnimationPlayer      Owns idle, success, miss, and preview clips
```

`BodyPivot` and its cutout children remain hidden in the scene as the earlier
stand-in asset. They are not the visible gameplay character.

## Preview an animation

1. Open `miner_rig.tscn`.
2. Select `AnimationPlayer`.
3. Choose `idle`, `wind_up`, `wind_down`, `mine_success`, or `mine_miss` in
   the Animation panel.
4. Press the play triangle.

`RESET` stores the neutral frame and should not be used as an action clip.

## Edit the mining swing

The visible animation changes only two `DrawnMinerSprite` properties:

- `frame` chooses one drawing from the sheet.
- `position` keeps the character's feet aligned while poses change height.

`mine_success` currently uses:

- `0.00`: frame 1, wound up at the upper-right.
- `0.09`: frame 5, fast transition into the strike.
- `0.16`: frame 2, ground contact.
- `0.38`: frame 0, return to idle.

The method track calls `_emit_success_impact()` at `0.16`. Move that method
key with the contact drawing if the strike timing changes. Terrain, particles,
audio, and the dig number all begin from that callback.

`wind_up` and `wind_down` contain the same poses as separate clips for
previewing a larger anticipation. `play_full_swing()` plays them in order.

## Change speed

`Animation Speed Multiplier` on `MinerRig` changes every clip. The mining
controller also supplies the equipped pickaxe speed and combo bonus when it
calls `play_success()`.

```gdscript
miner_rig.set_animation_speed_multiplier(1.5)
```

Playback speed changes timing without moving the impact key relative to the
visible strike.

## Replace the sheet

Keep seven 256-by-256 frames in one horizontal row to replace the drawing
without changing the scene. If the frame count or layout changes, update
`DrawnMinerSprite.hframes` and the frame keys together.

Keep the contact drawing aligned with `DrawnImpactPoint`. `ChipOrigin` stays
fixed because it defines where the player falls, not where the artwork moves.

## Test in gameplay

Run `mining_proof.tscn` and press Space or left click while the timing slider
overlaps a target. A correct result should play `mine_success`, break terrain
on the contact frame, and advance depth. A miss should play `mine_miss`
without changing terrain or depth.

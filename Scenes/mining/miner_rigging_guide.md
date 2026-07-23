# Miner Cutout Rigging Guide

The miner uses a simple cutout rig made from `Node2D` pivots. It does not
require a `Skeleton2D`, bones, skin weights, or frame-by-frame sprite sheets.

## Controls

```text
MinerRig                         Keep fixed at the player screen position
├── VisualRoot                   Whole-character bounce, squash, and recoil
│   ├── BackHairSprite           Optional art behind the body
│   └── BodyPivot                Torso rotation
│       ├── BodySprite           Body art
│       ├── HeadPivot            Head counter-rotation
│       │   ├── HeadSprite
│       │   └── FrontHairSprite
│       └── ArmPivot             Main swing rotation
│           ├── ArmSprite
│           ├── ForearmSprite
│           ├── HandSprite
│           └── PickaxePivot     Tool follow-through
│               ├── PickaxeHandleSprite
│               ├── PickaxeHeadSprite
│               └── ImpactPoint  Authored striking tip
├── ChipOrigin                   Fixed player fall column; never animate
└── AnimationPlayer
```

The basic rig has only three animation controls:

1. `BodyPivot` moves the whole body. The head, arm, and tool follow it.
2. `ArmPivot` creates the main swing.
3. `PickaxePivot` adds tool follow-through.

`HeadPivot` is an optional fourth polish control for head counter-rotation.
Do not animate `MinerRig` or `ChipOrigin`.

## Preview an existing animation

1. Open `miner_rig.tscn`.
2. Select `AnimationPlayer` in the Scene tree.
3. In the bottom Animation panel, open the dropdown that currently says
   `RESET`.
4. Choose `idle`, `wind_up`, `wind_down`, `mine_success`, or `mine_miss`.
5. Press the play triangle in the Animation panel.

`RESET` is the neutral property state used by Godot. Do not author the swing
inside `RESET`.

## Edit the successful swing

1. Select `mine_success`.
2. Move the timeline cursor to the desired time.
3. Select a pivot such as `ArmPivot`.
4. Rotate or move it in the 2D viewport.
5. In the Inspector, expand `Transform` and press the key icon beside
   `Rotation`, `Position`, or `Scale`.
6. Repeat for the other poses and pivots.
7. Press play to preview.

Suggested poses:

- `0.00`: raised anticipation pose.
- `0.16`: ground contact and strongest tool follow-through.
- `0.38`: return to the neutral pose.

The successful timing result queues this animation. The `_emit_success_impact`
method key at `0.16` is the authoritative contact moment that starts terrain
breakage, sound, particles, and shake. Moving that key changes gameplay contact
timing, so keep it aligned with `ImpactPoint` touching the ground.

`wind_up` and `wind_down` are starter clips for authoring the complete visual
swing. Each has only three tracks: body position, arm rotation, and pickaxe
rotation. `mine_success` remains the gameplay contact/recoil clip so adding
the practice clips does not silently delay terrain damage.

## Change animation speed

Select the `MinerRig` root and change `Animation Speed Multiplier` under the
Playback section. `1.0` is authored speed, `0.5` is half speed, and `2.0` is
double speed.

Another gameplay system can change the same number without changing keys:

```gdscript
miner_rig.set_animation_speed_multiplier(1.5)
```

`Combo Speed Bonus` is a separate optional increase applied to successful
gameplay hits. Use `play_full_swing()` to preview `wind_up` followed by
`wind_down` from code.

For a miss, use a slower overshoot that never visually contacts `ChipOrigin`.
For idle, keep movement small so it does not compete with the timing bar.

## Replace the stand-ins with art

The easiest art delivery is a set of transparent PNG layers:

- back hair
- body
- head
- front hair or face details
- upper arm
- forearm
- hand

Duplicate `res://resources/characters/default_miner_skin.tres`, assign the
textures to that `MinerSkin`, and use the rig preview scene to verify alignment.
The rig keeps the current stand-ins for empty body and head slots. It hides the
arm stand-in after the upper-arm, forearm, and hand textures are all assigned.

Put handle and head textures, sounds, scale, color, and the striking-tip
`impact_offset` on a `PickaxeDefinition`. The equipped definition updates the
rig automatically.

## Test in gameplay

Open `mining_proof.tscn` and run the scene. Press Space or left click while the
timing slider overlaps its target. A correct result should play `mine_success`,
start the pixel break wave at `ImpactPoint`, and advance the player as pixels
finish fading under `ChipOrigin`. A miss should play `mine_miss` without
changing terrain or depth.

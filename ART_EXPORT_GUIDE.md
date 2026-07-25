# Game Art Export Target

For new character and prop art, export the final PNG with its longest side at
**1024 px or less**. Use the actual in-game framing as the target rather than
the drawing-canvas size, trim unused transparent margins, and do not upscale a
smaller source.

- Full-screen or near-full-screen moving props: up to 1024 px.
- Characters and smaller props: 512 px is preferred.
- Keep the original layered working file outside the Godot project.
- Enable mipmaps and use linear filtering for art that moves or is downscaled.

Before delivery, check the exported PNG dimensions. A 2224x1668 drawing canvas
must not be delivered directly as the runtime asset.

## Where the character sits in its canvas

A cutscene marker positions an actor's **root**, and the root is meant to be the
point the character stands on. Everything that places a character — entrance and
conversation markers, the cafe line-up, the offset that keeps a speaker beside
the miner — is measured from it. So the canvas has to agree:

- Centre the character horizontally in the canvas.
- Put the soles on the bottom edge, trimming the empty rows beneath them.
- Leave `sprite_offset.x` at zero. A horizontal nudge there silently cancels
  every marker offset that positions the actor, and nothing on screen says so.
  Cheese Girl carried a 75 px nudge to compensate for her art sitting off-centre
  in an untrimmed canvas; the stage asked for 64 px of clearance from the miner
  and she was drawn on top of him instead.
- `sprite_offset.y` is then just half the drawn height, negative: it lifts the
  centred sprite so the bottom edge lands on the root.

Trimming pays twice. The importer caps the longest side at 512 px, so a subject
floating in a large canvas spends most of that budget on empty space and arrives
blurry. Cheese Girl's 623x1166 subject inside a 2224x1668 canvas imported at
143x268; trimmed to 274x512 it draws the same size at nearly twice the detail.

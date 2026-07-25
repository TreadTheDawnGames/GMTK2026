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

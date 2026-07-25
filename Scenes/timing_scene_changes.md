# Timing scene change log

Caspian owns the timing bar. `AGENTS.md` marks these files adapt-only:

- `Scenes/TimingWindow.tscn`
- `Scenes/slider_timing_window.tscn` and `Scenes/slider_timing_window.gd`
- `Scripts/timing_windows/timing_window.gd`
- the timing scene tree

This file exists so every change to them is visible in one place instead of
being buried in a commit that also touched ten other files.

## The rule

**A change to a Caspian-owned file gets its own commit, touching nothing else.**
The subject line starts with `Caspian timing scene:` so the whole history is one
search. Everything built *around* the bar goes in separate commits.

To see every change ever made to his files:

```bash
git log --oneline -- Scenes/TimingWindow.tscn Scenes/slider_timing_window.tscn Scenes/slider_timing_window.gd Scripts/timing_windows/timing_window.gd
```

To read one of them as a diff:

```bash
git show <commit>
```

## Changes so far

| Commit | File | What | Why |
| --- | --- | --- | --- |
| `6b6e8bf` | `TimingWindow.tscn` | `ComboLabel` re-anchored from the viewport's top-right to `MiningWindow`'s bottom-centre, and moved inside the frame's upper-left interior. | It sat across the frame art's drawn top edge. The nine-slice `expand_margin_top` of 20 px put wood underneath the text. Its old top-right anchors also meant it drifted relative to the bar at other window sizes. |
| `5f423e6` | `TimingWindow.tscn` | `ComboLabel` hidden (`visible = false`). Node kept. | The combo is now the charge gauge drawn below the bar, which also shows the effect ceiling and the quick-save threshold. Hidden rather than deleted so `timing_window.gd` keeps its `combo_label` target and the number can be switched back on for debugging. |
| `7c36152` | `TimingWindow.tscn` | `RecoveryWindow` moved up: `offset_top` -151 → -178, `offset_bottom` -134 → -161. | `MiningWindow`'s frame is a nine-slice whose `expand_margin_top` of 20 puts drawn wood 20 px above its own rect, reaching -148. At -151 the quick-save strip sat inside that art and the two frames collided. Size, anchors, speed, grace, and targets are unchanged. |

Nothing in `slider_timing_window.gd`, `slider_timing_window.tscn`, or
`timing_window.gd` has been modified. Every behaviour change lives outside them.

## What was deliberately *not* changed

`TimingBarFeedback` (`Scripts/timing_windows/timing_bar_feedback.gd`) draws all
of the bar's hit feedback, the charge gauge, and the frame the quick-save strip
borrows, and it does so **strictly read-only**. It reads rects, slider position,
combo, config, and StyleBoxes; it never writes a property back. StyleBoxes are
tinted on cached duplicates so the bar's own resources are untouched.

`local_tests/verify_bar_readonly.gd` pins that promise. It records the slider
position, backing width, speed multiplier, every target placement, and the frame
StyleBox's `modulate_color`, drives a range of presses through the overlay, and
fails if any of them moved:

```bash
godot --headless --path . --script res://local_tests/verify_bar_readonly.gd
```

The same invariant is covered inside the main suite by
`_test_impact_feel_presentation`, which runs under
`GMTK_LOCAL_TEST_PROFILE=full`.

## If a change here breaks something of Caspian's

Each row above is one commit touching one file, so reverting is:

```bash
git revert <commit>
```

The overlay tolerates the bar not being what it expects: it looks up the frame
by searching for a textured StyleBox rather than by a hard-coded node path, and
falls back to the bar's own box when there is none. Renaming or restructuring
nodes inside the timing scene will not break it.

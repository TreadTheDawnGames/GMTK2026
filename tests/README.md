# Fast shared verification

Run this tracked smoke gate before handing a branch to another agent:

```powershell
godot --headless --path . --script res://tests/smoke_verify.gd
```

It verifies that the configured entry scene resolves, the production mining
scene loads, its composition references and streaming signal are intact, and
one real terrain dig changes logical occupancy.

This is intentionally smaller than
`res://local_tests/integration_verify.gd`. The local suite remains the
required detailed behavior check; this smoke gate exists to catch parse,
scene-path, and composition breakage quickly in every Git checkout.

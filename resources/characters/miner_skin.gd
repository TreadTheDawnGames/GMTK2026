class_name MinerSkin
extends Resource

## Supplies aligned cutout textures for one miner appearance.

@export_category("Body")
@export var body_texture: Texture2D
@export var head_texture: Texture2D
@export var upper_arm_texture: Texture2D
@export var forearm_texture: Texture2D
@export var hand_texture: Texture2D

@export_category("Hair")
@export var back_hair_texture: Texture2D
@export var front_hair_texture: Texture2D

@export_category("Appearance")
@export_range(0.1, 4.0, 0.05) var default_scale: float = 1.0
@export var skin_tint: Color = Color.WHITE

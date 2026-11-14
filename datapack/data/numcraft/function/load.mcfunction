scoreboard objectives add numcraft.cooldown dummy
scoreboard objectives add numcraft.id dummy
scoreboard objectives add numcraft.xp_levels dummy
scoreboard objectives add numcraft.xp_points dummy
scoreboard objectives add numcraft.var dummy
# markers act only in loaded chunks, and the arrival point must be loaded for a teleport
execute in numcraft:lab run forceload add 0 0
# the vaults of the first 16 travellers; lab/vault_prepare loads the others
execute in numcraft:vault run forceload add 0 0

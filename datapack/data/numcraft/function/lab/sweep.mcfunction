# The lab biome has no spawn list; this removes what arrives in another way.
# A selector with no distance matches in each dimension, so each one has it.
# A mob with the tag numcraft.keep stays. An empty loot table: no drops, and
# the small slimes of a split go in the next sweep.
execute in numcraft:lab as @e[type=#numcraft:hostile,tag=!numcraft.keep,distance=0..] run data merge entity @s {DeathLootTable:"minecraft:empty"}
execute in numcraft:lab run kill @e[type=#numcraft:hostile,tag=!numcraft.keep,distance=0..]
schedule function numcraft:lab/sweep 10s replace

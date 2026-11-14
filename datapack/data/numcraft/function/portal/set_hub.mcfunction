# Run where the hub portal must be, in a loaded chunk:
#   execute in minecraft:overworld positioned <x> <y> <z> run function numcraft:portal/set_hub
kill @e[type=minecraft:marker,tag=numcraft.to_lab]
summon minecraft:marker ~ ~ ~ {Tags:["numcraft.to_lab"]}
data modify storage numcraft:portal hub.x set from entity @e[type=minecraft:marker,tag=numcraft.to_lab,limit=1] Pos[0]
data modify storage numcraft:portal hub.y set from entity @e[type=minecraft:marker,tag=numcraft.to_lab,limit=1] Pos[1]
data modify storage numcraft:portal hub.z set from entity @e[type=minecraft:marker,tag=numcraft.to_lab,limit=1] Pos[2]
forceload add ~ ~
execute in numcraft:lab run kill @e[type=minecraft:marker,tag=numcraft.to_hub]
execute in numcraft:lab run summon minecraft:marker 8.5 -60 0.5 {Tags:["numcraft.to_hub"]}

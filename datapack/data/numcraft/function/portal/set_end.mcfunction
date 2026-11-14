# The vault dimension is not in this list on purpose: no portal goes there.
data remove storage numcraft:portal new
execute if dimension minecraft:overworld run data modify storage numcraft:portal new.dim set value "minecraft:overworld"
execute if dimension minecraft:the_nether run data modify storage numcraft:portal new.dim set value "minecraft:the_nether"
execute if dimension minecraft:the_end run data modify storage numcraft:portal new.dim set value "minecraft:the_end"
execute if dimension numcraft:lab run data modify storage numcraft:portal new.dim set value "numcraft:lab"
execute unless data storage numcraft:portal new.dim run return fail
$kill @e[type=minecraft:marker,tag=numcraft.portal,nbt={data:{name:"$(name)",end:"$(end)"}}]
$summon minecraft:marker ~ ~ ~ {Tags:["numcraft.portal","numcraft.new"],data:{name:"$(name)",end:"$(end)",other:"$(other)"}}
data modify storage numcraft:portal new.x set from entity @e[type=minecraft:marker,tag=numcraft.new,limit=1] Pos[0]
data modify storage numcraft:portal new.y set from entity @e[type=minecraft:marker,tag=numcraft.new,limit=1] Pos[1]
data modify storage numcraft:portal new.z set from entity @e[type=minecraft:marker,tag=numcraft.new,limit=1] Pos[2]
tag @e[type=minecraft:marker,tag=numcraft.new] remove numcraft.new
# a marker acts only in a loaded chunk, and an arrival point must be loaded
forceload add ~ ~
$data modify storage numcraft:portal pairs.$(name).$(end) set from storage numcraft:portal new
return 1

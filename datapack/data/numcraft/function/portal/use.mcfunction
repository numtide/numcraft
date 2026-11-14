# As the traveller, at the marker of a portal end.
data remove storage numcraft:portal use
data modify storage numcraft:portal use set from entity @e[type=minecraft:marker,tag=numcraft.portal,distance=..0.1,limit=1,sort=nearest] data
execute unless data storage numcraft:portal use.name run return fail
return run function numcraft:portal/use_pair with storage numcraft:portal use

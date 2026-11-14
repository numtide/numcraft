data remove storage numcraft:portal dest
$data modify storage numcraft:portal dest set from storage numcraft:portal pairs.$(name).$(other)
execute unless data storage numcraft:portal dest.dim run return fail
# The traveller arrives on the other end. The tag stops a trip back until the
# traveller steps off; the cooldown covers an arrival before the marker loads.
scoreboard players set @s numcraft.cooldown 20
tag @s add numcraft.on_portal
# Each portal that crosses the border of the lab uses the same entry and exit
# as the lab portal, and does not move a traveller that they refuse.
execute if data storage numcraft:portal dest{dim:"numcraft:lab"} run function numcraft:lab/enter
execute if data storage numcraft:portal dest{dim:"numcraft:lab"} unless entity @s[tag=numcraft.in_lab] run return fail
execute unless data storage numcraft:portal dest{dim:"numcraft:lab"} run function numcraft:lab/leave
execute unless data storage numcraft:portal dest{dim:"numcraft:lab"} if entity @s[tag=numcraft.in_lab] run return fail
function numcraft:portal/tp with storage numcraft:portal dest
return 1

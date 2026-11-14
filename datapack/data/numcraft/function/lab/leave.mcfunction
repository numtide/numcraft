execute unless entity @s[tag=numcraft.in_lab] run return 1
execute store result storage numcraft:lab args.x int 1 run scoreboard players get @s numcraft.id
function numcraft:lab/vault_check with storage numcraft:lab args
# no vault, no wipe: the traveller keeps the tag, and the next tick tries again
execute unless score #ready numcraft.var matches 1 run return fail
function numcraft:lab/wipe
function numcraft:lab/restore with storage numcraft:lab args
execute store result storage numcraft:lab args.levels int 1 run scoreboard players get @s numcraft.xp_levels
execute store result storage numcraft:lab args.points int 1 run scoreboard players get @s numcraft.xp_points
function numcraft:lab/restore_xp with storage numcraft:lab args
function numcraft:lab/vault_empty with storage numcraft:lab args
effect clear @s
gamemode survival @s
tag @s remove numcraft.in_lab
return 1

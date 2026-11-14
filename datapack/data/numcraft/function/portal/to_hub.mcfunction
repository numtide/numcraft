scoreboard players set @s numcraft.cooldown 100
function numcraft:lab/leave
execute if entity @s[tag=numcraft.in_lab] run return fail
function numcraft:portal/tp_hub with storage numcraft:portal hub

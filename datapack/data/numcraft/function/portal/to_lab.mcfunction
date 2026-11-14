# the cooldown stops a loop: the traveller arrives next to the return portal
scoreboard players set @s numcraft.cooldown 100
function numcraft:lab/enter
execute unless entity @s[tag=numcraft.in_lab] run return fail
execute in numcraft:lab run tp @s 0.5 -60 0.5

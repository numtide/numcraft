function numcraft:lab/state_sync
execute unless score @s numcraft.plot matches 0.. run return fail
function numcraft:lab/enter
execute unless entity @s[tag=numcraft.in_lab] run return fail
function numcraft:lab/plot_args
function numcraft:lab/plot_tp with storage numcraft:lab plot
return 1

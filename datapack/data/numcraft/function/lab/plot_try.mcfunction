# As the owner of a plot that has no marks yet.
function numcraft:lab/plot_args
scoreboard players set #loaded numcraft.var 0
function numcraft:lab/plot_loaded with storage numcraft:lab plot
execute unless score #loaded numcraft.var matches 1 run return fail
# The name of a player is in no entity data. A player head made for the
# owner has it; an owner that is not a player keeps the "?".
data modify storage numcraft:lab plot.owner set value "?"
function numcraft:lab/plot_owner with storage numcraft:lab plot
function numcraft:lab/plot_mark with storage numcraft:lab plot
tag @s remove numcraft.plot_pending
return 1

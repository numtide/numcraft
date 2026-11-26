# Gives the caller the next free plot, or goes to the plot that the caller has.
function numcraft:lab/state_sync
execute if score @s numcraft.plot matches 0.. run return run function numcraft:lab/home
function numcraft:lab/enter
execute unless entity @s[tag=numcraft.in_lab] run return fail
execute unless score #next_plot numcraft.var matches 0.. run scoreboard players set #next_plot numcraft.var 0
scoreboard players operation @s numcraft.plot = #next_plot numcraft.var
scoreboard players add #next_plot numcraft.var 1
function numcraft:lab/state_save
# the corners are marked when the chunks of the plot are loaded
tag @s add numcraft.plot_pending
function numcraft:lab/plot_args
function numcraft:lab/plot_tp with storage numcraft:lab plot
return 1

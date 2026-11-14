# Plots are 32 by 32 on a grid of 40, eight in a row, so paths of 8 blocks
# stay between them. Plot 0 has its low corner at 48 32, clear of the arrival.
scoreboard players operation #x numcraft.var = @s numcraft.plot
scoreboard players operation #x numcraft.var %= #8 numcraft.var
scoreboard players operation #x numcraft.var *= #40 numcraft.var
scoreboard players add #x numcraft.var 48
scoreboard players operation #z numcraft.var = @s numcraft.plot
scoreboard players operation #z numcraft.var /= #8 numcraft.var
scoreboard players operation #z numcraft.var *= #40 numcraft.var
scoreboard players add #z numcraft.var 32
execute store result storage numcraft:lab plot.x int 1 run scoreboard players get #x numcraft.var
execute store result storage numcraft:lab plot.z int 1 run scoreboard players get #z numcraft.var
scoreboard players add #x numcraft.var 16
scoreboard players add #z numcraft.var 16
execute store result storage numcraft:lab plot.cx int 1 run scoreboard players get #x numcraft.var
execute store result storage numcraft:lab plot.cz int 1 run scoreboard players get #z numcraft.var
scoreboard players add #x numcraft.var 15
scoreboard players add #z numcraft.var 15
execute store result storage numcraft:lab plot.x2 int 1 run scoreboard players get #x numcraft.var
execute store result storage numcraft:lab plot.z2 int 1 run scoreboard players get #z numcraft.var

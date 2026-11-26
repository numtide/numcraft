$execute unless data storage numcraft:lab players[{uuid:$(uuid)}] run data modify storage numcraft:lab players append value {uuid:$(uuid)}
$execute if score @s numcraft.id matches 0.. store result storage numcraft:lab players[{uuid:$(uuid)}].id int 1 run scoreboard players get @s numcraft.id
$execute if score @s numcraft.plot matches 0.. store result storage numcraft:lab players[{uuid:$(uuid)}].plot int 1 run scoreboard players get @s numcraft.plot
$execute if score @s numcraft.xp_levels matches 0.. store result storage numcraft:lab players[{uuid:$(uuid)}].xp_levels int 1 run scoreboard players get @s numcraft.xp_levels
$execute if score @s numcraft.xp_points matches 0.. store result storage numcraft:lab players[{uuid:$(uuid)}].xp_points int 1 run scoreboard players get @s numcraft.xp_points

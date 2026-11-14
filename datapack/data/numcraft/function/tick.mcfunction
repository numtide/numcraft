scoreboard players remove @a[scores={numcraft.cooldown=1..}] numcraft.cooldown 1
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_lab,distance=..1.5] run function numcraft:portal/to_lab
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_hub,distance=..1.5] run function numcraft:portal/to_hub

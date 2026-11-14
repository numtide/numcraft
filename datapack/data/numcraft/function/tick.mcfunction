scoreboard players remove @a[scores={numcraft.cooldown=1..}] numcraft.cooldown 1
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_lab,distance=..1.5] run function numcraft:portal/to_lab
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_hub,distance=..1.5] run function numcraft:portal/to_hub
# Every way out of the lab that is not the portal ends here: death and
# respawn, a teleport, a portal block. And every way in.
execute as @a[tag=numcraft.in_lab] at @s unless dimension numcraft:lab run function numcraft:lab/leave
execute as @a[tag=!numcraft.in_lab] at @s if dimension numcraft:lab run function numcraft:lab/enter
execute as @a[tag=numcraft.in_lab] at @s if dimension numcraft:lab run function numcraft:lab/no_portals

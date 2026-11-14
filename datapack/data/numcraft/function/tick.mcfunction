scoreboard players remove @a[scores={numcraft.cooldown=1..}] numcraft.cooldown 1
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_lab,distance=..1.5] run function numcraft:portal/to_lab
execute as @a at @s unless score @s numcraft.cooldown matches 1.. if entity @e[type=minecraft:marker,tag=numcraft.to_hub,distance=..1.5] run function numcraft:portal/to_hub
# Every way out of the lab that is not the portal ends here: death and
# respawn, a teleport, a portal block. And every way in.
execute as @a[tag=numcraft.in_lab] at @s unless dimension numcraft:lab run function numcraft:lab/leave
execute as @a[tag=!numcraft.in_lab] at @s if dimension numcraft:lab run function numcraft:lab/enter
execute as @a[tag=numcraft.in_lab] at @s if dimension numcraft:lab run function numcraft:lab/no_portals
# Named portals. The tag goes when the traveller is off each portal end.
execute as @a[tag=numcraft.on_portal] at @s unless entity @e[type=minecraft:marker,tag=numcraft.portal,distance=..2.5] run tag @s remove numcraft.on_portal
execute as @a[tag=!numcraft.on_portal] at @s unless score @s numcraft.cooldown matches 1.. at @e[type=minecraft:marker,tag=numcraft.portal,distance=..1.5,limit=1,sort=nearest] run function numcraft:portal/use
# /trigger works for a player who is not an operator
scoreboard players enable @a numcraft.claim
scoreboard players enable @a numcraft.home
execute as @a[scores={numcraft.claim=1..}] at @s run function numcraft:lab/claim
execute as @a[scores={numcraft.home=1..}] at @s run function numcraft:lab/home
scoreboard players set @a[scores={numcraft.claim=1..}] numcraft.claim 0
scoreboard players set @a[scores={numcraft.home=1..}] numcraft.home 0
execute as @a[tag=numcraft.plot_pending] run function numcraft:lab/plot_try

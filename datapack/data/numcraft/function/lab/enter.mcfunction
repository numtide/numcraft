# The tag numcraft.in_lab means: the vault holds the survival state of @s.
# The tag is set only after the save is verified, and nothing is wiped before
# the tag is set.
execute if entity @s[tag=numcraft.in_lab] run return 1
execute unless score @s numcraft.id matches 0.. run function numcraft:lab/allocate
execute store result storage numcraft:lab args.x int 1 run scoreboard players get @s numcraft.id
function numcraft:lab/vault_prepare with storage numcraft:lab args
function numcraft:lab/vault_check with storage numcraft:lab args
# a vault with items and no tag is a state that only an operator can judge
function numcraft:lab/vault_must_be_empty with storage numcraft:lab args
execute unless score #ready numcraft.var matches 1 run return fail
execute store result score @s numcraft.xp_levels run xp query @s levels
execute store result score @s numcraft.xp_points run xp query @s points
function numcraft:lab/save with storage numcraft:lab args
scoreboard players set #bad numcraft.var 0
function numcraft:lab/verify with storage numcraft:lab args
execute if score #bad numcraft.var matches 1 run function numcraft:lab/vault_empty with storage numcraft:lab args
execute if score #bad numcraft.var matches 1 run return fail
tag @s add numcraft.in_lab
function numcraft:lab/wipe
gamemode creative @s
return 1

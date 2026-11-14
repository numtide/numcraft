$execute in numcraft:lab run summon minecraft:item_display $(cx) -55 $(cz) {Tags:["numcraft.head"]}
execute in numcraft:lab run loot replace entity @e[type=minecraft:item_display,tag=numcraft.head,distance=0..] contents loot {pools:[{rolls:1,entries:[{type:"minecraft:item",name:"minecraft:player_head",functions:[{function:"minecraft:fill_player_head",entity:"this"}]}]}]}
execute in numcraft:lab run data modify storage numcraft:lab plot.owner set from entity @e[type=minecraft:item_display,tag=numcraft.head,distance=0..,limit=1] item.components."minecraft:profile".name
execute in numcraft:lab run kill @e[type=minecraft:item_display,tag=numcraft.head,distance=0..]

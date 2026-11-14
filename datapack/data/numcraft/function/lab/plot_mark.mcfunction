$execute in numcraft:lab run fill $(x) -61 $(z) $(x2) -61 $(z) minecraft:white_concrete
$execute in numcraft:lab run fill $(x) -61 $(z2) $(x2) -61 $(z2) minecraft:white_concrete
$execute in numcraft:lab run fill $(x) -61 $(z) $(x) -61 $(z2) minecraft:white_concrete
$execute in numcraft:lab run fill $(x2) -61 $(z) $(x2) -61 $(z2) minecraft:white_concrete
$execute in numcraft:lab run setblock $(x) -60 $(z) minecraft:sea_lantern
$execute in numcraft:lab run setblock $(x2) -60 $(z) minecraft:sea_lantern
$execute in numcraft:lab run setblock $(x) -60 $(z2) minecraft:sea_lantern
$execute in numcraft:lab run setblock $(x2) -60 $(z2) minecraft:sea_lantern
$execute in numcraft:lab positioned $(cx) -56 $(cz) run kill @e[type=minecraft:text_display,tag=numcraft.plot_label,distance=..1]
$execute in numcraft:lab run summon minecraft:text_display $(cx) -56 $(cz) {billboard:"vertical",Tags:["numcraft.plot_label"],text:"$(owner)"}

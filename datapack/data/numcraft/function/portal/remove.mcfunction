# The chunks of the two ends stay force-loaded: another portal can share them.
$kill @e[type=minecraft:marker,tag=numcraft.portal,nbt={data:{name:"$(name)"}}]
$data remove storage numcraft:portal pairs.$(name)

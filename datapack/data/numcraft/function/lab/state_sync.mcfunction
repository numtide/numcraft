# A score belongs to a name, and a player can change the name. The storage
# holds the same values by UUID, and it wins when it has them.
data modify storage numcraft:lab state.uuid set from entity @s UUID
function numcraft:lab/state_load with storage numcraft:lab state
function numcraft:lab/state_store with storage numcraft:lab state

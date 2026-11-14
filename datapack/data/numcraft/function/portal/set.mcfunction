# Run at the position of a portal end, two times for one name:
#   execute in <dimension> positioned <x> <y> <z> run function numcraft:portal/set {name:"mine"}
# The first call sets end a. Each later call sets end b again.
$execute unless data storage numcraft:portal pairs.$(name).a run return run function numcraft:portal/set_end {name:"$(name)",end:"a",other:"b"}
$function numcraft:portal/set_end {name:"$(name)",end:"b",other:"a"}

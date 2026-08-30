# ECS Manager
---
### TODO
- fix why does it take a try to deinit an ECS manager. zig philosophy says deinit can never fail
- Add an iterator method to the ECS
	- right now its all GetGroup which gets an array of entity IDs and then you work with the entity IDs
	- what if there was a like GetIterator where the type of object in the iterator was generated at compile time using the comptime parameters and then you can do direct access instead of always having to do a get component? 
	- inspired by https://codeberg.org/Games-by-Mason/mr_ecs
	- instead you can do while(iter.next()) |entity| {} (normal zig syntax) but lets say you did a query where you get all the transform and rigid body components, then you can do entity.Transform,(blahblah) to directly access the transform component?
- make it so tag components have zeros size instead of the 1 bit they occupy right now
	- this can be done at init by checking to see the size of the component type. if the size is 0 then make a sparse set which has not "value" array. then getting the component is illegal but you can do everything else
- add a version of sparse sets that are paged instead of just flat array like it is right now. then change component types so that they have to provide another parameter for the ECS when they are added to the ECS which says whether the ECS should use contiguous sparse sets or paged sparse sets
### Resources to look at
https://github.com/abeimler/ecs_benchmark

### Related 
[[Adding new components to engine]] 
[[Adding new scripts to engine]] 

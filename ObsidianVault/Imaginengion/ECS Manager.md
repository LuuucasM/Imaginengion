# ECS Manager
---
### TODO
- change entity IDs to split the 32 bits into 16 and 16 bits where the bottom half is the generation and the top half is the object ID
- add a version of sparse sets that are paged instead of just flat array like it is right now. then change component types so that they have to provide another parameter for the ECS when they are added to the ECS which says whether the ECS should use contiguous sparse sets or paged sparse sets
[[Adding new components to engine]] 
[[Adding new scripts to engine]] 

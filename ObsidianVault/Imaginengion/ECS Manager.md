# ECS Manager
---
### TODO
- try and move the scripts into the ECS where you pass a script list like a component list
- change entity IDs to split the 32 bits into 16 and 16 bits where the bottom half is the generation and the top half is the object ID
- change sparse set to use pages instead of just raw array using IDs. split the entity id (now 16bit) into 2 parts 8 and 8 bits. use the bottom 8 bits for page number and use the top 8 bits for the entity ID
- change components so that they have to provide another parameter for the ECS when they are added to the ECS which says whether the ECS should use contiguous sparse sets or paged sparse sets
- change name component so it uses a dynamic array that way user can name however big or small they want. note: this is for editor purpose. for compiling the game to an executable, i dont think a name is even needed, but also if it really is then it can be made using array using meta programming
### Other Related Topics
[[Adding new components to engine]] 
[[Adding new scripts to engine]] 

# ECS Manager
---
### Design Choices
- 
### Member Variables
- [[Entity Manager]]
- [[Component Manager]]
- Allocator
### Public Functions
- Init - Used to initialize the ECS
- Deinit - Used To deinitialize the ECS
- CreateEntity - Use to create an entity, which for the purpose of the ECS is simply an integer
- DestroyEntity - Marks an entity to be destroyed
- ProcessDestroyedEntities - Remove all of the components of the entity and release the identifier 
- GetAllEntities - Gets all the entities in the ECS
- DuplicateEntities - Creates a
- GetGroup
- EntityListDifference
- EntityListUnion
- EntityListIntersection
- AddComponent
- RemoveComponent
- HasComponent
- GetComponent
### Private Functions
- None
### Other Related Topics
[[Adding new components to engine]] 
[[Adding new scripts to engine]] 

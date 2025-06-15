- When using ray marching has a complexity of O(number of rays * number of steps * number of shapes)
- It is also worth considering the parameters MAX_STEPS, SURF_DIST and MAX_DIST to optimize as well
	- for surf_dist, for example as the object gets further away it does not need to retain 100% of its quality and therefore we can increase the SURF_DIST threshold up to something like 0.1 or even 0.5 
	- for max_dist, realistically the max_dist can just be some distance at the very end, or just past (if its easier to calculate) for the further BVH node we are traversing
	- for max_steps, im a bit torn on this one because if the loop terminates early from max_steps then that means either we didnt hit the max distance (and therefore are still in screen space) or we didnt actually hit an object yet. it feels like if we hit max_steps its actually just a failure that should never happen. but i suppose its necessary just incase some edge case but if its possible to guarentee that we either exit the max distance or hit an object that would be much better. and maybe we can when we are dealing with bvh's since the scope of shapes we are considering will be much smaller
- for a 1920x1080 scene there are 2,073,600 rays alone. then multiply by number of steps and multiply by number of shapes being tested and suddenly 
	- Total Evaluations = Rays × Steps × Shapes
	- T=2, ⁣073, ⁣600×100×ShapesT = 2,073,600 * 100 * Shapes
	- T=2,073,600×100×Shapes
	Now let's vary the number of shapes:

| Number of Shapes | Total Evaluations (approx) |
| ---------------- | -------------------------- |
| 1                | 207,360,000                |
| 2                | 414,720,000                |
| 5                | 1,036,800,000              |
| 10               | 2,073,600,000              |
| 20               | 4,147,200,000              |
| 50               | 10,368,000,000             |
| 100              | 20,736,000,000             |
| 200              | 41,472,000,000             |
| 500              | 103,680,000,000            |
| 1000             | 207,360,000,000            |
- so when trying to optimize to make rendering faster i need to decrease either the number of rays, the number of steps, or the number of shapes
- when doing alpha blending, probably implement alpha blending from front to back
- this goes with ray marching because since we are pruning objects that are not directly in the rays path, and then we will march to the first closest object, so at that point we can look at the alpha values, and if we hit another object then we can blend, and continue until our accumulated alpha is hit 1 or we hit the background

### what i dont understand yet to research
- Need more information on morton curve
### Optimize Number of Rays
- not sure yet
### Optimize Number of Steps
- current stepping techniques allow us to step only as far as the closest is away  from us
- but isnt the only issue that we dont want to step PAST an object? so could we step as far as long as we dont pass through the object so if we know the volume for an object we can step as far as the distance to the object + its volume?
- im not sure yet but i feel like theres opportunity to be more greedy with the number of steps, maybe in specific situations
- also sometimes the closest object to the ray isnt even along the path of a ray, but im wondering if this can be mended some by BVH like if we shoot a ray we can check where in the BVH sub tree we are and only test the distance to the leaf nodes (the actual objects) that are at the end of the current sub branch instead of chekcing the entire screen
- this prevents situations where like if scene shapes run parallel to the ray but actually never intersect then they are just slowing it down by only letting the ray travel the disntance from the point to the paralell object. 
- so wouldnt the calculation become something like {# of rays in the scene} * {number of leaf nodes we trace through} * {number of nodes we trace through}
- additionally finding the leaf nodes we trace through shouldn't take too much time, even in an incredibly full scene each leaf node would be like O(the number of shapes we pierce through * log(# shapes included in the scene))
- SOUNDS GOOD TO ME?

### Optimize Number of Shapes
- Frustum culling
	- use a spatial data structure like BVH
	- these data structures can, effectively split themselves down 
	- so that the runtime of finding which objects to include in the scene is reduced to an O(logn) time search rather than O(n) because its a tree data structure and we can cut or include entire  parts of the tree saving lots of time
	- construction strategy: use Linear BVH(LBVH) as the construction strategy. 
		- This provides a less accurate bvh but is noted as a good starting point in combining with other strategies. 
		- I am particularly drawn to this strategy because it uses the Morton curve, which we need for our sorting strategy so after our discovery iteration, we can use the same morton number for both sorting and constructing the BVH.
		- infact i would even guess that sorting shapes by morton curve and constructing a bvh probably have something in common
- occlusion culling
- something pruning...? i forget what its called

### physics
- physics goooooood
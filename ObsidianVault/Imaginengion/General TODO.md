- change the like initialization of the engine. I think for things that dont need allocations or run time setup like opengl, glfw, etc they can be initialized straight from the beginning. Like most of the imgui panels just have a bool that can easily be set with a default value which means that the panel in EditorProgram can also be set with a default value, which means that Program in application can also be set with a default value. Maybe this can solve some of the issues where like something needs reference of something else but its not initialized yet.. maybe not tho idk
- extend scenes to also utilize the script system where scripts will be called on scene start. this means changing the scenes into entities with its own ECS and then changing everything to follow suit. Additionally I want to add a new SceneInfoPanel where the user can double click on a scene in the ScenePanel and it will open up another panel where you can add scripts and stuff to the scene. This will make scenes fully extendable and give devs full control over their game
- have scenes generate at least 1 player on game startup
- using the new scene-script system now devs can write game logic where they can tell the scene where to assign 
- finish up adding the primary camera by filling in the editor render function for camera and then implementing the event function the SetPrimaryCameraEvent and camera component imgui render.
- does alt + f4 work natively with every program or does it need to be implemented?
- make a new window when they hit the play button that shows the game from the primary camera POV 
- at this point i should be able to give things textures and scripts and have them move around when hitting the play button (with no animations or anything just moving around)
- get the newest updated versions of zig set and zig sparse set from git
- nothing gets released ever for assethandlerefs lol
- go over all the files looking for places to optimize. make sure to minimizes things like hashes, jumps (if statement loops etc), make sure things look clean and logical
- make animation system
- go over all the files looking for places to optimize. make sure to minimizes things like hashes, jumps (if statement loops etc), make sure things look clean and logical
- Make main menu for vampire survivors 
- go over all the files looking for places to optimize. make sure to minimizes things like hashes, jumps (if statement loops etc), make sure things look clean and logical
- write physics and collision system
- go over all the files looking for places to optimize. make sure to minimizes things like hashes, jumps (if statement loops etc), make sure things look clean and logical
- add a way to export the game into its standalone
- go over all the files looking for places to optimize. make sure to minimizes things like hashes, jumps (if statement loops etc), make sure things look clean and logical
- make it so u cant make scenes or anything until you have a project selected first
- Give an editor option that is a viewport which is what you see from the in game perspective like from the set primary camera. And when you hit "play" for the scene instead of getting rid of changing the main viewport you just save and play and then in the secondary viewport you do the same that way you can get the editor POV during testing. But it needs to be an option because not all computers can handle literally double the rendering
- Editor settings file
- Add localization for Korean
- add profiling via Tracy (or if all else fails hand roll something)
- review files to add possible unit tests and asserts
- start making vampire survivors but using Pokémon sprites so like a little fan made Pokémon game
- add in reinforcement learning to the ECS for sorting components lists
- Make a git page website
- i don't ever delete dynamic libraries and maybe i shouldn't but i should probably sort them into their own folder so it doesn't clutter the zig-out/bin folder
- add a way to calculate constants e.g. how many total entities a scene could have. or stuff like that. This way when creating the game executable we can initialize everything at the right capacities and what not to hyper optimize game performance
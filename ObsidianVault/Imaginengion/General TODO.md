- for the asset manager split mAssetPathToID into 3 one for each path type (Eng, Prj, Abs)
	- this way i can store assets using their relative paths directly and i dont necessarily need to grab the abs path until its 100% necessary
- ive got it. so i will have what i have so far with the player manager and stuff. basically in the editor in the toolbar panel where the play button is there will be a drop down where you can choose WHERE you want to start when u hit the play button. then when building the game into a final executable you will just manually set starting scene(s) and through the script you should be able to posses on scene start
	- i also have the idea of having each object OR each player with its own frame buffer? since rendering and POV is based on the object being controlled the camera attached to that object. with the object thing this means we only have to render from the objects who is being possesed and also we can share that same pov across multiple screens if needed. but also this shares a problem with each player having its own frame buffer in that if you are doing a splitscreen/multiplayer where all the players share the same POV then theres no need for a "split" in the screen. but maybe if i do it the way like where the frame buffer is on the object, its possible that since we dont ever render from a camera we are not using its ok and programatically we can decide HOW to draw it?
	- the only thing thats bad about this is if you want the test the game from the very beginning you will have to load only those scenes, and then you have to do the things to set it up properly like putting the right scene(s) and then starting hitting play with the selected place to spawn
	- maybe in the future i can introduce like saved editor states where you can like hotkey or save specific scene setups so you can use later?
- split these mega shaders into smaller shaders so like a .vert and .frag instead of one big .glsl that we parse through
- add a function to scene_layer to "spawn player" which is an entity which has a component like PlayerComponent which contains the data related to the player. 
- then i can for example on scene_layer.OnSceneStart I can spawn a player -> then somehow take control of an entity with a controller component, and then 
- Then in scene scripts like OnSceneStart you can spawn a player and then set that players "ToControlEntity" to a specified entity
- fix bug where if you minimize it crashes because imgui begin/end children dont match
- does alt + f4 work natively with every program or does it need to be implemented?
- at this point i should be able to give things textures and scripts and have them move around when hitting the play button (with no animations or anything just moving around)
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
- have some sort of system for managing "players"
- im thinking about a system where like we have a player controller object that we make.
	- the controller object it contains stuff like input scripts and whatever else that the human player uses to interact with the in game object
	- then when we assign a player to an object its attached scripts / components are copied onto the said object. then when we remove controller or unposses we remove those scripts and components
	- good things: 
		- This basically makes player controllers like a controller profile that can be reused across objects which is good for like multiplayer when you have multiple people controlling characters that all share the same basic buttons and stuff
	- bad things:
		- this works less well with when a player takes control of another object because other objects will (might / likely) have a different control scheme so then id need to make a system just to handle this case
		- it would require difficult logic to be able to copy component/scripts and then keep track of them so we can remove them when the unposession happens
		- also this way might be not very performant as adding  scripts/components and removing them dynamically is less optimal and it would be good to avoid when possible 
- so now im going back to thinking about how an object has its own input script and its own input logic, and instead the player.
	- so a player controller is just an object that might contain some metadata but the entity its self doesnt really contain much else.
	- 

NOTE:
- I am realizing now why some game engines have you map actions to actions for inputs instead of directly using keys. like the move forward action on a player activates the move forward action on a car, and then the key being determined by the players hotkey profile. this is a change for later but i am now understanding why
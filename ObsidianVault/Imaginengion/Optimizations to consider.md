- making children transforms have smaller x y z values
	- since a childs transform is just the object relative to its parent it likely doesnt need to have a transform of millions can you can likely get away with having it be u8 or u16 which can improve cache efficiency by 4x  or 2x AND reduce memory
	- 
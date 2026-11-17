//! What a texture atlas handle says: the layer of the atlas's texture array a texture is in, where its slot starts in
//! that layer, in cells of CELL pixels (every slot starts on a cell), and its size class, the slot's size. The shaders
//! read the first two to find a texture (GetTextureUV); the class is only for giving the slot back. Kept apart from
//! the allocator (AtlasSlots), which is CPU only, so the shaders build only this.
const AtlasHandle = @This();

/// A layer of the texture array is ATLAS_SIZE by ATLAS_SIZE
pub const ATLAS_SIZE: u32 = 4096;
/// The smallest slot, and the grid every slot starts on
pub const CELL: u32 = 64;
/// Cells across a layer
pub const CELLS: u32 = ATLAS_SIZE / CELL;
/// Pixels left around a texture inside its slot, so sampling at its edge never reads its neighbour's
pub const PADDING: u32 = 2;
/// Size classes: slots of 64, 128, 256, 512, 1024, 2048 and 4096 pixels
pub const CLASS_COUNT = 7;

const CLASS_BITS = 3;
const CELL_BITS = 6;
const LAYER_BITS = 10;
/// More than the atlas ever has
pub const MAX_LAYERS: u32 = 1 << LAYER_BITS;

pub fn Make(layer: u32, cell_x: u32, cell_y: u32, class: u32) u32 {
    return class | (cell_x << CLASS_BITS) | (cell_y << (CLASS_BITS + CELL_BITS)) | (layer << (CLASS_BITS + 2 * CELL_BITS));
}

pub fn Class(handle: u32) u32 {
    return handle & ((1 << CLASS_BITS) - 1);
}

pub fn CellX(handle: u32) u32 {
    return (handle >> CLASS_BITS) & ((1 << CELL_BITS) - 1);
}

pub fn CellY(handle: u32) u32 {
    return (handle >> (CLASS_BITS + CELL_BITS)) & ((1 << CELL_BITS) - 1);
}

pub fn Layer(handle: u32) u32 {
    return (handle >> (CLASS_BITS + 2 * CELL_BITS)) & ((1 << LAYER_BITS) - 1);
}

/// The pixel in its layer where the texture starts, inside its slot's padding
pub fn PixelX(handle: u32) u32 {
    return CellX(handle) * CELL + PADDING;
}

pub fn PixelY(handle: u32) u32 {
    return CellY(handle) * CELL + PADDING;
}

/// How many pixels across a slot of `class` is
pub fn SlotSize(class: u32) u32 {
    return CELL << @intCast(class);
}

/// The biggest texture a slot of `class` takes, either way
pub fn MaxTextureSize(class: u32) u32 {
    return SlotSize(class) - 2 * PADDING;
}

/// The smallest class whose slot takes a texture this big, null for one bigger than a whole layer takes
pub fn ClassOf(width: usize, height: usize) ?u32 {
    const biggest = @max(width, height);
    var class: u32 = 0;
    while (class < CLASS_COUNT) : (class += 1) {
        if (biggest <= MaxTextureSize(class)) return class;
    }
    return null;
}

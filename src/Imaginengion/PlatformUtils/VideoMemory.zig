//! What the GPU driver says the application holds, as Windows' video memory manager counts it (DXGI's
//! QueryVideoMemoryInfo), whatever API made it: everything GPUAllocator counts, plus what it can't see, the swapchain's
//! images, pipelines and shaders, and the driver's own. So the gap between the two is what the engine doesn't make by
//! hand. Windows only, through DXGI's COM interfaces: Read gives null elsewhere, or if DXGI can't be reached.
//! SDL doesn't say which adapter it picked, so the one this process uses the most video memory on is taken as it.
const std = @import("std");
const builtin = @import("builtin");

const VideoMemory = @This();

/// What Read gives
pub const Usage = struct {
    /// the GPU's own memory this process holds, on the adapter it uses most
    Used: u64,
    /// how much of it Windows will let the process have before it starts moving its memory out
    Budget: u64,
    /// system memory the GPU reads through, held by this process ("non-local", "shared GPU memory")
    Shared: u64,
};

const MAX_ADAPTERS = 8;

/// Found the first time it is read
mAdapters: [MAX_ADAPTERS]*IDXGIAdapter3 = undefined,
mAdapterCount: usize = 0,
mTried: bool = false,

/// The application's video memory now. Main thread
pub fn Read(self: *VideoMemory) ?Usage {
    if (builtin.os.tag != .windows) return null;
    if (!self.mTried) {
        self.mTried = true;
        self.FindAdapters();
    }
    var best: ?Usage = null;
    for (self.mAdapters[0..self.mAdapterCount]) |adapter| {
        var local: VideoMemoryInfo = undefined;
        var non_local: VideoMemoryInfo = undefined;
        if (adapter.vtable.QueryVideoMemoryInfo(adapter, 0, .Local, &local) < 0) continue;
        if (adapter.vtable.QueryVideoMemoryInfo(adapter, 0, .NonLocal, &non_local) < 0) continue;
        if (best == null or local.CurrentUsage > best.?.Used) {
            best = .{ .Used = local.CurrentUsage, .Budget = local.Budget, .Shared = non_local.CurrentUsage };
        }
    }
    return best;
}

pub fn Deinit(self: *VideoMemory) void {
    for (self.mAdapters[0..self.mAdapterCount]) |adapter| _ = adapter.vtable.Release(adapter);
    self.mAdapterCount = 0;
}

fn FindAdapters(self: *VideoMemory) void {
    var factory: *IDXGIFactory1 = undefined;
    if (CreateDXGIFactory1(&IID_IDXGIFactory1, @ptrCast(&factory)) < 0) {
        std.log.warn("The driver's count of video memory can't be read: DXGI didn't start", .{});
        return;
    }
    defer _ = factory.vtable.Release(factory);
    var index: u32 = 0;
    while (self.mAdapterCount < MAX_ADAPTERS) : (index += 1) {
        var adapter: *IDXGIAdapter1 = undefined;
        if (factory.vtable.EnumAdapters1(factory, index, &adapter) < 0) break;
        defer _ = adapter.vtable.Release(adapter);
        //QueryVideoMemoryInfo came with IDXGIAdapter3, in Windows 10
        var adapter3: *IDXGIAdapter3 = undefined;
        if (adapter.vtable.QueryInterface(adapter, &IID_IDXGIAdapter3, @ptrCast(&adapter3)) < 0) continue;
        self.mAdapters[self.mAdapterCount] = adapter3;
        self.mAdapterCount += 1;
    }
}

// DXGI's COM interfaces, as much of them as is used: each vtable in the order its header declares it

const HRESULT = i32;
const GUID = extern struct { Data1: u32, Data2: u16, Data3: u16, Data4: [8]u8 };
const IID_IDXGIFactory1 = GUID{ .Data1 = 0x770aae78, .Data2 = 0xf26f, .Data3 = 0x4dba, .Data4 = .{ 0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87 } };
const IID_IDXGIAdapter3 = GUID{ .Data1 = 0x645967a4, .Data2 = 0x1392, .Data3 = 0x4310, .Data4 = .{ 0xa7, 0x98, 0x80, 0x53, 0xce, 0x3e, 0x93, 0xfd } };

const MemorySegmentGroup = enum(u32) { Local = 0, NonLocal = 1 };
const VideoMemoryInfo = extern struct {
    Budget: u64,
    CurrentUsage: u64,
    AvailableForReservation: u64,
    CurrentReservation: u64,
};

const Unused = *const anyopaque;

const IDXGIFactory1 = extern struct {
    vtable: *const extern struct {
        //IUnknown
        QueryInterface: Unused,
        AddRef: Unused,
        Release: *const fn (*IDXGIFactory1) callconv(.winapi) u32,
        //IDXGIObject
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: Unused,
        //IDXGIFactory
        EnumAdapters: Unused,
        MakeWindowAssociation: Unused,
        GetWindowAssociation: Unused,
        CreateSwapChain: Unused,
        CreateSoftwareAdapter: Unused,
        //IDXGIFactory1
        EnumAdapters1: *const fn (*IDXGIFactory1, u32, **IDXGIAdapter1) callconv(.winapi) HRESULT,
        IsCurrent: Unused,
    },
};

const IDXGIAdapter1 = extern struct {
    vtable: *const extern struct {
        QueryInterface: *const fn (*IDXGIAdapter1, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: Unused,
        Release: *const fn (*IDXGIAdapter1) callconv(.winapi) u32,
    },
};

const IDXGIAdapter3 = extern struct {
    vtable: *const extern struct {
        //IUnknown
        QueryInterface: Unused,
        AddRef: Unused,
        Release: *const fn (*IDXGIAdapter3) callconv(.winapi) u32,
        //IDXGIObject
        SetPrivateData: Unused,
        SetPrivateDataInterface: Unused,
        GetPrivateData: Unused,
        GetParent: Unused,
        //IDXGIAdapter
        EnumOutputs: Unused,
        GetDesc: Unused,
        CheckInterfaceSupport: Unused,
        //IDXGIAdapter1
        GetDesc1: Unused,
        //IDXGIAdapter2
        GetDesc2: Unused,
        //IDXGIAdapter3
        RegisterHardwareContentProtectionTeardownStatusEvent: Unused,
        UnregisterHardwareContentProtectionTeardownStatus: Unused,
        QueryVideoMemoryInfo: *const fn (*IDXGIAdapter3, u32, MemorySegmentGroup, *VideoMemoryInfo) callconv(.winapi) HRESULT,
    },
};

extern "dxgi" fn CreateDXGIFactory1(riid: *const GUID, factory: **anyopaque) callconv(.winapi) HRESULT;

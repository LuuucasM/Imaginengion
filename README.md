# Imaginengion

### My take on a high-performance game engine designed to leverage emerging technologies with a strong focus on modern hardware optimization.

## Table of Contents
1. [Introduction](#introduction)
2. [Compatibility](#comp)
3. [Installation](#inst)
4. [How To Use](#howtouse)
5. [AI Usage](#aiusage)

## Introduction <a name="introduction"></a>

Imaginengion is my take on building a game engine. It is partly a playground for experimenting with ideas, but I still spend a lot of time thinking about long-term design decisions and performance.

The renderer is a signed-distance-field renderer. The ECS and event system are built from scratch. Physics is also written by hand, not because I necessarily wanted to, but because I could not find an existing physics library that worked the way I wanted. Audio support is fairly bare-bones right now, but I hope to create some kind of ray-traced audio system in the future.

Several engine systems rely on two main patterns: ECSs and Event Managers. One major difference is that in my ECS, the "S" stands for *Scripts* rather than *Systems*. The engine provides different points in the main update loop where scripts can hook in, giving you the freedom to make objects behave however you want without needing to add systems directly to the engine.

Because of the way the engine is designed, creating complete game objects can currently be quite verbose. One day, I would like to build a layer on top of the base engine that provides convenience features and assets to make things easier to work with.

It is definitely an ambitious project, but I hope I can make games with it one day ^_^

## Compatibility <a name="comp"></a>

##### Compiler Version
- Currently using a recent Zig compiler version (0.17.x)

##### OS
- Windows 10 64-bit (build 1903+) or newer

##### CPU
- x86-64 with SSE4.2 support

##### GPU
- A graphics card supporting DirectX 12 Feature Level 11_0 and Resource Binding Tier 2

##### RAM
- 1 GB

##### VRAM
- 1 GB

## Installation <a name="inst"></a>

1. Download and extract this repository into a folder.
2. Download the correct version of the Zig compiler.
3. Open a terminal in the extracted engine folder.
4. Compile the engine.

## How To Use <a name="howtouse"></a>

I have not written anything for this section yet because the engine is still in development ^_^

## AI Usage <a name="aiusage"></a>

Most of the code in this engine has been written by me. I find that AI is often not very good at understanding the broader context when designing engine systems, so I generally do not use it for that kind of work.

One place where I have used AI is for generating tests for the math library. AI generated Python scripts using NumPy so that I could create test inputs and outputs, which I then copied into my own Zig unit tests.

I also occasionally use AI for ImGui-related code since UI work is not something I particularly enjoy, and I plan to replace ImGui in the future anyway.

Finally, I used AI to help generate the code that ensures structs are correctly aligned for uploading to the GPU. It was not a difficult function to write, but I was feeling lazy at the time. Actually, AI got the implementation wrong, and I ended up fixing it myself anyway.
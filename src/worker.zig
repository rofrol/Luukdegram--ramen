const std = @import("std");
const Sha1 = std.crypto.Sha1;
const Allocator = std.mem.Allocator;
const Peer = @import("peer.zig").Peer;
const Torrent = @import("torrent.zig").Torrent;
const Client = @import("net/tcp_client.zig").TcpClient;

const max_items = 5;
const max_block_size = 16384;

/// Context passed to the working threads
pub const WorkerContext = struct {
    worker: *Worker,
};

/// Worker that manages jobs
pub const Worker = struct {
    const Self = @This();
    mutex: *std.Mutex,
    work: *std.PriorityQueue(Work),
    torrent: *const Torrent,
    workers: usize,
    allocator: *Allocator,

    /// Creates a new worker for the given work
    pub fn init(
        allocator: *Allocator,
        mutex: *std.Mutex,
        torrent: *const Torrent,
        work: *std.PriorityQueue(Work),
    ) Self {
        return Self{
            .mutex = mutex,
            .work = work,
            .torrent = torrent,
            .workers = torrent.peers.len,
            .allocator = allocator,
        };
    }

    /// Returns a Client for a worker, returns null if no empty spots are left.
    pub fn getClient(self: *Self) ?Client {
        const lock = self.mutex.acquire();
        defer lock.release();

        const peer = if (self.workers > 0) self.torrent.peers[self.workers - 1] else return null;
        var client = Client.init(self.allocator, peer, self.torrent.file.hash, self.torrent.peer_id);
        self.workers -= 1;

        return client;
    }

    /// Puts a new piece of work in the queue
    pub fn put(self: *Self, work: Work) !void {
        const lock = self.mutex.acquire();
        defer lock.release();
        try self.work.add(work);
    }

    /// Returns next job from queue, returns null if no work left.
    pub fn next(self: *Self) ?Work {
        const lock = self.mutex.acquire();
        defer lock.release();
        return self.work.removeOrNull();
    }
};

/// A piece of work that needs to be done
pub const Work = struct {
    const Self = @This();
    index: usize,
    hash: [20]u8,
    size: usize,
    allocator: *std.mem.Allocator,
    buffer: []u8,

    /// Initializes work and creates a buffer according to the given size,
    /// call deinit() to free its memory.
    pub fn init(
        index: usize,
        hash: [20]u8,
        size: usize,
        allocator: *std.mem.Allocator,
    ) Self {
        return Self{
            .index = index,
            .hash = hash,
            .size = size,
            .allocator = allocator,
            .buffer = undefined,
        };
    }

    /// Downloads work into its buffer
    pub fn download(self: *Self, client: *Client) !void {
        var downloaded: usize = 0;
        var requested: usize = 0;
        var backlog: usize = 0;

        // request to the peer for more bytes
        while (downloaded < self.size) {
            // if we are not choked, request for bytes
            if (!client.choked) {
                while (backlog < max_items and requested < self.size) : (backlog += 1) {
                    const block_size = if (self.size - requested < max_block_size) self.size - requested else max_block_size;
                    try client.sendRequest(self.index, requested, block_size);
                    requested += block_size;
                }
            }

            // read the message we received, this is blocking
            if (try client.read()) |message| {
                switch (message.message_type) {
                    .Choke => client.choked = true,
                    .Unchoke => client.choked = false,
                    .Have => {
                        const index = try message.parseHave();
                        if (client.bitfield) |*bitfield| {
                            bitfield.setPiece(index);
                        }
                    },
                    .Piece => {
                        self.buffer = try self.allocator.alloc(u8, self.size);
                        const size = try message.parsePiece(self.buffer, self.index);
                        downloaded += size;
                        backlog -= 1;
                    },
                    else => {},
                }
            }
        }
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.buffer);
    }

    /// Checks the integrity of the data by checking its hash against the work's hash.
    fn eqlHash(self: Self) bool {
        var out: [20]u8 = undefined;
        Sha1.hash(self.buffer, &out);
        return std.mem.eql(u8, &self.hash, &out);
    }
};

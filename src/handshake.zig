const std = @import("std");
const testing = std.testing;

/// Handshake identifies the connection between us and the peers
pub const Handshake = struct {
    p_str: []const u8 = "BitTorrent protocol",
    hash: []const u8,
    peer: []const u8,

    /// Creates a new Handshake instance
    pub fn init(hash: []const u8, peerID: []const u8) Handshake {
        return .{
            .hash = hash,
            .peer = peerID,
        };
    }

    /// Serializes a Handshake object into binary data
    pub fn serialize(self: @This(), allocator: *std.mem.Allocator) ![]u8 {
        var buffer: []u8 = try allocator.alloc(u8, 1024);
        std.mem.copy(u8, buffer[0..], self.p_str);
        var i: usize = self.p_str.len + 8; // 8 reserved bytes
        std.mem.copy(u8, buffer[i..], self.hash);
        i += self.hash.len;
        std.mem.copy(u8, buffer[i..], self.peer);
        i += self.peer.len;
        return buffer[0..i];
    }

    /// Deserializes binary data into a handshake
    pub fn deserialize(data: []u8) Handshake {
        var i: usize = 20;
        var self: Handshake = undefined;
        self.peer = data[data.len - i ..];
        i += self.peer.len;
        self.hash = data[data.len - i .. data.len - self.peer.len];
        i += 8; // 8 spare bytes
        self.p_str = data[0 .. data.len - i];
        return self;
    }
};

test "Serialize handshake" {
    const hs = Handshake.init(
        "12345678901234567890",
        "12345678901234567890",
    );

    const result = try hs.serialize(testing.allocator);
    defer testing.allocator.free(result);
    testing.expect(result.len == 67);
}

test "Deserialize handshake" {
    const hs = Handshake.init(
        "12345678901234567890",
        "12345678901234567890",
    );

    const data = try hs.serialize(testing.allocator);
    defer testing.allocator.free(data);
    const result = Handshake.deserialize(data);
    testing.expect(std.mem.eql(u8, "BitTorrent protocol", result.p_str));
}

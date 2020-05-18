const std = @import("std");
const msg = @import("message.zig");

const Peer = @import("../peer.zig").Peer;
const Handshake = @import("handshake.zig").Handshake;

/// Client represents a connection between a peer and us
pub const TcpClient = struct {
    const Self = @This();

    peer: Peer,
    bitfield: []u8,
    hash: [20]u8,
    id: [20]u8,
    allocator: *std.mem.Allocator,
    socket: std.fs.File,
    choked: bool = false,

    /// initiates a new Client
    pub fn init(
        allocator: *std.mem.Allocator,
        peer: Peer,
        hash: [20]u8,
        peer_id: [20]u8,
    ) Self {
        return .{
            .peer = peer,
            .hash = hash,
            .id = peer_id,
            .allocator = allocator,
            .socket = undefined,
            .bitfield = undefined,
        };
    }

    /// Creates a connection with the peer
    pub fn connect(self: *Self) !void {
        var socket = try std.net.tcpConnectToAddress(self.peer.address);
        self.socket = socket;
        errdefer socket.close();

        // initialize our handshake
        _ = try self.handshake();

        //receive the Bitfield so we can start sending messages (optional)
        // if (try self.getBitfield()) |bitfield| {
        //     self.bitfield = bitfield;
        // }
    }

    /// Reads bytes from the connection and deserializes it into a `Message` object.
    /// This function allocates memory that must be freed.
    /// If null returned, it's a keep-alive message.
    pub fn read(self: Self) !?msg.Message {
        return msg.Message.read(self.allocator, self.socket.inStream());
    }

    /// Sends a 'Request' message to the peer
    pub fn sendRequest(
        self: Self,
        index: usize,
        begin: usize,
        length: usize,
    ) !void {
        const allocator = self.allocator;
        const message = try msg.Message.requestMessage(allocator, index, begin, length);
        defer allocator.free(message.payload);
        const buffer = try message.serialize(allocator);
        defer allocator.free(buffer);
        _ = try self.socket.write(buffer);
    }

    /// Sends a message of the given `MessageType` to the peer.
    pub fn sendTyped(self: Self, message_type: msg.MessageType) !void {
        const message = msg.Message.init(message_type);
        const buffer = try message.serialize(self.allocator);
        defer self.allocator.free(buffer);
        _ = try self.socket.write(buffer);
    }

    /// Sends the 'Have' message to the peer.
    pub fn sendHave(self: Self, index: usize) !void {
        const allocator = self.allocator;
        const have = try msg.Message.haveMessage(allocator, index);
        defer allocator.free(have.payload);
        const buffer = try have.serialize(allocator);
        defer allocator.free(buffer);
        _ = try self.socket.write(buffer);
    }

    /// Closes the connection
    pub fn close(self: Self) void {
        self.socket.close();
        self.peer.deinit(self.allocator);
    }

    /// Initiates a handshake between the peer and us.
    fn handshake(self: Self) !Handshake {
        var hs = Handshake.init(self.hash, self.id);

        _ = try self.socket.write(try hs.serialize(self.allocator));

        var tmp = try self.allocator.alloc(u8, 100);
        defer self.allocator.free(tmp);
        const response = try Handshake.read(tmp, self.socket.inStream());

        if (!std.mem.eql(u8, &self.hash, &response.hash)) return error.IncorrectHash;

        return response;
    }

    /// Attempt to receive a bitfield from the peer.
    fn getBitfield(self: Self) !?[]const u8 {
        if (try msg.Message.read(self.allocator, self.socket.inStream())) |message| {
            if (message.message_type != msg.MessageType.Bitfield) return error.UnexpectedMessageType;
            return message.payload;
        } else {
            return null;
        }
    }
};

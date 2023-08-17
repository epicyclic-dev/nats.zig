// Copyright 2023 torque@epicyclic.dev
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");

pub const nats_c = @cImport({
    @cInclude("nats/nats.h");
});

const err_ = @import("./error.zig");
const con_ = @import("./connection.zig");
const sub_ = @import("./subscription.zig");
const msg_ = @import("./message.zig");

pub const default_server_url = con_.default_server_url;
pub const Connection = con_.Connection;
pub const Subscription = sub_.Subscription;
pub const Message = msg_.Message;

const Status = err_.Status;
pub const Error = err_.Error;

fn onMessage(userdata: *bool, connection: *Connection, subscription: *Subscription, message: *Message) void {
    _ = subscription;

    std.debug.print("Subject \"{s}\" received message: \"{s}\"\n", .{
        message.getSubject(),
        message.getData() orelse "[null]",
    });

    if (message.getReply()) |reply| {
        connection.publishString(reply, "salutations") catch @panic("HELP");
    }

    userdata.* = true;
}

pub fn main() !void {
    const connection = try Connection.connectTo(default_server_url);
    defer connection.destroy();

    var done = false;
    const subscription = try connection.subscribe(bool, "channel", onMessage, &done);
    defer subscription.destroy();

    while (!done) {
        const reply = try connection.requestString("channel", "greetings", 1000);
        defer reply.destroy();

        std.debug.print("Reply \"{s}\" got message: {s}\n", .{
            reply.getSubject(),
            reply.getData() orelse "[null]",
        });
    }
}

pub fn getVersion() [:0]const u8 {
    const verString = nats_c.nats_GetVersion();
    return std.mem.sliceTo(verString, 0);
}

pub fn getVersionNumber() u32 {
    return nats_c.nats_GetVersionNumber();
}

pub fn checkCompatibility() bool {
    return nats_c.nats_CheckCompatibilityImpl(
        nats_c.NATS_VERSION_REQUIRED_NUMBER,
        nats_c.NATS_VERSION_NUMBER,
        nats_c.NATS_VERSION_STRING,
    );
}

pub fn now() i64 {
    return nats_c.nats_Now();
}

pub fn nowInNanoSeconds() i64 {
    return nats_c.nats_NowInNanoSeconds();
}

pub fn sleep(sleep_time: i64) void {
    return nats_c.nats_Sleep(sleep_time);
}

pub fn setMessageDeliveryPoolSize(max: c_int) Error!void {
    const status = Status.fromInt(nats_c.nats_SetMessageDeliveryPoolSize(max));
    return status.raise();
}

pub fn releaseThreadMemory() void {
    return nats_c.nats_ReleaseThreadMemory();
}

pub fn init(lock_spin_count: i64) Error!void {
    const status = Status.fromInt(nats_c.nats_Open(lock_spin_count));
    return status.raise();
}

pub fn deinit() void {
    return nats_c.nats_Close();
}

// the result of this requires manual deallocation unless it is used to provide the
// signature out-parameter in the natsSignatureHandler callback. Calling it outside of
// that context seems unlikely, but we should probably provide a deinit function so the
// user doesn't have to dig around for libc free to deallocate it.
pub fn sign(encoded_seed: [:0]const u8, input: [:0]const u8) Error![]const u8 {
    var result: [*]u8 = undefined;
    var length: c_int = 0;
    const status = Status.fromInt(nats_c.nats_Sign(encoded_seed.ptr, &input, &length));

    return status.toError() orelse result[0..@intCast(length)];
}

pub fn deinitWait(timeout: i64) Error!void {
    const status = Status.fromInt(nats_c.nats_CloseAndWait(timeout));
    return status.raise();
}

pub const StatsCounts = struct {
    messages_in: u64 = 0,
    bytes_in: u64 = 0,
    messages_out: u64 = 0,
    bytes_out: u64 = 0,
    reconnects: u64 = 0,
};

pub const Statistics = opaque {
    pub fn create() Error!*Statistics {
        var stats: *Statistics = undefined;
        const status = Status.fromInt(nats_c.natsStatistics_Create(@ptrCast(&stats)));
        return status.toError() orelse stats;
    }

    pub fn deinit(self: *Statistics) void {
        nats_c.natsStatistics_Destroy(@ptrCast(self));
    }

    pub fn getCounts(self: *Statistics) Error!StatsCounts {
        var counts: StatsCounts = .{};
        const status = Status.fromInt(nats_c.natsStatistics_GetCounts)(
            self,
            &counts.messages_in,
            &counts.bytes_in,
            &counts.messages_out,
            &counts.bytes_out,
            &counts.reconnects,
        );
        return status.toError() orelse counts;
    }
};

// This appears to be a jetstream API, but these two endpoints are trivial, so, whoops.
// I have no clue what this does, since there's basically no
pub const Inbox = opaque {
    pub fn create() Error!*Inbox {
        var self: *Inbox = undefined;
        const status = Status.fromInt(nats_c.natsInbox_Create(@ptrCast(&self)));

        return status.toError() orelse self;
    }

    pub fn destroy(self: *Inbox) void {
        nats_c.natsInbox_Destroy(@ptrCast(self));
    }
};

// I think this is also a jetstream API. This function sure does not seem at all useful
// by itself.
pub const MessageList = opaque {
    pub fn destroy(self: *MessageList) void {
        nats_c.natsMsgList_Destroy(@ptrCast(self));
    }
};

test {
    std.testing.refAllDecls(@This());
}

// NATS_EXTERN natsStatus natsOptions_Create(natsOptions **newOpts);
// NATS_EXTERN natsStatus natsOptions_SetURL(natsOptions *opts, const char *url);
// NATS_EXTERN natsStatus natsOptions_SetServers(natsOptions *opts, const char** servers, int serversCount);
// NATS_EXTERN natsStatus natsOptions_SetUserInfo(natsOptions *opts, const char *user, const char *password);
// NATS_EXTERN natsStatus natsOptions_SetToken(natsOptions *opts, const char *token);
// NATS_EXTERN natsStatus natsOptions_SetTokenHandler(natsOptions *opts, natsTokenHandler tokenCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetNoRandomize(natsOptions *opts, bool noRandomize);
// NATS_EXTERN natsStatus natsOptions_SetTimeout(natsOptions *opts, int64_t timeout);
// NATS_EXTERN natsStatus natsOptions_SetName(natsOptions *opts, const char *name);
// NATS_EXTERN natsStatus natsOptions_SetSecure(natsOptions *opts, bool secure);
// NATS_EXTERN natsStatus natsOptions_LoadCATrustedCertificates(natsOptions *opts, const char *fileName);
// NATS_EXTERN natsStatus natsOptions_SetCATrustedCertificates(natsOptions *opts, const char *certificates);
// NATS_EXTERN natsStatus natsOptions_LoadCertificatesChain(natsOptions *opts, const char *certsFileName, const char *keyFileName);
// NATS_EXTERN natsStatus natsOptions_SetCertificatesChain(natsOptions *opts, const char *cert, const char *key);
// NATS_EXTERN natsStatus natsOptions_SetCiphers(natsOptions *opts, const char *ciphers);
// NATS_EXTERN natsStatus natsOptions_SetCipherSuites(natsOptions *opts, const char *ciphers);
// NATS_EXTERN natsStatus natsOptions_SetExpectedHostname(natsOptions *opts, const char *hostname);
// NATS_EXTERN natsStatus natsOptions_SkipServerVerification(natsOptions *opts, bool skip);
// NATS_EXTERN natsStatus natsOptions_SetVerbose(natsOptions *opts, bool verbose);
// NATS_EXTERN natsStatus natsOptions_SetPedantic(natsOptions *opts, bool pedantic);
// NATS_EXTERN natsStatus natsOptions_SetPingInterval(natsOptions *opts, int64_t interval);
// NATS_EXTERN natsStatus natsOptions_SetMaxPingsOut(natsOptions *opts, int maxPingsOut);
// NATS_EXTERN natsStatus natsOptions_SetIOBufSize(natsOptions *opts, int ioBufSize);
// NATS_EXTERN natsStatus natsOptions_SetAllowReconnect(natsOptions *opts, bool allow);
// NATS_EXTERN natsStatus natsOptions_SetMaxReconnect(natsOptions *opts, int maxReconnect);
// NATS_EXTERN natsStatus natsOptions_SetReconnectWait(natsOptions *opts, int64_t reconnectWait);
// NATS_EXTERN natsStatus natsOptions_SetReconnectJitter(natsOptions *opts, int64_t jitter, int64_t jitterTLS);
// NATS_EXTERN natsStatus natsOptions_SetCustomReconnectDelay(natsOptions *opts, natsCustomReconnectDelayHandler cb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetReconnectBufSize(natsOptions *opts, int reconnectBufSize);
// NATS_EXTERN natsStatus natsOptions_SetMaxPendingMsgs(natsOptions *opts, int maxPending);
// NATS_EXTERN natsStatus natsOptions_SetErrorHandler(natsOptions *opts, natsErrHandler errHandler, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetClosedCB(natsOptions *opts, natsConnectionHandler closedCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetDisconnectedCB(natsOptions *opts, natsConnectionHandler disconnectedCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetReconnectedCB(natsOptions *opts, natsConnectionHandler reconnectedCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetDiscoveredServersCB(natsOptions *opts, natsConnectionHandler discoveredServersCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetIgnoreDiscoveredServers(natsOptions *opts, bool ignore);
// NATS_EXTERN natsStatus natsOptions_SetLameDuckModeCB(natsOptions *opts, natsConnectionHandler lameDuckCb, void *closure);
// NATS_EXTERN natsStatus natsOptions_SetEventLoop(natsOptions *opts, void *loop, natsEvLoop_Attach attachCb, natsEvLoop_ReadAddRemove readCb, natsEvLoop_WriteAddRemove writeCb, natsEvLoop_Detach detachCb);
// NATS_EXTERN natsStatus natsOptions_UseGlobalMessageDelivery(natsOptions *opts, bool global);
// NATS_EXTERN natsStatus natsOptions_IPResolutionOrder(natsOptions *opts, int order);
// NATS_EXTERN natsStatus natsOptions_SetSendAsap(natsOptions *opts, bool sendAsap);
// NATS_EXTERN natsStatus natsOptions_UseOldRequestStyle(natsOptions *opts, bool useOldStyle);
// NATS_EXTERN natsStatus natsOptions_SetFailRequestsOnDisconnect(natsOptions *opts, bool failRequests);
// NATS_EXTERN natsStatus natsOptions_SetNoEcho(natsOptions *opts, bool noEcho);
// NATS_EXTERN natsStatus natsOptions_SetRetryOnFailedConnect(natsOptions *opts, bool retry, natsConnectionHandler connectedCb, void* closure);
// NATS_EXTERN natsStatus natsOptions_SetUserCredentialsCallbacks(natsOptions *opts, natsUserJWTHandler ujwtCB, void *ujwtClosure, natsSignatureHandler sigCB, void *sigClosure);
// NATS_EXTERN natsStatus natsOptions_SetUserCredentialsFromFiles(natsOptions *opts, const char *userOrChainedFile, const char *seedFile);
// NATS_EXTERN natsStatus natsOptions_SetUserCredentialsFromMemory(natsOptions *opts, const char *jwtAndSeedContent);
// NATS_EXTERN natsStatus natsOptions_SetNKey(natsOptions             *opts, const char              *pubKey, natsSignatureHandler    sigCB, void                    *sigClosure);
// NATS_EXTERN natsStatus natsOptions_SetNKeyFromSeed(natsOptions *opts, const char  *pubKey, const char  *seedFile);
// NATS_EXTERN natsStatus natsOptions_SetWriteDeadline(natsOptions *opts, int64_t deadline);
// NATS_EXTERN natsStatus natsOptions_DisableNoResponders(natsOptions *opts, bool disabled);
// NATS_EXTERN natsStatus natsOptions_SetCustomInboxPrefix(natsOptions *opts, const char *inboxPrefix);
// NATS_EXTERN natsStatus natsOptions_SetMessageBufferPadding(natsOptions *opts, int paddingSize);
// NATS_EXTERN void natsOptions_Destroy(natsOptions *opts);

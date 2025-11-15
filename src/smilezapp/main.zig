const std = @import("std");
const smilez = @import("smilez");

const iteration_count = 100_000;
const repeat_count = 10;
const smiles_input = "C1CC(=O)CCC1";

var smiles_buffer: [65536]u8 = undefined;

const AllocatorType = enum { gpa, fba, c };
const Result = struct {
    allocator: AllocatorType,
    times_ns: [repeat_count]u64 = [_]u64 { 0 } ** repeat_count,
};

fn runBenchmark(allocatorType: AllocatorType, allocator: std.mem.Allocator, repeat_index: usize, results: *Result) !void {
    var timer = try std.time.Timer.start();

    switch (allocatorType) {
        .gpa, .c => {
            for (0..iteration_count) |_| {
                const result = try smilez.Parser.parseSMILES(smiles_input, allocator);
                std.mem.doNotOptimizeAway(result);
            }
        },
        .fba => {
            var fba = std.heap.FixedBufferAllocator.init(&smiles_buffer);
            for (0..iteration_count) |_| {
                const result = try smilez.Parser.parseSMILES(smiles_input, fba.allocator());
                std.mem.doNotOptimizeAway(result);
                fba.reset();
            }
        },
    }

    const elapsed = timer.read();
    results.times_ns[repeat_index] = elapsed;
}

fn runAllBenchmarks(allocator: std.mem.Allocator, results: []Result) !void {
    for (results) |*res| {
        for (0..repeat_count) |r| {
            try runBenchmark(res.allocator, allocator, r, res);
        }
    }
}

const benchmark = false;

pub fn main() !void {
    if (!benchmark) {
        var fba = std.heap.FixedBufferAllocator.init(&smiles_buffer);
        const molecule = try smilez.Parser.parseSMILES("C(C(CC(=O)O)(C(=O)O)C(=O)O)(C(=O)O)(C(=O)O)C(=O)O", fba.allocator());
        try smilez.Parser.outputCML("molecule.cml", &molecule);
    } else {
        var results = [_]Result{
            .{ .allocator = .gpa },
            .{ .allocator = .fba },
            .{ .allocator = .c },
        };

        var threads: [3]std.Thread = undefined;

        threads[0] = try std.Thread.spawn(.{}, struct {
            fn run(res: *Result) !void {
                var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                defer _ = gpa.deinit();
                for (0..repeat_count) |r| {
                    try runBenchmark(.gpa, gpa.allocator(), r, res);
                }
            }
        }.run, .{&results[0]});

        threads[1] = try std.Thread.spawn(.{}, struct {
            fn run(res: *Result) !void {
                for (0..repeat_count) |r| {
                    try runBenchmark(.fba, std.heap.page_allocator, r, res);
                }
            }
        }.run, .{&results[1]});

        threads[2] = try std.Thread.spawn(.{}, struct {
            fn run(res: *Result) !void {
                for (0..repeat_count) |r| {
                    try runBenchmark(.c, std.heap.c_allocator, r, res);
                }
            }
        }.run, .{&results[2]});

        for (&threads) |*t| {
            t.join();
        }

        for (results) |result| {
            printResult(&result);
        }
    }
}

fn printResult(res: *const Result) void {
    var total_ns: u128 = 0;
    for (res.times_ns) |t| {
        total_ns += @intCast(t);
    }

    const avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(repeat_count));
    const avg_ms = avg_ns / 1_000_000.0;
    const avg_per_parse_ms = avg_ms / @as(f64, @floatFromInt(iteration_count));

    const name = switch (res.allocator) {
        .gpa => "GeneralPurposeAllocator",
        .fba => "FixedBufferAllocator",
        .c   => "c_allocator",
    };

    std.debug.print("{s} average: {d:.3} ms total, {d:.6} ms/parse\n",
        .{
            name,
            avg_ms,
            avg_per_parse_ms
        }
    );
}

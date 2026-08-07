`timescale 1ns / 1ps

`ifndef MULEIN_CLOSURE_CORE_SV
`define MULEIN_CLOSURE_CORE_SV

// Mulein Closure Core
// ===================
//
// Scalar closure lane for a future-parallel Mulein bank.  The lane owns only mutable
// diagonal-board state.  Edge descriptors and Enigma scrambler LUTs are read through shared
// combinational interfaces, so a bank can broadcast one 130-bit S_t permutation to every
// seed/future lane instead of synthesizing a private rotor datapath or LUT memory per lane.
//
// Shared-store protocol
// ---------------------
// `edge_read_index` addresses one menu descriptor `(a,b,step)`.  The descriptor's step is
// reflected on `step_read_index`; the shared trail store returns the complete permutation
// S_t as 26 packed five-bit values (`S_t(x)` at bits `5*x +: 5`).  A standalone wrapper may
// back these interfaces with runtime-programmable RAM; an FPGA future bank should own one
// multi-lane/broadcast store and a Metal threadgroup should use shared memory.
//
// Job protocol
// ------------
// Pulse `start` while idle with edge count, central menu letter, maximum plug pairs, and
// tolerance 0 or 1.  The lane evaluates all 26 central-letter seeds. `done` pulses for one
// cycle. `survivor_mask` records exact/tolerant survivors; `erased_seed_mask` and packed
// `erased_edge_by_seed` retain the concrete repair needed for host confirmation.
// `max_plugs == 0` disables the physical plug sieve, matching the Swift/Metal API.
//
// Board representation
// --------------------
// Before contradiction every Welchman live row has at most one bit. Store that partial
// involution as 26 valid bits plus 26 five-bit values, and impose diagonal reciprocity
// immediately: sigma(x)=y also writes sigma(y)=x. This is closure-equivalent to the Swift
// 26-bit-row oracle while requiring 156 state bits rather than a 26x26 matrix.
//
// Tolerance and completeness
// --------------------------
// Exact closure runs first. If it contradicts *or closes above the physical plug budget*,
// tolerance 1 retries only edges that changed the exact partial involution or exposed its
// contradiction. Dropping an inactive edge leaves both closure and plug count unchanged, so
// it cannot repair either failure. A reduced menu is rejected when the central letter no
// longer touches a surviving edge. Higher tolerance remains in Swift/Metal until a banked
// RTL implementation is exhaustively cross-checked against the blind subset oracle.
module mulein_closure_core #(
    parameter integer MAX_EDGES = 40,
    parameter integer MAX_STEPS = 80,
    parameter integer EDGE_BITS = 6,
    parameter integer STEP_BITS = 7
) (
    input  wire                         clk,
    input  wire                         resetn,

    // Shared menu descriptor read port.
    output wire [EDGE_BITS-1:0]         edge_read_index,
    input  wire [4:0]                   edge_read_a,
    input  wire [4:0]                   edge_read_b,
    input  wire [STEP_BITS-1:0]         edge_read_step,

    // Shared scrambler-trail read port. Row packing: S_t(x) = row[5*x +: 5].
    output wire [STEP_BITS-1:0]         step_read_index,
    input  wire [(26*5)-1:0]            step_read_row,

    input  wire                         start,
    input  wire [EDGE_BITS-1:0]         start_edge_count,
    input  wire [4:0]                   start_central,
    input  wire [4:0]                   start_max_plugs,
    input  wire [1:0]                   start_tolerance,

    output reg                          busy,
    output reg                          done,
    output reg                          config_error,
    output reg  [25:0]                  survivor_mask,
    output reg  [25:0]                  erased_seed_mask,
    output reg  [(26*EDGE_BITS)-1:0]    erased_edge_by_seed,

    // Receipt instrumentation: proves the requested erasure work was actually performed.
    output reg  [31:0]                  cycle_count,
    output reg  [31:0]                  closure_count,
    output reg  [31:0]                  drop_trial_count
);

    localparam [EDGE_BITS-1:0] DROP_NONE = {EDGE_BITS{1'b1}};

    localparam [4:0]
        ST_IDLE          = 5'd0,
        ST_SEED_INIT     = 5'd1,
        ST_PASS_BEGIN    = 5'd2,
        ST_EDGE_FWD      = 5'd3,
        ST_EDGE_REV      = 5'd4,
        ST_EDGE_NEXT     = 5'd5,
        ST_PASS_END      = 5'd6,
        ST_CLOSURE_FAIL  = 5'd7,
        ST_PLUG_BEGIN    = 5'd8,
        ST_PLUG_COUNT    = 5'd9,
        ST_PLUG_DONE     = 5'd10,
        ST_SELECT_DROP   = 5'd11,
        ST_ATTACH_BEGIN  = 5'd12,
        ST_ATTACH_SCAN   = 5'd13,
        ST_ADVANCE_SEED  = 5'd14;

    reg [4:0] state;

    reg [EDGE_BITS-1:0] edge_count_reg;
    reg [4:0]           central_reg;
    reg [4:0]           max_plugs_reg;
    reg                 tolerance_one;

    reg [4:0]           seed_cursor;
    reg [EDGE_BITS-1:0] edge_cursor;
    reg [4:0]           plug_cursor;
    reg [5:0]           plug_pairs;
    reg [EDGE_BITS-1:0] attach_cursor;

    // Packed compact partial involution: value for letter x is at 5*x +: 5.
    reg [25:0]          live_valid;
    reg [(26*5)-1:0]   live_values;

    reg                 changed;
    reg                 contradiction;
    reg                 drop_enabled;
    reg [EDGE_BITS-1:0] drop_index;
    reg                 seed_attached;

    reg [MAX_EDGES-1:0] active_work;
    reg [MAX_EDGES-1:0] drop_candidates;
    reg [EDGE_BITS-1:0] selected_drop;
    reg [4:0]           mapped_value;
    reg [4:0]           current_value;

    // Attachment scans use their own descriptor address; closure scans use edge_cursor.
    assign edge_read_index = (state == ST_ATTACH_SCAN) ? attach_cursor : edge_cursor;
    assign step_read_index = edge_read_step;

    function automatic [4:0] mapping_at;
        input [(26*5)-1:0] mappings;
        input [4:0] letter;
        begin
            mapping_at = mappings[(letter * 5) +: 5];
        end
    endfunction

    function automatic [4:0] scrambler_at;
        input [(26*5)-1:0] row;
        input [4:0] letter;
        begin
            scrambler_at = row[(letter * 5) +: 5];
        end
    endfunction

    function automatic [EDGE_BITS-1:0] first_active;
        input [MAX_EDGES-1:0] mask;
        integer k;
        reg found;
        begin
            first_active = DROP_NONE;
            found = 1'b0;
            for (k = 0; k < MAX_EDGES; k = k + 1) begin
                if (!found && mask[k]) begin
                    first_active = k[EDGE_BITS-1:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    // Impose sigma(x)=y and diagonal reciprocity sigma(y)=x.
    task automatic impose_pair;
        input [4:0] x;
        input [4:0] y;
        input [EDGE_BITS-1:0] source_edge;
        reg wrote;
        begin
            wrote = 1'b0;
            if (x >= 26 || y >= 26) begin
                contradiction = 1'b1;
                active_work[source_edge] = 1'b1;
            end else begin
                if (live_valid[x]) begin
                    if (mapping_at(live_values, x) != y) begin
                        contradiction = 1'b1;
                        active_work[source_edge] = 1'b1;
                    end
                end else begin
                    live_valid[x] = 1'b1;
                    live_values[(x * 5) +: 5] = y;
                    wrote = 1'b1;
                end

                if (!contradiction) begin
                    if (live_valid[y]) begin
                        if (mapping_at(live_values, y) != x) begin
                            contradiction = 1'b1;
                            active_work[source_edge] = 1'b1;
                        end
                    end else begin
                        live_valid[y] = 1'b1;
                        live_values[(y * 5) +: 5] = x;
                        wrote = 1'b1;
                    end
                end

                if (wrote) begin
                    changed = 1'b1;
                    active_work[source_edge] = 1'b1;
                end
            end
        end
    endtask

    task automatic launch_closure;
        begin
            live_valid = 26'd0;
            live_values = {(26*5){1'b0}};
            changed = 1'b0;
            contradiction = 1'b0;
            active_work = {MAX_EDGES{1'b0}};
            closure_count = closure_count + 1'b1;
            state = ST_SEED_INIT;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            state = ST_IDLE;
            busy = 1'b0;
            done = 1'b0;
            config_error = 1'b0;
            survivor_mask = 26'd0;
            erased_seed_mask = 26'd0;
            erased_edge_by_seed = {(26*EDGE_BITS){1'b1}};
            cycle_count = 32'd0;
            closure_count = 32'd0;
            drop_trial_count = 32'd0;
            edge_count_reg = {EDGE_BITS{1'b0}};
            central_reg = 5'd0;
            max_plugs_reg = 5'd0;
            tolerance_one = 1'b0;
            seed_cursor = 5'd0;
            edge_cursor = {EDGE_BITS{1'b0}};
            attach_cursor = {EDGE_BITS{1'b0}};
            drop_enabled = 1'b0;
            drop_index = DROP_NONE;
            live_valid = 26'd0;
            live_values = {(26*5){1'b0}};
        end else begin
            done = 1'b0;
            if (busy)
                cycle_count = cycle_count + 1'b1;

            case (state)
                ST_IDLE: begin
                    edge_cursor = {EDGE_BITS{1'b0}};
                    if (start) begin
                        survivor_mask = 26'd0;
                        erased_seed_mask = 26'd0;
                        erased_edge_by_seed = {(26*EDGE_BITS){1'b1}};
                        cycle_count = 32'd0;
                        closure_count = 32'd0;
                        drop_trial_count = 32'd0;

                        if (start_edge_count == 0 || start_edge_count > MAX_EDGES ||
                            start_central >= 26 || start_tolerance > 1) begin
                            config_error = 1'b1;
                            busy = 1'b0;
                            done = 1'b1;
                        end else begin
                            config_error = 1'b0;
                            edge_count_reg = start_edge_count;
                            central_reg = start_central;
                            max_plugs_reg = start_max_plugs;
                            tolerance_one = (start_tolerance == 1);
                            seed_cursor = 5'd0;
                            drop_enabled = 1'b0;
                            drop_index = DROP_NONE;
                            busy = 1'b1;
                            launch_closure();
                        end
                    end
                end

                ST_SEED_INIT: begin
                    // Seed plus immediate diagonal reciprocity.
                    live_valid[central_reg] = 1'b1;
                    live_values[(central_reg * 5) +: 5] = seed_cursor;
                    live_valid[seed_cursor] = 1'b1;
                    live_values[(seed_cursor * 5) +: 5] = central_reg;
                    changed = 1'b0;
                    contradiction = 1'b0;
                    state = ST_PASS_BEGIN;
                end

                ST_PASS_BEGIN: begin
                    changed = 1'b0;
                    contradiction = 1'b0;
                    edge_cursor = {EDGE_BITS{1'b0}};
                    state = ST_EDGE_FWD;
                end

                ST_EDGE_FWD: begin
                    if (edge_read_a >= 26 || edge_read_b >= 26 ||
                        edge_read_step >= MAX_STEPS) begin
                        config_error = 1'b1;
                        busy = 1'b0;
                        done = 1'b1;
                        state = ST_IDLE;
                    end else if (drop_enabled && edge_cursor == drop_index) begin
                        state = ST_EDGE_NEXT;
                    end else begin
                        if (live_valid[edge_read_a]) begin
                            current_value = mapping_at(live_values, edge_read_a);
                            mapped_value = scrambler_at(step_read_row, current_value);
                            impose_pair(edge_read_b, mapped_value, edge_cursor);
                        end
                        if (contradiction)
                            state = ST_CLOSURE_FAIL;
                        else
                            state = ST_EDGE_REV;
                    end
                end

                ST_EDGE_REV: begin
                    if (live_valid[edge_read_b]) begin
                        current_value = mapping_at(live_values, edge_read_b);
                        mapped_value = scrambler_at(step_read_row, current_value);
                        impose_pair(edge_read_a, mapped_value, edge_cursor);
                    end
                    if (contradiction)
                        state = ST_CLOSURE_FAIL;
                    else
                        state = ST_EDGE_NEXT;
                end

                ST_EDGE_NEXT: begin
                    if ((edge_cursor + 1'b1) >= edge_count_reg) begin
                        state = ST_PASS_END;
                    end else begin
                        edge_cursor = edge_cursor + 1'b1;
                        state = ST_EDGE_FWD;
                    end
                end

                ST_PASS_END: begin
                    if (changed)
                        state = ST_PASS_BEGIN;
                    else
                        state = ST_PLUG_BEGIN;
                end

                ST_CLOSURE_FAIL: begin
                    if (!drop_enabled && tolerance_one) begin
                        drop_candidates = active_work;
                        state = ST_SELECT_DROP;
                    end else if (drop_enabled) begin
                        state = ST_SELECT_DROP;
                    end else begin
                        state = ST_ADVANCE_SEED;
                    end
                end

                ST_PLUG_BEGIN: begin
                    plug_cursor = 5'd0;
                    plug_pairs = 6'd0;
                    state = ST_PLUG_COUNT;
                end

                ST_PLUG_COUNT: begin
                    if (live_valid[plug_cursor]) begin
                        current_value = mapping_at(live_values, plug_cursor);
                        if (current_value != plug_cursor && plug_cursor < current_value)
                            plug_pairs = plug_pairs + 1'b1;
                    end
                    if (plug_cursor == 25)
                        state = ST_PLUG_DONE;
                    else
                        plug_cursor = plug_cursor + 1'b1;
                end

                ST_PLUG_DONE: begin
                    if (max_plugs_reg == 0 || plug_pairs <= max_plugs_reg) begin
                        survivor_mask[seed_cursor] = 1'b1;
                        if (drop_enabled) begin
                            erased_seed_mask[seed_cursor] = 1'b1;
                            erased_edge_by_seed[(seed_cursor * EDGE_BITS) +: EDGE_BITS]
                                = drop_index;
                        end
                        state = ST_ADVANCE_SEED;
                    end else if (!drop_enabled && tolerance_one) begin
                        // Consistent but physically impossible: active erasures may reduce it.
                        drop_candidates = active_work;
                        state = ST_SELECT_DROP;
                    end else if (drop_enabled) begin
                        state = ST_SELECT_DROP;
                    end else begin
                        state = ST_ADVANCE_SEED;
                    end
                end

                ST_SELECT_DROP: begin
                    selected_drop = first_active(drop_candidates);
                    if (selected_drop == DROP_NONE) begin
                        state = ST_ADVANCE_SEED;
                    end else begin
                        drop_index = selected_drop;
                        drop_candidates[selected_drop] = 1'b0;
                        drop_trial_count = drop_trial_count + 1'b1;
                        state = ST_ATTACH_BEGIN;
                    end
                end

                ST_ATTACH_BEGIN: begin
                    seed_attached = 1'b0;
                    attach_cursor = {EDGE_BITS{1'b0}};
                    state = ST_ATTACH_SCAN;
                end

                ST_ATTACH_SCAN: begin
                    if (attach_cursor != drop_index &&
                        (edge_read_a == central_reg || edge_read_b == central_reg)) begin
                        seed_attached = 1'b1;
                    end

                    if ((attach_cursor + 1'b1) >= edge_count_reg) begin
                        if (seed_attached) begin
                            drop_enabled = 1'b1;
                            launch_closure();
                        end else begin
                            state = ST_SELECT_DROP;
                        end
                    end else begin
                        attach_cursor = attach_cursor + 1'b1;
                    end
                end

                ST_ADVANCE_SEED: begin
                    if (seed_cursor == 25) begin
                        busy = 1'b0;
                        done = 1'b1;
                        state = ST_IDLE;
                    end else begin
                        seed_cursor = seed_cursor + 1'b1;
                        drop_enabled = 1'b0;
                        drop_index = DROP_NONE;
                        launch_closure();
                    end
                end

                default: begin
                    config_error = 1'b1;
                    busy = 1'b0;
                    done = 1'b1;
                    state = ST_IDLE;
                end
            endcase
        end
    end
endmodule

`endif

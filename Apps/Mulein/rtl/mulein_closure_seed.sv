`ifndef MULEIN_CLOSURE_SEED_SV
`define MULEIN_CLOSURE_SEED_SV

// Mulein single-seed production closure lane
// ============================================
//
// This lane is the independently schedulable unit used by the TensorLUT Future Bank.  The
// host compiles every exact/indel transcript hypothesis to an ordered (a,b,step) descriptor
// list; the lane never parses edit scripts.  It runs exact diagonal-board closure first and,
// only after contradiction or physical-budget failure, tries one active edge erasure in
// lexical order.  Descriptor and M4 scrambler rows are read through combinational ports so a
// bank can keep one shared trail store while replicating only mutable closure state.
//
// Results use a held valid/ready protocol.  A negative is an explicit result_hit=0 receipt,
// never the absence of a pulse.  The producer holds every result field stable until
// result_ready is sampled.  This is cleartext circuit machinery; it is not an FHE primitive.
module mulein_closure_seed #(
    parameter integer MAX_EDGES = 40,
    parameter integer MAX_STEPS = 80,
    parameter integer EDGE_BITS = 6,
    parameter integer STEP_BITS = 7,
    parameter integer TAG_BITS  = 32
) (
    input  wire                         clk,
    input  wire                         resetn,

    output wire [EDGE_BITS-1:0]         edge_read_index,
    input  wire [4:0]                   edge_read_a,
    input  wire [4:0]                   edge_read_b,
    input  wire [STEP_BITS-1:0]         edge_read_step,

    output wire [STEP_BITS-1:0]         step_read_index,
    input  wire [(26*5)-1:0]            step_read_row,

    input  wire                         start,
    input  wire [EDGE_BITS-1:0]         start_edge_count,
    input  wire [4:0]                   start_central,
    input  wire [4:0]                   start_seed,
    input  wire [4:0]                   start_max_plugs,
    input  wire [4:0]                   start_exact_plugs,
    input  wire [1:0]                   start_tolerance,
    input  wire [TAG_BITS-1:0]          start_tag,

    output reg                          busy,
    output reg                          result_valid,
    input  wire                         result_ready,
    output reg                          result_config_error,
    output reg                          result_hit,
    output reg  [TAG_BITS-1:0]          result_tag,
    output reg  [4:0]                   result_seed,
    output reg                          result_exact,
    output reg  [MAX_EDGES-1:0]         result_drop_mask,
    output reg  [EDGE_BITS-1:0]         result_erased_edge,
    output reg  [3:0]                   result_pair_count,
    output reg  [4:0]                   result_determined_count,
    output reg  [31:0]                  result_live_hash,
    output reg  [31:0]                  result_cycle_count,
    output reg  [31:0]                  result_closure_count,
    output reg  [31:0]                  result_drop_trial_count
);
    localparam [EDGE_BITS-1:0] DROP_NONE = {EDGE_BITS{1'b1}};
    localparam [31:0] FNV_OFFSET = 32'd2166136261;
    localparam [31:0] FNV_PRIME  = 32'd16777619;

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
        ST_RESULT        = 5'd14;

    reg [4:0] state;

    reg [EDGE_BITS-1:0] edge_count_reg;
    reg [4:0]           central_reg;
    reg [4:0]           seed_reg;
    reg [4:0]           max_plugs_reg;
    reg [4:0]           exact_plugs_reg;
    reg                 tolerance_one;
    reg [TAG_BITS-1:0]  tag_reg;

    reg [EDGE_BITS-1:0] edge_cursor;
    reg [EDGE_BITS-1:0] attach_cursor;
    reg [4:0]           plug_cursor;
    reg [5:0]           plug_pairs;
    reg [5:0]           determined_count;

    // Compact partial involution: sigma(x) is live_values[5*x +: 5] when live_valid[x].
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
    reg [31:0]          live_hash;
    reg [31:0]          hash_word;
    reg [5:0]           free_letters;
    reg [5:0]           required_letters;
    reg                 budget_ok;

    reg [31:0] cycle_count;
    reg [31:0] closure_count;
    reg [31:0] drop_trial_count;

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

    task automatic finish_result;
        input hit;
        input config_error;
        begin
            busy = 1'b0;
            result_valid = 1'b1;
            result_config_error = config_error;
            result_hit = hit;
            result_tag = tag_reg;
            result_seed = seed_reg;
            result_cycle_count = cycle_count;
            result_closure_count = closure_count;
            result_drop_trial_count = drop_trial_count;
            if (hit) begin
                result_exact = !drop_enabled;
                result_drop_mask = {MAX_EDGES{1'b0}};
                if (drop_enabled)
                    result_drop_mask[drop_index] = 1'b1;
                result_erased_edge = drop_enabled ? drop_index : DROP_NONE;
                result_pair_count = plug_pairs[3:0];
                result_determined_count = determined_count[4:0];
                result_live_hash = live_hash;
            end else begin
                result_exact = 1'b0;
                result_drop_mask = {MAX_EDGES{1'b0}};
                result_erased_edge = DROP_NONE;
                result_pair_count = 4'd0;
                result_determined_count = 5'd0;
                result_live_hash = 32'd0;
            end
            state = ST_RESULT;
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            state = ST_IDLE;
            busy = 1'b0;
            result_valid = 1'b0;
            result_config_error = 1'b0;
            result_hit = 1'b0;
            result_tag = {TAG_BITS{1'b0}};
            result_seed = 5'd0;
            result_exact = 1'b0;
            result_drop_mask = {MAX_EDGES{1'b0}};
            result_erased_edge = DROP_NONE;
            result_pair_count = 4'd0;
            result_determined_count = 5'd0;
            result_live_hash = 32'd0;
            result_cycle_count = 32'd0;
            result_closure_count = 32'd0;
            result_drop_trial_count = 32'd0;
            cycle_count = 32'd0;
            closure_count = 32'd0;
            drop_trial_count = 32'd0;
            edge_count_reg = {EDGE_BITS{1'b0}};
            central_reg = 5'd0;
            seed_reg = 5'd0;
            max_plugs_reg = 5'd0;
            exact_plugs_reg = 5'd0;
            tolerance_one = 1'b0;
            tag_reg = {TAG_BITS{1'b0}};
            edge_cursor = {EDGE_BITS{1'b0}};
            attach_cursor = {EDGE_BITS{1'b0}};
            drop_enabled = 1'b0;
            drop_index = DROP_NONE;
            live_valid = 26'd0;
            live_values = {(26*5){1'b0}};
        end else begin
            if (busy)
                cycle_count = cycle_count + 1'b1;

            case (state)
                ST_IDLE: begin
                    edge_cursor = {EDGE_BITS{1'b0}};
                    if (start) begin
                        result_config_error = 1'b0;
                        result_hit = 1'b0;
                        cycle_count = 32'd0;
                        closure_count = 32'd0;
                        drop_trial_count = 32'd0;
                        tag_reg = start_tag;
                        seed_reg = start_seed;

                        if (start_edge_count == 0 || start_edge_count > MAX_EDGES ||
                            start_central >= 26 || start_seed >= 26 ||
                            start_max_plugs > 13 || start_exact_plugs > 13 ||
                            (start_max_plugs != 0 && start_exact_plugs != 0 &&
                             start_exact_plugs > start_max_plugs) ||
                            start_tolerance > 1) begin
                            result_valid = 1'b1;
                            result_config_error = 1'b1;
                            result_hit = 1'b0;
                            result_tag = start_tag;
                            result_seed = start_seed;
                            result_exact = 1'b0;
                            result_drop_mask = {MAX_EDGES{1'b0}};
                            result_erased_edge = DROP_NONE;
                            result_pair_count = 4'd0;
                            result_determined_count = 5'd0;
                            result_live_hash = 32'd0;
                            result_cycle_count = 32'd0;
                            result_closure_count = 32'd0;
                            result_drop_trial_count = 32'd0;
                            busy = 1'b0;
                            state = ST_RESULT;
                        end else begin
                            edge_count_reg = start_edge_count;
                            central_reg = start_central;
                            max_plugs_reg = start_max_plugs;
                            exact_plugs_reg = start_exact_plugs;
                            tolerance_one = (start_tolerance == 1);
                            drop_enabled = 1'b0;
                            drop_index = DROP_NONE;
                            busy = 1'b1;
                            launch_closure();
                        end
                    end
                end

                ST_SEED_INIT: begin
                    live_valid[central_reg] = 1'b1;
                    live_values[(central_reg * 5) +: 5] = seed_reg;
                    live_valid[seed_reg] = 1'b1;
                    live_values[(seed_reg * 5) +: 5] = central_reg;
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
                        finish_result(1'b0, 1'b1);
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
                    if ((edge_cursor + 1'b1) >= edge_count_reg)
                        state = ST_PASS_END;
                    else begin
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
                        finish_result(1'b0, 1'b0);
                    end
                end

                ST_PLUG_BEGIN: begin
                    plug_cursor = 5'd0;
                    plug_pairs = 6'd0;
                    determined_count = 6'd0;
                    live_hash = FNV_OFFSET;
                    state = ST_PLUG_COUNT;
                end

                ST_PLUG_COUNT: begin
                    hash_word = 32'd0;
                    if (live_valid[plug_cursor]) begin
                        current_value = mapping_at(live_values, plug_cursor);
                        hash_word = 32'd1 << current_value;
                        determined_count = determined_count + 1'b1;
                        if (current_value != plug_cursor && plug_cursor < current_value)
                            plug_pairs = plug_pairs + 1'b1;
                    end
                    live_hash = (live_hash ^ hash_word) * FNV_PRIME;
                    if (plug_cursor == 25)
                        state = ST_PLUG_DONE;
                    else
                        plug_cursor = plug_cursor + 1'b1;
                end

                ST_PLUG_DONE: begin
                    budget_ok = 1'b1;
                    if (max_plugs_reg != 0 && plug_pairs > max_plugs_reg)
                        budget_ok = 1'b0;
                    if (exact_plugs_reg != 0) begin
                        if (plug_pairs > exact_plugs_reg) begin
                            budget_ok = 1'b0;
                        end else begin
                            free_letters = 6'd26 - determined_count;
                            required_letters = 2 * (exact_plugs_reg - plug_pairs);
                            if (free_letters < required_letters)
                                budget_ok = 1'b0;
                        end
                    end

                    if (budget_ok) begin
                        finish_result(1'b1, 1'b0);
                    end else if (!drop_enabled && tolerance_one) begin
                        drop_candidates = active_work;
                        state = ST_SELECT_DROP;
                    end else if (drop_enabled) begin
                        state = ST_SELECT_DROP;
                    end else begin
                        finish_result(1'b0, 1'b0);
                    end
                end

                ST_SELECT_DROP: begin
                    selected_drop = first_active(drop_candidates);
                    if (selected_drop == DROP_NONE) begin
                        finish_result(1'b0, 1'b0);
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
                        (edge_read_a == central_reg || edge_read_b == central_reg))
                        seed_attached = 1'b1;

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

                ST_RESULT: begin
                    if (result_valid && result_ready) begin
                        result_valid = 1'b0;
                        state = ST_IDLE;
                    end
                end

                default: begin
                    finish_result(1'b0, 1'b1);
                end
            endcase
        end
    end
endmodule

`endif

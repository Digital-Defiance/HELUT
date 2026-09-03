`ifndef MULEIN_FUTURE_TENSORLUT_TOP_SV
`define MULEIN_FUTURE_TENSORLUT_TOP_SV

// Unified Mulein Future Bank top for Yosys -> TensorLUT -> Metal
// ==============================================================
//
// One TensorLUT batch lane represents one M4 rotor setting.  Its 80x26 scrambler trail is
// supplied once in `step_rows` and selected by every bank slot.  Each slot owns only a future
// descriptor table, one central-letter seed, and mutable closure state.  BANK_LANES is swept
// at synthesis/benchmark time: wider is not assumed faster because Yosys must flatten each
// independently addressed row selector into LUT logic.
//
// Indel/splice hypotheses are already explicit geometry here: each slot receives the ordered
// (a,b,transmitted-step) descriptors produced by the Future Lattice.  Garble repair remains a
// separate exact-first one-edge erasure inside `mulein_closure_seed`.
//
// Inputs that describe a job (including edge tables and step_rows) must remain stable from an
// accepted `start` until that slot's held result is consumed.  `bank_ready` prevents overlap;
// result_ready may consume slots independently after their result_valid bit is observed.
module mulein_future_tensorlut_top #(
    parameter integer BANK_LANES = 1,
    parameter integer MAX_EDGES  = 40,
    parameter integer MAX_STEPS  = 80,
    parameter integer EDGE_BITS  = 6,
    parameter integer STEP_BITS  = 7,
    parameter integer TAG_BITS   = 32
) (
    input  wire                                  clk,
    input  wire                                  resetn,

    input  wire                                  start,
    input  wire [BANK_LANES-1:0]                 start_lane_mask,
    output wire                                  bank_ready,
    output wire                                  bank_complete,
    output reg  [BANK_LANES-1:0]                 active_mask,

    // Per-slot scalar job fields. Slot i occupies i*WIDTH +: WIDTH.
    input  wire [(BANK_LANES*EDGE_BITS)-1:0]     start_edge_counts,
    input  wire [(BANK_LANES*5)-1:0]             start_centrals,
    input  wire [(BANK_LANES*5)-1:0]             start_seeds,
    input  wire [(BANK_LANES*5)-1:0]             start_max_plugs,
    input  wire [(BANK_LANES*5)-1:0]             start_exact_plugs,
    input  wire [(BANK_LANES*2)-1:0]             start_tolerances,
    input  wire [(BANK_LANES*TAG_BITS)-1:0]      start_tags,

    // Explicit Future-Lattice geometry, private per bank slot.
    input  wire [(BANK_LANES*MAX_EDGES*5)-1:0]   edge_a_tables,
    input  wire [(BANK_LANES*MAX_EDGES*5)-1:0]   edge_b_tables,
    input  wire [(BANK_LANES*MAX_EDGES*STEP_BITS)-1:0] edge_step_tables,

    // Shared M4 work: S_t(x) occupies step_rows[(t*130)+(x*5) +: 5].
    input  wire [(MAX_STEPS*26*5)-1:0]           step_rows,

    output wire [BANK_LANES-1:0]                 busy_mask,
    output wire [BANK_LANES-1:0]                 result_valid,
    input  wire [BANK_LANES-1:0]                 result_ready,
    output wire [BANK_LANES-1:0]                 result_config_error,
    output wire [BANK_LANES-1:0]                 result_hit,
    output wire [(BANK_LANES*TAG_BITS)-1:0]      result_tags,
    output wire [(BANK_LANES*5)-1:0]             result_seeds,
    output wire [BANK_LANES-1:0]                 result_exact,
    output wire [(BANK_LANES*MAX_EDGES)-1:0]     result_drop_masks,
    output wire [(BANK_LANES*EDGE_BITS)-1:0]     result_erased_edges,
    output wire [(BANK_LANES*4)-1:0]             result_pair_counts,
    output wire [(BANK_LANES*5)-1:0]             result_determined_counts,
    output wire [(BANK_LANES*32)-1:0]            result_live_hashes,
    output wire [(BANK_LANES*32)-1:0]            result_cycle_counts,
    output wire [(BANK_LANES*32)-1:0]            result_closure_counts,
    output wire [(BANK_LANES*32)-1:0]            result_drop_trial_counts
);
    wire accepted_start;

    assign bank_ready = (active_mask == {BANK_LANES{1'b0}}) &&
                        (busy_mask == {BANK_LANES{1'b0}}) &&
                        (result_valid == {BANK_LANES{1'b0}});
    assign accepted_start = start && bank_ready;
    assign bank_complete = (active_mask != {BANK_LANES{1'b0}}) &&
                           ((result_valid & active_mask) == active_mask);

    always @(posedge clk) begin
        if (!resetn) begin
            active_mask <= {BANK_LANES{1'b0}};
        end else begin
            if (accepted_start)
                active_mask <= start_lane_mask;
            else
                // The host asserts ready only after observing the corresponding held valid.
                // Clear directly from ready so lane-local blocking assignments cannot create a
                // cross-always simulation race on the consume edge.
                active_mask <= active_mask & ~result_ready;
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < BANK_LANES; lane = lane + 1) begin : g_lane
            wire [EDGE_BITS-1:0] edge_read_index;
            wire [4:0] edge_read_a;
            wire [4:0] edge_read_b;
            wire [STEP_BITS-1:0] edge_read_step;
            wire [STEP_BITS-1:0] step_read_index;
            wire [(26*5)-1:0] step_read_row;

            localparam integer EDGE_A_BASE = lane * MAX_EDGES * 5;
            localparam integer EDGE_B_BASE = lane * MAX_EDGES * 5;
            localparam integer EDGE_STEP_BASE = lane * MAX_EDGES * STEP_BITS;

            assign edge_read_a = edge_a_tables[
                EDGE_A_BASE + (edge_read_index * 5) +: 5
            ];
            assign edge_read_b = edge_b_tables[
                EDGE_B_BASE + (edge_read_index * 5) +: 5
            ];
            assign edge_read_step = edge_step_tables[
                EDGE_STEP_BASE + (edge_read_index * STEP_BITS) +: STEP_BITS
            ];
            assign step_read_row = step_rows[
                (step_read_index * 26 * 5) +: (26 * 5)
            ];

            mulein_closure_seed #(
                .MAX_EDGES(MAX_EDGES),
                .MAX_STEPS(MAX_STEPS),
                .EDGE_BITS(EDGE_BITS),
                .STEP_BITS(STEP_BITS),
                .TAG_BITS(TAG_BITS)
            ) core (
                .clk(clk),
                .resetn(resetn),
                .edge_read_index(edge_read_index),
                .edge_read_a(edge_read_a),
                .edge_read_b(edge_read_b),
                .edge_read_step(edge_read_step),
                .step_read_index(step_read_index),
                .step_read_row(step_read_row),
                .start(accepted_start && start_lane_mask[lane]),
                .start_edge_count(start_edge_counts[(lane*EDGE_BITS) +: EDGE_BITS]),
                .start_central(start_centrals[(lane*5) +: 5]),
                .start_seed(start_seeds[(lane*5) +: 5]),
                .start_max_plugs(start_max_plugs[(lane*5) +: 5]),
                .start_exact_plugs(start_exact_plugs[(lane*5) +: 5]),
                .start_tolerance(start_tolerances[(lane*2) +: 2]),
                .start_tag(start_tags[(lane*TAG_BITS) +: TAG_BITS]),
                .busy(busy_mask[lane]),
                .result_valid(result_valid[lane]),
                .result_ready(result_ready[lane]),
                .result_config_error(result_config_error[lane]),
                .result_hit(result_hit[lane]),
                .result_tag(result_tags[(lane*TAG_BITS) +: TAG_BITS]),
                .result_seed(result_seeds[(lane*5) +: 5]),
                .result_exact(result_exact[lane]),
                .result_drop_mask(result_drop_masks[(lane*MAX_EDGES) +: MAX_EDGES]),
                .result_erased_edge(result_erased_edges[(lane*EDGE_BITS) +: EDGE_BITS]),
                .result_pair_count(result_pair_counts[(lane*4) +: 4]),
                .result_determined_count(result_determined_counts[(lane*5) +: 5]),
                .result_live_hash(result_live_hashes[(lane*32) +: 32]),
                .result_cycle_count(result_cycle_counts[(lane*32) +: 32]),
                .result_closure_count(result_closure_counts[(lane*32) +: 32]),
                .result_drop_trial_count(result_drop_trial_counts[(lane*32) +: 32])
            );
        end
    endgenerate
endmodule

`endif

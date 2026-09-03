`ifndef MULEIN_CLOSURE_BOUNDED_SV
`define MULEIN_CLOSURE_BOUNDED_SV

// Bounded shared-store adapter for circuit conformance.
//
// This module adds no closure logic. It puts the canonical Closure Core's reactive descriptor
// and S_t read ports behind packed combinational stores so Yosys, CleartextNetlistSimulator,
// and TensorLUT can execute the whole bounded circuit without a host-side memory callback.
// Production banks should still share a larger store across lanes; this four-edge/four-step
// adapter exists only for source/post-Yosys/TensorLUT equivalence and batch-shape grades.
module mulein_closure_bounded #(
    parameter integer MAX_EDGES = 4,
    parameter integer MAX_STEPS = 4,
    // Three bits are intentional: 3'b111 remains an invalid DROP_NONE sentinel while 0...3
    // are legal edge indices. EDGE_BITS=2 would collide with edge 3.
    parameter integer EDGE_BITS = 3,
    parameter integer STEP_BITS = 3
) (
    input  wire                              clk,
    input  wire                              resetn,
    input  wire                              start,
    input  wire [EDGE_BITS-1:0]              start_edge_count,
    input  wire [4:0]                        start_central,
    input  wire [4:0]                        start_max_plugs,
    input  wire [1:0]                        start_tolerance,

    // Packed little-slice tables: item i occupies bits i*WIDTH +: WIDTH.
    input  wire [(MAX_EDGES*5)-1:0]          edge_a_table,
    input  wire [(MAX_EDGES*5)-1:0]          edge_b_table,
    input  wire [(MAX_EDGES*STEP_BITS)-1:0]  edge_step_table,
    input  wire [(MAX_STEPS*26*5)-1:0]       step_rows,

    output wire                              busy,
    output wire                              done,
    output wire                              config_error,
    output wire [25:0]                       survivor_mask,
    output wire [25:0]                       erased_seed_mask,
    output wire [(26*EDGE_BITS)-1:0]         erased_edge_by_seed,
    output wire [31:0]                       cycle_count,
    output wire [31:0]                       closure_count,
    output wire [31:0]                       drop_trial_count
);
    wire [EDGE_BITS-1:0] edge_read_index;
    wire [4:0] edge_read_a;
    wire [4:0] edge_read_b;
    wire [STEP_BITS-1:0] edge_read_step;
    wire [STEP_BITS-1:0] step_read_index;
    wire [(26*5)-1:0] step_read_row;

    assign edge_read_a = edge_a_table[(edge_read_index * 5) +: 5];
    assign edge_read_b = edge_b_table[(edge_read_index * 5) +: 5];
    assign edge_read_step = edge_step_table[(edge_read_index * STEP_BITS) +: STEP_BITS];
    assign step_read_row = step_rows[(step_read_index * 26 * 5) +: (26 * 5)];

    mulein_closure_core #(
        .MAX_EDGES(MAX_EDGES),
        .MAX_STEPS(MAX_STEPS),
        .EDGE_BITS(EDGE_BITS),
        .STEP_BITS(STEP_BITS)
    ) core (
        .clk(clk),
        .resetn(resetn),
        .edge_read_index(edge_read_index),
        .edge_read_a(edge_read_a),
        .edge_read_b(edge_read_b),
        .edge_read_step(edge_read_step),
        .step_read_index(step_read_index),
        .step_read_row(step_read_row),
        .start(start),
        .start_edge_count(start_edge_count),
        .start_central(start_central),
        .start_max_plugs(start_max_plugs),
        .start_tolerance(start_tolerance),
        .busy(busy),
        .done(done),
        .config_error(config_error),
        .survivor_mask(survivor_mask),
        .erased_seed_mask(erased_seed_mask),
        .erased_edge_by_seed(erased_edge_by_seed),
        .cycle_count(cycle_count),
        .closure_count(closure_count),
        .drop_trial_count(drop_trial_count)
    );
endmodule

`endif

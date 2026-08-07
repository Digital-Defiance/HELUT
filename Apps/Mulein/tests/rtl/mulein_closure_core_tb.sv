`timescale 1ns / 1ps

// Self-checking unit tests for the scalar Mulein Closure Core.
//
// These are deliberately tiny synthetic boards rather than campaign claims. They isolate the
// hardware obligations that must hold before historical fixtures are admitted:
//   * exact closure survives when a partial involution is consistent;
//   * contradictory exact edges eliminate the selected seed;
//   * tolerance 1 removes the uniquely uncorroborated active edge;
//   * a disconnected inactive edge is never selected as the repair;
//   * physical plug-budget failure participates in tolerance branching.
module mulein_closure_core_tb;
    localparam integer MAX_EDGES = 40;
    localparam integer MAX_STEPS = 80;
    localparam integer EDGE_BITS = 6;
    localparam integer STEP_BITS = 7;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    // The scalar lane owns no descriptor or scrambler memory. This testbench models the
    // bank-level shared stores and returns both reads combinationally.
    wire [EDGE_BITS-1:0]         edge_read_index;
    wire [4:0]                   edge_read_a;
    wire [4:0]                   edge_read_b;
    wire [STEP_BITS-1:0]         edge_read_step;
    wire [STEP_BITS-1:0]         step_read_index;
    wire [(26*5)-1:0]            step_read_row;

    reg [4:0]                    edge_a_store [0:MAX_EDGES-1];
    reg [4:0]                    edge_b_store [0:MAX_EDGES-1];
    reg [STEP_BITS-1:0]          edge_step_store [0:MAX_EDGES-1];
    reg [(26*5)-1:0]             step_store [0:MAX_STEPS-1];

    assign edge_read_a = edge_a_store[edge_read_index];
    assign edge_read_b = edge_b_store[edge_read_index];
    assign edge_read_step = edge_step_store[edge_read_index];
    assign step_read_row = step_store[step_read_index];

    reg                          start = 1'b0;
    reg [EDGE_BITS-1:0]          start_edge_count = 0;
    reg [4:0]                    start_central = 0;
    reg [4:0]                    start_max_plugs = 0;
    reg [1:0]                    start_tolerance = 0;

    wire                         busy;
    wire                         done;
    wire                         config_error;
    wire [25:0]                  survivor_mask;
    wire [25:0]                  erased_seed_mask;
    wire [(26*EDGE_BITS)-1:0]    erased_edge_by_seed;
    wire [31:0]                  cycle_count;
    wire [31:0]                  closure_count;
    wire [31:0]                  drop_trial_count;

    mulein_closure_core #(
        .MAX_EDGES(MAX_EDGES),
        .MAX_STEPS(MAX_STEPS),
        .EDGE_BITS(EDGE_BITS),
        .STEP_BITS(STEP_BITS)
    ) dut (
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

    integer errors = 0;
    integer k;
    integer wait_cycles;

    function automatic [EDGE_BITS-1:0] erased_edge;
        input integer seed;
        begin
            erased_edge = erased_edge_by_seed[(seed*EDGE_BITS) +: EDGE_BITS];
        end
    endfunction

    task automatic check_condition;
        input condition;
        input string message;
        begin
            // A four-state unknown is a test failure, never an implicit pass.
            if (condition !== 1'b1) begin
                $display("FAIL: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic write_edge;
        input integer index;
        input integer a;
        input integer b;
        input integer step;
        begin
            edge_a_store[index] = a[4:0];
            edge_b_store[index] = b[4:0];
            edge_step_store[index] = step[STEP_BITS-1:0];
        end
    endtask

    // Store an involution that is identity except for x<->y. x==y stores identity.
    task automatic write_step_swap;
        input integer step;
        input integer x;
        input integer y;
        integer value;
        begin
            step_store[step] = {(26*5){1'b0}};
            for (k = 0; k < 26; k = k + 1) begin
                value = k;
                if (k == x)
                    value = y;
                else if (k == y)
                    value = x;
                step_store[step][(k*5) +: 5] = value[4:0];
            end
        end
    endtask

    task automatic run_job;
        input integer edge_count;
        input integer central;
        input integer max_plugs;
        input integer tolerance;
        begin
            @(negedge clk);
            start_edge_count = edge_count[EDGE_BITS-1:0];
            start_central = central[4:0];
            start_max_plugs = max_plugs[4:0];
            start_tolerance = tolerance[1:0];
            start = 1'b1;
            @(posedge clk);
            #1;
            check_condition(busy === 1'b1, "valid start did not assert busy");
            @(negedge clk);
            start = 1'b0;

            wait_cycles = 0;
            while (done !== 1'b1 && wait_cycles < 500000) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
            end
            if (done !== 1'b1) begin
                $display("FAIL: timeout after %0d cycles", wait_cycles);
                errors = errors + 1;
            end
            check_condition(config_error === 1'b0,
                            "core raised config_error on a valid fixture");
            check_condition(busy === 1'b0, "busy remained asserted at completion");

            // done is a pulse, not a sticky level.
            @(posedge clk);
            #1;
            check_condition(done === 1'b0, "done was not a one-cycle pulse");
        end
    endtask

    task automatic run_invalid_job;
        begin
            @(negedge clk);
            start_edge_count = 0;
            start_central = 0;
            start_max_plugs = 0;
            start_tolerance = 0;
            start = 1'b1;
            @(posedge clk);
            #1;
            check_condition(done === 1'b1, "invalid job did not complete immediately");
            check_condition(config_error === 1'b1, "invalid job did not raise config_error");
            check_condition(busy === 1'b0, "invalid job incorrectly asserted busy");
            @(negedge clk);
            start = 1'b0;
            @(posedge clk);
            #1;
            check_condition(done === 1'b0, "invalid-job done pulse was sticky");
        end
    endtask

    task automatic load_overplug_fixture;
        begin
            // Desired seed mapping is sigma(0)=1, sigma(1)=0.
            // Edge 0 additionally forces sigma(2)=3, sigma(3)=2 through S_0(1)=3,
            // producing two plug pairs. Edge 1 corroborates the seed pair and keeps central
            // letter 0 attached if edge 0 is erased.
            write_step_swap(0, 1, 3);
            write_step_swap(1, 0, 1);
            write_edge(0, 0, 2, 0);
            write_edge(1, 0, 1, 1);
        end
    endtask

    task automatic load_contradiction_fixture;
        begin
            // Edges 0 and 1 agree that seed sigma(0)=0 implies sigma(1)=1.
            // Edge 2 instead demands sigma(1)=2. Edge 1 is corroborating and therefore
            // inactive in the root failure; edge 3 is disconnected and inactive.
            write_step_swap(0, 0, 1);
            write_step_swap(1, 0, 2);
            write_step_swap(2, 4, 5);
            write_edge(0, 0, 1, 0);
            write_edge(1, 0, 1, 0);
            write_edge(2, 0, 1, 1);
            write_edge(3, 4, 5, 2);
        end
    endtask

    task automatic load_seed_25_fixture;
        begin
            // Exercise the highest seed provenance slot and highest legal trail address.
            // Two edges demand sigma(1)=1 for seed 25; edge 2 demands sigma(1)=2.
            write_step_swap(MAX_STEPS - 1, 25, 1);
            write_step_swap(MAX_STEPS - 2, 25, 2);
            write_step_swap(MAX_STEPS - 3, 4, 5);
            write_edge(0, 0, 1, MAX_STEPS - 1);
            write_edge(1, 0, 1, MAX_STEPS - 1);
            write_edge(2, 0, 1, MAX_STEPS - 2);
            write_edge(3, 4, 5, MAX_STEPS - 3);
        end
    endtask

    initial begin
        resetn = 1'b0;
        repeat (4) @(posedge clk);
        check_condition(busy === 1'b0, "busy was unknown or high during reset");
        check_condition(done === 1'b0, "done was unknown or high during reset");
        check_condition(config_error === 1'b0,
                        "config_error was unknown or high during reset");
        @(negedge clk);
        resetn = 1'b1;

        // Reject malformed work and prove the next valid start clears the error.
        run_invalid_job();

        // Expected masks below were independently derived with a blind all-single-edge model.
        load_overplug_fixture();

        // 1. Exact consistent closure: only seed 1 survives with two physical plug pairs.
        run_job(2, 0, 2, 0);
        check_condition(survivor_mask === 26'h0000002,
                        "exact fixture survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h0000000,
                        "exact fixture reported erased survivors");
        check_condition(erased_edge_by_seed === {(26*EDGE_BITS){1'b1}},
                        "exact fixture changed default erasure provenance");
        check_condition(closure_count === 32'd26,
                        "tolerance-0 job did not run one closure per seed");

        // 2. Tolerance remains exact-first: seed 1 stays exact while seed 0 is repaired.
        run_job(2, 0, 2, 1);
        check_condition(survivor_mask === 26'h000000b,
                        "exact-first tolerance survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h0000009,
                        "exact-first tolerance erasure mask differs from blind model");
        check_condition(erased_seed_mask[1] === 1'b0,
                        "exact seed 1 was needlessly marked as erased");
        check_condition(erased_edge(0) == 0 && erased_edge(3) == 1,
                        "exact-first repairs did not retain their erased edges");

        // 3. The same exact closure is physically over budget at max_plugs=1.
        run_job(2, 0, 1, 0);
        check_condition(survivor_mask === 26'h0000000,
                        "over-plug exact fixture produced survivors");
        check_condition(erased_seed_mask === 26'h0000000,
                        "tolerance-0 fixture reported erasure provenance");

        // 4. Budget failure enters tolerance branching for seeds 0 and 1.
        run_job(2, 0, 1, 1);
        check_condition(survivor_mask === 26'h0000003,
                        "budget-repair survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h0000003,
                        "budget-repair erasure mask differs from blind model");
        check_condition(erased_edge(0) == 0 && erased_edge(1) == 0,
                        "budget repair did not identify active edge 0");
        check_condition(drop_trial_count > 0, "tolerance job reported no drop trials");

        // 5. Contradictory exact board has no surviving central-letter seed.
        load_contradiction_fixture();
        run_job(4, 0, 10, 0);
        check_condition(survivor_mask === 26'h0000000,
                        "contradictory exact fixture produced survivors");

        // 6. Only deleting active edge 2 repairs seeds 0 and 1. The disconnected edge 3
        // is absent from the exact active set and cannot appear as provenance.
        run_job(4, 0, 10, 1);
        check_condition(survivor_mask === 26'h0000003,
                        "contradiction-repair survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h0000003,
                        "contradiction-repair erasure mask differs from blind model");
        check_condition(erased_edge(0) == 2 && erased_edge(1) == 2,
                        "repair did not isolate bad active edge 2");
        check_condition(erased_edge(0) != 3 && erased_edge(1) != 3,
                        "inactive disconnected edge 3 was selected");

        // 7. Seed 25 exercises the top survivor bit, top packed provenance slice, and step 79.
        load_seed_25_fixture();
        run_job(4, 0, 10, 0);
        check_condition(survivor_mask === 26'h0000000,
                        "high-index contradiction unexpectedly survived exact closure");
        run_job(4, 0, 10, 1);
        check_condition(survivor_mask === 26'h2000000,
                        "seed-25 repair survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h2000000,
                        "seed-25 repair erasure mask differs from blind model");
        check_condition(erased_edge(25) == 2,
                        "highest packed provenance slot did not retain edge 2");

        if (errors == 0) begin
            $display("PASS: Mulein Closure Core protocol, exact-first, active-erasure, plug-budget, and high-index tests");
            $finish;
        end else begin
            $fatal(1, "Mulein Closure Core testbench recorded %0d error(s)", errors);
        end
    end
endmodule

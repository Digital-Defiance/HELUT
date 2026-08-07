// Source/post-Yosys receipt fixture for the bounded Mulein Closure Core adapter.
//
// The same testbench is compiled once against the canonical source hierarchy and once against
// Yosys' LUT6-mapped write_verilog output. RECEIPT lines are byte-compared by the Swift
// TensorLUT grade. The vectors are synthetic controls, never campaign evidence.
module mulein_closure_bounded_tb;
    localparam integer MAX_EDGES = 4;
    localparam integer MAX_STEPS = 4;
    localparam integer EDGE_BITS = 3;
    localparam integer STEP_BITS = 3;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg start = 1'b0;
    always #5 clk = ~clk;

    reg [EDGE_BITS-1:0] start_edge_count = 0;
    reg [4:0] start_central = 0;
    reg [4:0] start_max_plugs = 0;
    reg [1:0] start_tolerance = 0;
    reg [(MAX_EDGES*5)-1:0] edge_a_table = 0;
    reg [(MAX_EDGES*5)-1:0] edge_b_table = 0;
    reg [(MAX_EDGES*STEP_BITS)-1:0] edge_step_table = 0;
    reg [(MAX_STEPS*26*5)-1:0] step_rows = 0;

    wire busy;
    wire done;
    wire config_error;
    wire [25:0] survivor_mask;
    wire [25:0] erased_seed_mask;
    wire [(26*EDGE_BITS)-1:0] erased_edge_by_seed;
    wire [31:0] cycle_count;
    wire [31:0] closure_count;
    wire [31:0] drop_trial_count;

    mulein_closure_bounded dut (
        .clk(clk), .resetn(resetn), .start(start),
        .start_edge_count(start_edge_count),
        .start_central(start_central),
        .start_max_plugs(start_max_plugs),
        .start_tolerance(start_tolerance),
        .edge_a_table(edge_a_table),
        .edge_b_table(edge_b_table),
        .edge_step_table(edge_step_table),
        .step_rows(step_rows),
        .busy(busy), .done(done), .config_error(config_error),
        .survivor_mask(survivor_mask),
        .erased_seed_mask(erased_seed_mask),
        .erased_edge_by_seed(erased_edge_by_seed),
        .cycle_count(cycle_count),
        .closure_count(closure_count),
        .drop_trial_count(drop_trial_count)
    );

    integer errors = 0;
    integer wait_cycles;
    integer k;

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
            if (condition !== 1'b1) begin
                $display("FAIL: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic clear_tables;
        begin
            edge_a_table = 0;
            edge_b_table = 0;
            edge_step_table = 0;
            step_rows = 0;
        end
    endtask

    task automatic write_edge;
        input integer index;
        input integer a;
        input integer b;
        input integer step;
        begin
            edge_a_table[(index*5) +: 5] = a[4:0];
            edge_b_table[(index*5) +: 5] = b[4:0];
            edge_step_table[(index*STEP_BITS) +: STEP_BITS] = step[STEP_BITS-1:0];
        end
    endtask

    task automatic write_step_swap;
        input integer step;
        input integer x;
        input integer y;
        integer value;
        begin
            for (k = 0; k < 26; k = k + 1) begin
                value = k;
                if (k == x)
                    value = y;
                else if (k == y)
                    value = x;
                step_rows[(step*26*5) + (k*5) +: 5] = value[4:0];
            end
        end
    endtask

    task automatic load_overplug_fixture;
        begin
            clear_tables();
            write_step_swap(0, 1, 3);
            write_step_swap(1, 0, 1);
            write_edge(0, 0, 2, 0);
            write_edge(1, 0, 1, 1);
        end
    endtask

    task automatic load_contradiction_fixture;
        begin
            clear_tables();
            write_step_swap(0, 0, 1);
            write_step_swap(1, 0, 2);
            write_step_swap(2, 4, 5);
            write_edge(0, 0, 1, 0);
            write_edge(1, 0, 1, 0);
            write_edge(2, 0, 1, 1);
            write_edge(3, 4, 5, 2);
        end
    endtask

    task automatic load_negative_control_fixture;
        begin
            // One S_t row is changed so the formerly contradictory third edge agrees with
            // the first two. A harness that reads the wrong packed row would miss this.
            load_contradiction_fixture();
            write_step_swap(1, 0, 1);
        end
    endtask

    task automatic load_contradiction_drop_fixture;
        input integer dropped;
        integer read_index;
        integer write_index;
        begin
            load_contradiction_fixture();
            write_index = 0;
            for (read_index = 0; read_index < MAX_EDGES; read_index = read_index + 1) begin
                if (read_index != dropped) begin
                    edge_a_table[(write_index*5) +: 5]
                        = edge_a_table[(read_index*5) +: 5];
                    edge_b_table[(write_index*5) +: 5]
                        = edge_b_table[(read_index*5) +: 5];
                    edge_step_table[(write_index*STEP_BITS) +: STEP_BITS]
                        = edge_step_table[(read_index*STEP_BITS) +: STEP_BITS];
                    write_index = write_index + 1;
                end
            end
            edge_a_table[(3*5) +: 5] = 0;
            edge_b_table[(3*5) +: 5] = 0;
            edge_step_table[(3*STEP_BITS) +: STEP_BITS] = 0;
        end
    endtask

    task automatic run_job;
        input string name;
        input integer edge_count;
        input integer max_plugs;
        input integer tolerance;
        begin
            @(negedge clk);
            start_edge_count = edge_count[EDGE_BITS-1:0];
            start_central = 5'd0;
            start_max_plugs = max_plugs[4:0];
            start_tolerance = tolerance[1:0];
            start = 1'b1;
            @(posedge clk);
            #1;
            check_condition(busy === 1'b1, "valid bounded job did not assert busy");
            @(negedge clk);
            start = 1'b0;

            wait_cycles = 0;
            while (done !== 1'b1 && wait_cycles < 200000) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
            end
            check_condition(done === 1'b1, "bounded job timed out");
            check_condition(busy === 1'b0, "bounded job remained busy at done");
            check_condition(config_error === 1'b0, "bounded fixture raised config_error");
            $display("RECEIPT %s survivor=%07h erased=%07h provenance=%020h cycles=%08h closures=%08h drops=%08h error=%01h",
                     name, survivor_mask, erased_seed_mask, erased_edge_by_seed,
                     cycle_count, closure_count, drop_trial_count, config_error);
            @(posedge clk);
            #1;
            check_condition(done === 1'b0, "bounded done pulse was sticky");
        end
    endtask

    initial begin
        resetn = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        load_overplug_fixture();
        run_job("overplug_exact", 2, 2, 0);
        check_condition(survivor_mask === 26'h0000002,
                        "bounded exact survivor mask differs from blind model");
        check_condition(erased_seed_mask === 0,
                        "bounded exact job reported erasure");

        load_overplug_fixture();
        run_job("overplug_repair", 2, 1, 1);
        check_condition(survivor_mask === 26'h0000003,
                        "bounded budget-repair survivor mask differs from blind model");
        check_condition(erased_seed_mask === 26'h0000003,
                        "bounded budget-repair erasure mask differs from blind model");
        check_condition(erased_edge(0) == 0 && erased_edge(1) == 0,
                        "bounded budget repair lost edge-0 provenance");

        load_contradiction_fixture();
        run_job("contradiction_exact", 4, 10, 0);
        check_condition(survivor_mask === 0,
                        "bounded contradictory exact board survived");

        load_contradiction_fixture();
        run_job("contradiction_repair", 4, 10, 1);
        check_condition(survivor_mask === 26'h0000003,
                        "bounded contradiction repair differs from blind model");
        check_condition(erased_seed_mask === 26'h0000003,
                        "bounded contradiction repair lost erasure mask");
        check_condition(erased_edge(0) == 2 && erased_edge(1) == 2,
                        "bounded contradiction repair lost edge-2 provenance");

        // 5-8. Materialize every one-edge future from the four-edge contradiction menu.
        // Each exact job still evaluates all 26 central seeds; only removal of edge 2 repairs
        // the board. This is the finite future set the Swift/TensorLUT batch cross-check uses.
        load_contradiction_drop_fixture(0);
        run_job("contradiction_drop_0", 3, 10, 0);
        check_condition(survivor_mask === 0, "drop-0 future unexpectedly survived");

        load_contradiction_drop_fixture(1);
        run_job("contradiction_drop_1", 3, 10, 0);
        check_condition(survivor_mask === 0, "drop-1 future unexpectedly survived");

        load_contradiction_drop_fixture(2);
        run_job("contradiction_drop_2", 3, 10, 0);
        check_condition(survivor_mask === 26'h0000003,
                        "drop-2 future did not recover both expected seeds");

        load_contradiction_drop_fixture(3);
        run_job("contradiction_drop_3", 3, 10, 0);
        check_condition(survivor_mask === 0, "drop-3 future unexpectedly survived");

        load_negative_control_fixture();
        run_job("row_mutation_control", 4, 10, 0);
        check_condition(survivor_mask === 26'h0000003,
                        "changed S_t row was not observed by bounded adapter");
        check_condition(erased_seed_mask === 0,
                        "row-mutation exact control reported erasure");

        if (errors == 0) begin
            $display("PASS: bounded source/post-Yosys receipt fixtures");
            $finish;
        end else begin
            $fatal(1, "bounded receipt fixture recorded %0d error(s)", errors);
        end
    end
endmodule

// Sequential E256-H H4 switching-sequence integrated-core testbenches.
//
// Contract: directives/e256-hardware-h4-sequence-preregistration.json
// RTL:      Hardware/RTL/Research/E256H/e256h_h4_sequence_core.v
//
// The preregistration does not freeze vector filenames, raw row grammar,
// completion sentinels, or numeric mutation codes.  This local runner ABI keeps
// the predecessor H2 conventions while making every executed/nonexecuted slot
// explicit:
//
//   build/e256h-h4-sequence/masks.hex
//   build/e256h-h4-sequence/h4-sequences.hex
//   build/e256h-h4-sequence/live-h4-sequences.hex
//   build/e256h-h4-sequence/blocks.hex
//   build/e256h-h4-sequence/results.txt
//
// Full-corpus configuration order is executable schedule (d outer, then a),
// then the three material sets.  A main row has exactly nineteen tokens:
//   rtl <config> <block> <a> <d> <sequence> <run-mask>
//       <four outputs> <four latencies> <four initiation intervals>
// Variant order is ff_repeated, ff_sequence, ring_repeated, ring_sequence.
// A '-' is mandatory for every unexecuted repeated slot on d=1 rows.
//
// The Python runner independently derives all expected cryptographic values.
// This TB checks handshakes, exact latency/earliest-II evidence, FF/ring
// equality, repeated/sequence bridges, malformed configuration behavior, and
// committed-selector independence from changed external pins.

`default_nettype none
`timescale 1ns / 1ps

module e256h_h4_sequence_core_tb #(
    parameter integer CONFIG_COUNT = 1,
    parameter integer MATERIAL_COUNT = 3,
    parameter [8*160-1:0] MASKS_FILE =
        "build/e256h-h4-sequence/masks.hex",
    parameter [8*160-1:0] SEQUENCES_FILE =
        "build/e256h-h4-sequence/h4-sequences.hex",
    parameter [8*160-1:0] LIVE_SEQUENCES_FILE =
        "build/e256h-h4-sequence/live-h4-sequences.hex",
    parameter [8*160-1:0] BLOCKS_FILE =
        "build/e256h-h4-sequence/blocks.hex",
    parameter [8*160-1:0] RESULTS_FILE =
        "build/e256h-h4-sequence/results.txt"
);
  localparam integer BLOCK_COUNT = 8;

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [255:0] mask_words [0:CONFIG_COUNT*13-1];
  reg [143:0] sequences [0:CONFIG_COUNT-1];
  reg [143:0] live_sequences [0:CONFIG_COUNT-1];
  reg [255:0] blocks [0:BLOCK_COUNT-1];

  reg          cfg_begin;
  reg          cfg_valid;
  reg  [255:0] cfg_word;
  reg          cfg_commit;
  reg  [143:0] cfg_h4_sequence;
  reg  [3:0]   starts;
  reg  [255:0] block_i;

  wire [3:0] cfg_ready_bus;
  wire [3:0] key_valid_bus;
  wire [3:0] cfg_error_bus;
  wire [3:0] ready_bus;
  wire [3:0] busy_bus;
  wire [3:0] done_bus;

  wire [255:0] ff_repeated_o;
  wire [255:0] ff_sequence_o;
  wire [255:0] ring_repeated_o;
  wire [255:0] ring_sequence_o;

  integer cycle_counter;
  integer results_fd;
  integer config_index;
  integer block_index;

  always @(posedge clk) begin
    if (rst) begin
      cycle_counter <= 0;
    end else begin
      cycle_counter <= cycle_counter + 1;
    end
  end

  e256h_h4_ff_repeated u_ff_repeated (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[0]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
      .key_valid(key_valid_bus[0]), .cfg_error(cfg_error_bus[0]),
      .start(starts[0]), .ready(ready_bus[0]), .block_i(block_i),
      .block_o(ff_repeated_o), .busy(busy_bus[0]), .done(done_bus[0])
  );

  e256h_h4_ff_sequence u_ff_sequence (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[1]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
      .key_valid(key_valid_bus[1]), .cfg_error(cfg_error_bus[1]),
      .start(starts[1]), .ready(ready_bus[1]), .block_i(block_i),
      .block_o(ff_sequence_o), .busy(busy_bus[1]), .done(done_bus[1])
  );

  e256h_h4_ring_repeated u_ring_repeated (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[2]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
      .key_valid(key_valid_bus[2]), .cfg_error(cfg_error_bus[2]),
      .start(starts[2]), .ready(ready_bus[2]), .block_i(block_i),
      .block_o(ring_repeated_o), .busy(busy_bus[2]), .done(done_bus[2])
  );

  e256h_h4_ring_sequence u_ring_sequence (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[3]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4_sequence(cfg_h4_sequence),
      .key_valid(key_valid_bus[3]), .cfg_error(cfg_error_bus[3]),
      .start(starts[3]), .ready(ready_bus[3]), .block_i(block_i),
      .block_o(ring_sequence_o), .busy(busy_bus[3]), .done(done_bus[3])
  );

  task automatic write_state_hex(
      input integer handle,
      input [255:0] value
  );
    integer lane;
    begin
      for (lane = 0; lane < 32; lane = lane + 1) begin
        $fwrite(handle, "%02x", value[8*lane +: 8]);
      end
    end
  endtask

  task automatic load_words(
      input integer selected_config,
      input integer word_count
  );
    integer word_index;
    begin
      for (word_index = 0; word_index < word_count;
           word_index = word_index + 1) begin
        @(negedge clk);
        if (cfg_ready_bus !== 4'hf) begin
          $fatal(1, "cfg_ready missing config=%0d word=%0d ready=%x",
                 selected_config, word_index, cfg_ready_bus);
        end
        cfg_word = mask_words[selected_config*13+word_index];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;
      end
    end
  endtask

  task automatic configure_all(input integer selected_config);
    begin
      @(negedge clk);
      cfg_h4_sequence = sequences[selected_config];
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_ready_bus !== 4'hf || key_valid_bus !== 4'h0 ||
          cfg_error_bus !== 4'h0) begin
        $fatal(1, "bad begin config=%0d ready=%x key=%x err=%x",
               selected_config, cfg_ready_bus, key_valid_bus, cfg_error_bus);
      end
      load_words(selected_config, 13);
      #1;
      if (cfg_ready_bus !== 4'h0) begin
        $fatal(1, "cfg_ready high after thirteen words: %x", cfg_ready_bus);
      end
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (key_valid_bus !== 4'hf || cfg_error_bus !== 4'h0 ||
          ready_bus !== 4'hf) begin
        $fatal(1, "bad commit config=%0d key=%x err=%x ready=%x",
               selected_config, key_valid_bus, cfg_error_bus, ready_bus);
      end
      if (live_sequences[selected_config] === sequences[selected_config]) begin
        $fatal(1, "live pin control sequence did not change config=%0d",
               selected_config);
      end
      // Positive evidence for commit sampling: all main runs occur after this
      // pin change and must still match the committed independent model.
      cfg_h4_sequence = live_sequences[selected_config];
    end
  endtask

  task automatic run_protocol_controls;
    integer seen;
    integer timeout;
    begin
      // Commit after twelve words and then attempt a start.
      @(negedge clk);
      cfg_h4_sequence = sequences[0];
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      load_words(0, 12);
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (cfg_error_bus !== 4'hf || key_valid_bus !== 4'h0 ||
          ready_bus !== 4'h0) begin
        $fatal(1, "incomplete configuration was not rejected");
      end
      @(negedge clk);
      starts = 4'hf;
      @(negedge clk);
      starts = 4'h0;
      seen = done_bus;
      if (busy_bus !== 4'h0) begin
        $fatal(1, "invalid start asserted busy");
      end
      for (timeout = 0; timeout < 16; timeout = timeout + 1) begin
        @(negedge clk);
        seen = seen | done_bus;
        if (busy_bus !== 4'h0) begin
          $fatal(1, "invalid start later asserted busy");
        end
      end
      if (seen != 0 || cfg_error_bus !== 4'hf || key_valid_bus !== 4'h0) begin
        $fatal(1, "incomplete configuration produced activity");
      end

      // Shared begin/start beat cannot launch under an old committed state.
      configure_all(0);
      @(negedge clk);
      block_i = blocks[0];
      cfg_begin = 1'b1;
      starts = 4'hf;
      @(negedge clk);
      cfg_begin = 1'b0;
      starts = 4'h0;
      seen = done_bus;
      if (busy_bus !== 4'h0) begin
        $fatal(1, "begin/start collision asserted busy");
      end
      for (timeout = 0; timeout < 16; timeout = timeout + 1) begin
        @(negedge clk);
        seen = seen | done_bus;
      end
      if (seen != 0 || cfg_error_bus !== 4'hf || key_valid_bus !== 4'h0) begin
        $fatal(1, "begin/start collision was not rejected");
      end

      // Busy-time configuration must set error without disturbing completion.
      configure_all(0);
      @(negedge clk);
      block_i = blocks[0];
      starts = 4'hf;
      @(negedge clk);
      starts = 4'h0;
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_error_bus !== 4'hf || key_valid_bus !== 4'hf) begin
        $fatal(1, "busy-time configuration control did not fire");
      end
      seen = 0;
      timeout = 0;
      while (seen != 4'hf) begin
        @(negedge clk);
        seen = seen | done_bus;
        timeout = timeout + 1;
        if (timeout > 20) begin
          $fatal(1, "busy-time configuration control timed out");
        end
      end
      if (busy_bus !== 4'h0) begin
        $fatal(1, "busy-time configuration disturbed completion");
      end
    end
  endtask

  task automatic run_configuration_and_write(
      input integer selected_config
  );
    integer schedule_index;
    integer selected_a;
    integer selected_d;
    integer selected_block;
    integer current_accept_cycle;
    integer previous_accept_cycle;
    integer next_accept_cycle;
    integer measured_interval;
    integer timeout;
    integer variant_index;
    integer latencies [0:3];
    integer intervals [0:3];
    reg [3:0] run_mask;
    reg [3:0] seen;
    begin
      schedule_index = selected_config / MATERIAL_COUNT;
      selected_a = schedule_index % 384;
      selected_d = schedule_index / 384;
      if (selected_d < 0 || selected_d > 1) begin
        $fatal(1, "configuration outside executable d set: %0d", selected_d);
      end
      run_mask = (selected_d == 0) ? 4'hf : 4'ha;

      // Launch the first block after configuration.  Every later block is
      // driven at the completion negedge below and accepted on the immediately
      // following edge, so initiation intervals are measured, not inferred.
      @(negedge clk);
      if (ready_bus !== 4'hf || busy_bus !== 4'h0) begin
        $fatal(1, "not ready config=%0d block=0 ready=%x busy=%x",
               selected_config, ready_bus, busy_bus);
      end
      block_i = blocks[0];
      starts = run_mask;
      @(negedge clk);
      starts = 4'h0;
      current_accept_cycle = cycle_counter;
      previous_accept_cycle = -1;
      if ((busy_bus & run_mask) !== run_mask ||
          (ready_bus & run_mask) !== 4'h0) begin
        $fatal(1, "accept mismatch config=%0d block=0 run=%x",
               selected_config, run_mask);
      end

      for (selected_block = 0; selected_block < BLOCK_COUNT;
           selected_block = selected_block + 1) begin
        seen = 4'h0;
        timeout = 0;
        for (variant_index = 0; variant_index < 4;
             variant_index = variant_index + 1) begin
          latencies[variant_index] = -1;
          intervals[variant_index] = -1;
        end

        while ((seen & run_mask) != run_mask) begin
          @(negedge clk);
          for (variant_index = 0; variant_index < 4;
               variant_index = variant_index + 1) begin
            if (run_mask[variant_index] && !seen[variant_index]) begin
              if (done_bus[variant_index]) begin
                if (!ready_bus[variant_index] || busy_bus[variant_index]) begin
                  $fatal(1, "completion ready/busy mismatch config=%0d block=%0d variant=%0d",
                         selected_config, selected_block, variant_index);
                end
                latencies[variant_index] =
                    cycle_counter - current_accept_cycle;
                seen[variant_index] = 1'b1;
              end else if (ready_bus[variant_index] ||
                           !busy_bus[variant_index]) begin
                $fatal(1, "early ready/busy release config=%0d block=%0d variant=%0d cycle=%0d",
                       selected_config, selected_block, variant_index,
                       cycle_counter - current_accept_cycle);
              end
            end
          end
          timeout = timeout + 1;
          if (timeout > 20) begin
            $fatal(1, "run timed out config=%0d block=%0d seen=%x run=%x",
                   selected_config, selected_block, seen, run_mask);
          end
        end

        if (selected_block + 1 < BLOCK_COUNT) begin
          if ((ready_bus & run_mask) !== run_mask ||
              (busy_bus & run_mask) !== 4'h0) begin
            $fatal(1, "successor not ready at done config=%0d block=%0d",
                   selected_config, selected_block);
          end
          // Assert the successor on the same negedge that observed done.  The
          // following positive edge is therefore the earliest accepted edge.
          block_i = blocks[selected_block + 1];
          starts = run_mask;
          @(negedge clk);
          starts = 4'h0;
          next_accept_cycle = cycle_counter;
          if ((busy_bus & run_mask) !== run_mask ||
              (ready_bus & run_mask) !== 4'h0) begin
            $fatal(1, "successor accept mismatch config=%0d block=%0d run=%x",
                   selected_config, selected_block + 1, run_mask);
          end
          measured_interval = next_accept_cycle - current_accept_cycle;
        end else begin
          // Do not add an out-of-corpus probe.  The final row uses its actual
          // incoming accepted-start gap, measured when block 7 was launched.
          if (previous_accept_cycle < 0) begin
            $fatal(1, "missing final-row predecessor acceptance");
          end
          measured_interval =
              current_accept_cycle - previous_accept_cycle;
        end

        for (variant_index = 0; variant_index < 4;
             variant_index = variant_index + 1) begin
          if (run_mask[variant_index]) begin
            intervals[variant_index] = measured_interval;
            if (latencies[variant_index] != 12 ||
                intervals[variant_index] != 13) begin
              $fatal(1, "cycle mismatch config=%0d block=%0d variant=%0d latency=%0d ii=%0d",
                     selected_config, selected_block, variant_index,
                     latencies[variant_index], intervals[variant_index]);
            end
          end
        end

        if (ff_sequence_o !== ring_sequence_o) begin
          $fatal(1, "sequence storage mismatch config=%0d block=%0d",
                 selected_config, selected_block);
        end
        if (selected_d == 0) begin
          if (ff_repeated_o !== ring_repeated_o) begin
            $fatal(1, "repeated storage mismatch config=%0d block=%0d",
                   selected_config, selected_block);
          end
          if (ff_repeated_o !== ff_sequence_o ||
              ring_repeated_o !== ring_sequence_o) begin
            $fatal(1, "repeated/sequence bridge mismatch config=%0d block=%0d",
                   selected_config, selected_block);
          end
        end

        $fwrite(results_fd, "rtl %0d %0d %0d %0d %036x %02x",
                selected_config, selected_block, selected_a, selected_d,
                sequences[selected_config], run_mask);
        for (variant_index = 0; variant_index < 4;
             variant_index = variant_index + 1) begin
          $fwrite(results_fd, " ");
          if (!run_mask[variant_index]) begin
            $fwrite(results_fd, "-");
          end else begin
            case (variant_index)
              0: write_state_hex(results_fd, ff_repeated_o);
              1: write_state_hex(results_fd, ff_sequence_o);
              2: write_state_hex(results_fd, ring_repeated_o);
              default: write_state_hex(results_fd, ring_sequence_o);
            endcase
          end
        end
        for (variant_index = 0; variant_index < 4;
             variant_index = variant_index + 1) begin
          if (run_mask[variant_index]) begin
            $fwrite(results_fd, " %0d", latencies[variant_index]);
          end else begin
            $fwrite(results_fd, " -");
          end
        end
        for (variant_index = 0; variant_index < 4;
             variant_index = variant_index + 1) begin
          if (run_mask[variant_index]) begin
            $fwrite(results_fd, " %0d", intervals[variant_index]);
          end else begin
            $fwrite(results_fd, " -");
          end
        end
        $fwrite(results_fd, "\n");

        if (selected_block + 1 < BLOCK_COUNT) begin
          previous_accept_cycle = current_accept_cycle;
          current_accept_cycle = next_accept_cycle;
        end
      end
    end
  endtask

  initial begin
    if (CONFIG_COUNT < 1 || MATERIAL_COUNT != 3) begin
      $fatal(1, "invalid configuration/material count");
    end
    $readmemh(MASKS_FILE, mask_words);
    $readmemh(SEQUENCES_FILE, sequences);
    $readmemh(LIVE_SEQUENCES_FILE, live_sequences);
    $readmemh(BLOCKS_FILE, blocks);

    cfg_begin = 1'b0;
    cfg_valid = 1'b0;
    cfg_word = 256'd0;
    cfg_commit = 1'b0;
    cfg_h4_sequence = 144'd0;
    starts = 4'h0;
    block_i = 256'd0;
    cycle_counter = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    results_fd = $fopen(RESULTS_FILE, "w");
    if (results_fd == 0) begin
      $fatal(1, "could not open H4 sequence results: %0s", RESULTS_FILE);
    end

    run_protocol_controls();

    for (config_index = 0; config_index < CONFIG_COUNT;
         config_index = config_index + 1) begin
      configure_all(config_index);
      run_configuration_and_write(config_index);
    end

    $fclose(results_fd);
    $display("E256H_H4_SEQUENCE_CORE_TB_DONE");
    $finish;
  end
endmodule

// One parameterized RTL-control run.  All eight blocks execute for each
// supplied configuration.  The runner supplies transformed mask files for
// mutation 8 and an alternate valid sequence pin image for mutation 7.
module e256h_h4_sequence_control_tb #(
    parameter integer STORAGE = 0,
    parameter integer SEQUENCE_MODE = 1,
    parameter integer MUTATION = 0,
    parameter integer CONFIG_COUNT = 1,
    parameter [8*160-1:0] MASKS_FILE =
        "build/e256h-h4-sequence/control-masks.hex",
    parameter [8*160-1:0] SEQUENCES_FILE =
        "build/e256h-h4-sequence/control-h4-sequences.hex",
    parameter [8*160-1:0] LIVE_SEQUENCES_FILE =
        "build/e256h-h4-sequence/control-live-h4-sequences.hex",
    parameter [8*160-1:0] BLOCKS_FILE =
        "build/e256h-h4-sequence/blocks.hex",
    parameter [8*160-1:0] RESULTS_FILE =
        "build/e256h-h4-sequence/control-results.txt"
);
  localparam integer BLOCK_COUNT = 8;

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [255:0] mask_words [0:CONFIG_COUNT*13-1];
  reg [143:0] sequences [0:CONFIG_COUNT-1];
  reg [143:0] live_sequences [0:CONFIG_COUNT-1];
  reg [255:0] blocks [0:BLOCK_COUNT-1];

  reg          cfg_begin;
  reg          cfg_valid;
  wire         cfg_ready;
  reg  [255:0] cfg_word;
  reg          cfg_commit;
  reg  [143:0] cfg_h4_sequence;
  wire         key_valid;
  wire         cfg_error;
  reg          start;
  wire         ready;
  reg  [255:0] block_i;
  wire [255:0] block_o;
  wire         busy;
  wire         done;

  integer cycle_counter;
  integer results_fd;
  integer config_index;
  integer block_index;

  always @(posedge clk) begin
    if (rst) begin
      cycle_counter <= 0;
    end else begin
      cycle_counter <= cycle_counter + 1;
    end
  end

  e256h_h4_control_core #(
      .STORAGE(STORAGE), .SEQUENCE_MODE(SEQUENCE_MODE), .MUTATION(MUTATION)
  ) u_control (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4_sequence(cfg_h4_sequence), .key_valid(key_valid),
      .cfg_error(cfg_error), .start(start), .ready(ready), .block_i(block_i),
      .block_o(block_o), .busy(busy), .done(done)
  );

  task automatic write_state_hex(
      input integer handle,
      input [255:0] value
  );
    integer lane;
    begin
      for (lane = 0; lane < 32; lane = lane + 1) begin
        $fwrite(handle, "%02x", value[8*lane +: 8]);
      end
    end
  endtask

  task automatic configure_control(input integer selected_config);
    integer word_index;
    begin
      @(negedge clk);
      cfg_h4_sequence = sequences[selected_config];
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (!cfg_ready || key_valid || cfg_error) begin
        $fatal(1, "control begin failed config=%0d", selected_config);
      end
      for (word_index = 0; word_index < 13;
           word_index = word_index + 1) begin
        @(negedge clk);
        if (!cfg_ready) begin
          $fatal(1, "control cfg_ready missing config=%0d word=%0d",
                 selected_config, word_index);
        end
        cfg_word = mask_words[selected_config*13+word_index];
        cfg_valid = 1'b1;
        @(negedge clk);
        cfg_valid = 1'b0;
      end
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (!key_valid || cfg_error || !ready) begin
        $fatal(1, "control commit failed config=%0d", selected_config);
      end
      if (live_sequences[selected_config] === sequences[selected_config]) begin
        $fatal(1, "control live sequence did not change config=%0d",
               selected_config);
      end
      cfg_h4_sequence = live_sequences[selected_config];
    end
  endtask

  task automatic run_control_block(
      input integer selected_config,
      input integer selected_block
  );
    integer accept_cycle;
    integer latency;
    integer timeout;
    begin
      @(negedge clk);
      if (!ready || busy) begin
        $fatal(1, "control not ready config=%0d block=%0d",
               selected_config, selected_block);
      end
      block_i = blocks[selected_block];
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      accept_cycle = cycle_counter;
      timeout = 0;
      while (!done) begin
        @(negedge clk);
        if (!done && (ready || !busy)) begin
          $fatal(1, "control early ready/busy release config=%0d block=%0d",
                 selected_config, selected_block);
        end
        timeout = timeout + 1;
        if (timeout > 20) begin
          $fatal(1, "control timed out config=%0d block=%0d",
                 selected_config, selected_block);
        end
      end
      latency = cycle_counter - accept_cycle;
      if (latency != 12 || !ready || busy) begin
        $fatal(1, "control cycle mismatch latency=%0d ready=%b busy=%b",
               latency, ready, busy);
      end
      $fwrite(results_fd, "control %0d %0d %0d %0d %0d %036x %036x ",
              MUTATION, STORAGE, SEQUENCE_MODE, selected_config,
              selected_block, sequences[selected_config],
              live_sequences[selected_config]);
      write_state_hex(results_fd, block_o);
      $fwrite(results_fd, " %0d\n", latency);
    end
  endtask

  initial begin
    if (STORAGE < 0 || STORAGE > 1 ||
        SEQUENCE_MODE < 0 || SEQUENCE_MODE > 1 ||
        MUTATION < 0 || MUTATION > 8 || CONFIG_COUNT < 1) begin
      $fatal(1, "invalid H4 control parameters");
    end
    if ((MUTATION >= 1 && MUTATION <= 3) && SEQUENCE_MODE == 0) begin
      $fatal(1, "selector-order mutation requires sequence mode");
    end
    if (MUTATION == 5 && STORAGE != 0) begin
      $fatal(1, "wrong-key-address mutation requires FF storage");
    end
    if (MUTATION == 6 && STORAGE != 1) begin
      $fatal(1, "broken-ring mutation requires ring storage");
    end

    $readmemh(MASKS_FILE, mask_words);
    $readmemh(SEQUENCES_FILE, sequences);
    $readmemh(LIVE_SEQUENCES_FILE, live_sequences);
    $readmemh(BLOCKS_FILE, blocks);

    cfg_begin = 1'b0;
    cfg_valid = 1'b0;
    cfg_word = 256'd0;
    cfg_commit = 1'b0;
    cfg_h4_sequence = 144'd0;
    start = 1'b0;
    block_i = 256'd0;
    cycle_counter = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    results_fd = $fopen(RESULTS_FILE, "w");
    if (results_fd == 0) begin
      $fatal(1, "could not open H4 control results: %0s", RESULTS_FILE);
    end

    for (config_index = 0; config_index < CONFIG_COUNT;
         config_index = config_index + 1) begin
      configure_control(config_index);
      for (block_index = 0; block_index < BLOCK_COUNT;
           block_index = block_index + 1) begin
        run_control_block(config_index, block_index);
      end
    end

    $fclose(results_fd);
    $display("E256H_H4_SEQUENCE_CONTROL_TB_DONE");
    $finish;
  end
endmodule

`default_nettype wire

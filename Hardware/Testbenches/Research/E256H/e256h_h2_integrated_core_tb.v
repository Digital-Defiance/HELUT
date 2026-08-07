// Sequential E256-H H2 integrated-core testbenches.
//
// Contract: directives/e256-hardware-h2-preregistration.json
// RTL:      Hardware/RTL/Research/E256H/e256h_h2_integrated_core.v
//
// This file defines three selectable simulation tops:
//   e256h_h2_integrated_core_tb -- all six correct wrappers, protocol controls,
//                                  exact latency/II checks, and canonical rows
//   e256h_h2_control_tb         -- one parameterized mutation/input-file run
//   e256h_h2_sbox_tb            -- exhaustive H2/frozen S-box semantic bridge
//
// The frozen documents do not assign H2 vector filenames, a raw row grammar,
// a completion sentinel, or numeric mutation codes.  This testbench therefore
// defines the following local runner ABI without changing the frozen science:
//
//   build/e256h-h2/masks.hex : CONFIG_COUNT*13 lines, one 256-bit K word/line;
//                              line 13*c+k is K_k for configuration c
//   build/e256h-h2/h4.hex    : CONFIG_COUNT lines, one 12-bit {o3,o2,o1,o0}
//   build/e256h-h2/blocks.hex: eight lines, one 256-bit block per line
//   build/e256h-h2/results.txt
//
// Main result row (state hex is byte index 0 through 31, lowercase; `-`
// marks a fixed variant outside its frozen 24-output corpus):
//   rtl <config> <block> <h4> <run-mask> <six outputs> <six latencies>
//       <six initiation intervals>
//
// Each per-input initiation interval is derived from the checked ready window:
// ready stays low throughout busy and rises with done, so the earliest next
// accepted edge is one cycle after the observed completion edge.
//
// All changing stimulus and pulses are driven on negative clock edges.  The
// testbench does not derive expected cipher outputs; the runner remains the
// independent model and validates every emitted row.

`default_nettype none
`timescale 1ns / 1ps

module e256h_h2_integrated_core_tb #(
    parameter integer CONFIG_COUNT = 1,
    parameter [8*128-1:0] MASKS_FILE = "build/e256h-h2/masks.hex",
    parameter [8*128-1:0] H4_FILE = "build/e256h-h2/h4.hex",
    parameter [8*128-1:0] BLOCKS_FILE = "build/e256h-h2/blocks.hex",
    parameter [8*128-1:0] RESULTS_FILE = "build/e256h-h2/results.txt"
);
  localparam integer BLOCK_COUNT = 8;
  localparam [11:0] FIXED_H4 = 12'h8c8; // {4,3,1,0}

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [255:0] mask_words [0:CONFIG_COUNT*13-1];
  reg [11:0]  h4_words [0:CONFIG_COUNT-1];
  reg [255:0] blocks [0:BLOCK_COUNT-1];

  reg          cfg_begin;
  reg          cfg_valid;
  reg  [255:0] cfg_word;
  reg          cfg_commit;
  reg  [11:0]  cfg_h4;
  reg  [5:0]   starts;
  reg  [255:0] block_i;

  wire [5:0] cfg_ready_bus;
  wire [5:0] key_valid_bus;
  wire [5:0] cfg_error_bus;
  wire [5:0] ready_bus;
  wire [5:0] busy_bus;
  wire [5:0] done_bus;

  wire [255:0] ff_fixed_o;
  wire [255:0] ff_direct_o;
  wire [255:0] ring_fixed_o;
  wire [255:0] ring_direct_o;
  wire [255:0] mem_fixed_o;
  wire [255:0] mem_direct_o;

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

  e256h_h2_ff_fixed u_ff_fixed (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[0]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[0]), .cfg_error(cfg_error_bus[0]),
      .start(starts[0]), .ready(ready_bus[0]), .block_i(block_i),
      .block_o(ff_fixed_o), .busy(busy_bus[0]), .done(done_bus[0])
  );

  e256h_h2_ff_direct u_ff_direct (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[1]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[1]), .cfg_error(cfg_error_bus[1]),
      .start(starts[1]), .ready(ready_bus[1]), .block_i(block_i),
      .block_o(ff_direct_o), .busy(busy_bus[1]), .done(done_bus[1])
  );

  e256h_h2_ring_fixed u_ring_fixed (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[2]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[2]), .cfg_error(cfg_error_bus[2]),
      .start(starts[2]), .ready(ready_bus[2]), .block_i(block_i),
      .block_o(ring_fixed_o), .busy(busy_bus[2]), .done(done_bus[2])
  );

  e256h_h2_ring_direct u_ring_direct (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[3]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[3]), .cfg_error(cfg_error_bus[3]),
      .start(starts[3]), .ready(ready_bus[3]), .block_i(block_i),
      .block_o(ring_direct_o), .busy(busy_bus[3]), .done(done_bus[3])
  );

  e256h_h2_mem_fixed u_mem_fixed (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[4]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[4]), .cfg_error(cfg_error_bus[4]),
      .start(starts[4]), .ready(ready_bus[4]), .block_i(block_i),
      .block_o(mem_fixed_o), .busy(busy_bus[4]), .done(done_bus[4])
  );

  e256h_h2_mem_direct u_mem_direct (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready_bus[5]), .cfg_word(cfg_word),
      .cfg_commit(cfg_commit), .cfg_h4(cfg_h4),
      .key_valid(key_valid_bus[5]), .cfg_error(cfg_error_bus[5]),
      .start(starts[5]), .ready(ready_bus[5]), .block_i(block_i),
      .block_o(mem_direct_o), .busy(busy_bus[5]), .done(done_bus[5])
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

  task automatic pulse_clean_begin;
    begin
      @(negedge clk);
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_ready_bus !== 6'h3f) begin
        $fatal(1, "cfg_ready did not assert after clean cfg_begin: %b",
               cfg_ready_bus);
      end
      if (key_valid_bus !== 6'h00) begin
        $fatal(1, "cfg_begin did not invalidate all keys: %b", key_valid_bus);
      end
      if (cfg_error_bus !== 6'h00) begin
        $fatal(1, "clean cfg_begin did not clear errors: %b", cfg_error_bus);
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
        if (cfg_ready_bus !== 6'h3f) begin
          $fatal(1, "cfg_ready missing before config=%0d word=%0d: %b",
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
      cfg_h4 = h4_words[selected_config];
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_ready_bus !== 6'h3f || key_valid_bus !== 6'h00 ||
          cfg_error_bus !== 6'h00) begin
        $fatal(1, "bad begin handshake for config=%0d ready=%b key=%b err=%b",
               selected_config, cfg_ready_bus, key_valid_bus, cfg_error_bus);
      end
      load_words(selected_config, 13);
      #1;
      if (cfg_ready_bus !== 6'h00) begin
        $fatal(1, "cfg_ready remained high after thirteen words: %b",
               cfg_ready_bus);
      end
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (key_valid_bus !== 6'h3f || cfg_error_bus !== 6'h00 ||
          ready_bus !== 6'h3f) begin
        $fatal(1, "bad commit for config=%0d key=%b err=%b ready=%b",
               selected_config, key_valid_bus, cfg_error_bus, ready_bus);
      end
    end
  endtask

  // Required twelve-word commit/start control, plus the other malformed
  // configuration classes named by the frozen architecture record.
  task automatic run_protocol_controls;
    integer seen;
    integer timeout;
    begin
      // Early commit after twelve words, then start without key_valid.
      @(negedge clk);
      cfg_h4 = h4_words[0];
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
      if (cfg_error_bus !== 6'h3f || key_valid_bus !== 6'h00 ||
          ready_bus !== 6'h00) begin
        $fatal(1, "incomplete configuration was not rejected");
      end
      @(negedge clk);
      starts = 6'h3f;
      @(negedge clk);
      starts = 6'h00;
      seen = done_bus;
      if (busy_bus !== 6'h00) begin
        $fatal(1, "start after incomplete configuration asserted busy");
      end
      for (timeout = 0; timeout < 16; timeout = timeout + 1) begin
        @(negedge clk);
        seen = seen | done_bus;
        if (busy_bus !== 6'h00) begin
          $fatal(1, "start after incomplete configuration asserted busy");
        end
      end
      if (seen != 0 || key_valid_bus !== 6'h00 ||
          cfg_error_bus !== 6'h3f) begin
        $fatal(1, "start after incomplete configuration produced activity");
      end

      // A fourteenth word poisons the span; the following commit is late.
      @(negedge clk);
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      load_words(0, 13);
      #1;
      if (cfg_ready_bus !== 6'h00) begin
        $fatal(1, "cfg_ready asserted before planted fourteenth word");
      end
      @(negedge clk);
      cfg_word = mask_words[0];
      cfg_valid = 1'b1;
      @(negedge clk);
      cfg_valid = 1'b0;
      #1;
      if (cfg_error_bus !== 6'h3f || key_valid_bus !== 6'h00) begin
        $fatal(1, "fourteenth configuration word was not rejected");
      end
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (cfg_error_bus !== 6'h3f || key_valid_bus !== 6'h00) begin
        $fatal(1, "late commit was not rejected");
      end

      // A cfg_valid/start shared beat is rejected before any mask word can be
      // accepted.  The poisoned span cannot be committed or launch a block.
      @(negedge clk);
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_ready_bus !== 6'h3f || key_valid_bus !== 6'h00 ||
          cfg_error_bus !== 6'h00) begin
        $fatal(1, "bad recovery before cfg_valid/start collision");
      end
      @(negedge clk);
      cfg_word = mask_words[0];
      cfg_valid = 1'b1;
      starts = 6'h3f;
      #1;
      if (cfg_ready_bus !== 6'h00) begin
        $fatal(1, "cfg_valid/start collision left cfg_ready asserted");
      end
      @(negedge clk);
      cfg_valid = 1'b0;
      starts = 6'h00;
      #1;
      if (cfg_error_bus !== 6'h3f || key_valid_bus !== 6'h00 ||
          ready_bus !== 6'h00 || busy_bus !== 6'h00) begin
        $fatal(1, "cfg_valid/start collision was not rejected");
      end

      // A same-beat configuration/start collision is rejected and cannot
      // launch a block under the previous committed key.
      configure_all(0);
      @(negedge clk);
      block_i = blocks[0];
      cfg_begin = 1'b1;
      starts = 6'h3f;
      @(negedge clk);
      cfg_begin = 1'b0;
      starts = 6'h00;
      seen = done_bus;
      if (busy_bus !== 6'h00) begin
        $fatal(1, "configuration/start collision asserted busy");
      end
      for (timeout = 0; timeout < 16; timeout = timeout + 1) begin
        @(negedge clk);
        seen = seen | done_bus;
        if (busy_bus !== 6'h00) begin
          $fatal(1, "configuration/start collision asserted busy");
        end
      end
      if (seen != 0 || cfg_error_bus !== 6'h3f ||
          key_valid_bus !== 6'h00) begin
        $fatal(1, "configuration/start collision was not rejected");
      end

      // Configuration activity while every core is busy is rejected without
      // disturbing the in-flight block or its committed key.
      configure_all(0);
      @(negedge clk);
      if (ready_bus !== 6'h3f) begin
        $fatal(1, "cores not ready before busy-configuration control");
      end
      block_i = blocks[0];
      starts = 6'h3f;
      @(negedge clk);
      starts = 6'h00;
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (cfg_error_bus !== 6'h3f || key_valid_bus !== 6'h3f) begin
        $fatal(1, "configuration-while-busy control did not fire cleanly");
      end
      seen = 0;
      timeout = 0;
      while (seen != 6'h3f) begin
        @(negedge clk);
        seen = seen | done_bus;
        timeout = timeout + 1;
        if (timeout > 20) begin
          $fatal(1, "busy-configuration control timed out");
        end
      end
      if (busy_bus !== 6'h00) begin
        $fatal(1, "core remained busy after busy-configuration control");
      end
    end
  endtask

  task automatic run_all_and_write(
      input integer selected_config,
      input integer selected_block
  );
    integer accept_cycle;
    integer timeout;
    integer variant_index;
    integer expected_latency;
    integer expected_interval;
    integer latencies [0:5];
    integer intervals [0:5];
    reg [5:0] run_mask;
    reg [5:0] seen;
    begin
      run_mask = (h4_words[selected_config] == FIXED_H4) ? 6'h3f : 6'h2a;
      @(negedge clk);
      if (ready_bus !== 6'h3f || busy_bus !== 6'h00) begin
        $fatal(1, "not ready before config=%0d block=%0d ready=%b busy=%b",
               selected_config, selected_block, ready_bus, busy_bus);
      end
      block_i = blocks[selected_block];
      starts = run_mask;
      @(negedge clk);
      starts = 6'h00;
      accept_cycle = cycle_counter;
      if ((busy_bus & run_mask) !== run_mask ||
          (ready_bus & run_mask) !== 6'h00) begin
        $fatal(1, "acceptance state mismatch config=%0d block=%0d run=%02x ready=%02x busy=%02x",
               selected_config, selected_block, run_mask, ready_bus, busy_bus);
      end
      seen = 6'h00;
      timeout = 0;
      for (variant_index = 0; variant_index < 6;
           variant_index = variant_index + 1) begin
        latencies[variant_index] = -1;
        intervals[variant_index] = -1;
      end

      while ((seen & run_mask) != run_mask) begin
        @(negedge clk);
        for (variant_index = 0; variant_index < 6;
             variant_index = variant_index + 1) begin
          if (run_mask[variant_index] && !seen[variant_index]) begin
            if (done_bus[variant_index]) begin
              if (!ready_bus[variant_index] || busy_bus[variant_index]) begin
                $fatal(1, "ready/busy mismatch on completion config=%0d block=%0d variant=%0d",
                       selected_config, selected_block, variant_index);
              end
              latencies[variant_index] = cycle_counter - accept_cycle;
              intervals[variant_index] = latencies[variant_index] + 1;
              seen[variant_index] = 1'b1;
            end else if (ready_bus[variant_index] ||
                         !busy_bus[variant_index]) begin
              $fatal(1, "early ready/busy release config=%0d block=%0d variant=%0d cycle=%0d",
                     selected_config, selected_block, variant_index,
                     cycle_counter - accept_cycle);
            end
          end
        end
        timeout = timeout + 1;
        if (timeout > 20) begin
          $fatal(1, "block run timed out config=%0d block=%0d seen=%0x run=%0x",
                 selected_config, selected_block, seen, run_mask);
        end
      end

      for (variant_index = 0; variant_index < 6;
           variant_index = variant_index + 1) begin
        if (run_mask[variant_index]) begin
          expected_latency = (variant_index < 4) ? 12 : 14;
          expected_interval = expected_latency + 1;
          if (latencies[variant_index] != expected_latency ||
              intervals[variant_index] != expected_interval) begin
            $fatal(1, "cycle mismatch config=%0d block=%0d variant=%0d latency=%0d ii=%0d",
                   selected_config, selected_block, variant_index,
                   latencies[variant_index], intervals[variant_index]);
          end
        end
      end
      if (h4_words[selected_config] == FIXED_H4 &&
          (ff_fixed_o !== ring_fixed_o || ff_fixed_o !== mem_fixed_o)) begin
        $fatal(1, "fixed storage mismatch config=%0d block=%0d",
               selected_config, selected_block);
      end
      if (ff_direct_o !== ring_direct_o || ff_direct_o !== mem_direct_o) begin
        $fatal(1, "direct storage mismatch config=%0d block=%0d",
               selected_config, selected_block);
      end
      if (h4_words[selected_config] == FIXED_H4 &&
          (ff_fixed_o !== ff_direct_o || ring_fixed_o !== ring_direct_o ||
           mem_fixed_o !== mem_direct_o)) begin
        $fatal(1, "fixed/direct bridge mismatch config=%0d block=%0d",
               selected_config, selected_block);
      end

      $fwrite(results_fd, "rtl %0d %0d %03x %02x", selected_config,
              selected_block, h4_words[selected_config], run_mask);
      for (variant_index = 0; variant_index < 6;
           variant_index = variant_index + 1) begin
        $fwrite(results_fd, " ");
        if (!run_mask[variant_index]) begin
          $fwrite(results_fd, "-");
        end else begin
          case (variant_index)
            0: write_state_hex(results_fd, ff_fixed_o);
            1: write_state_hex(results_fd, ff_direct_o);
            2: write_state_hex(results_fd, ring_fixed_o);
            3: write_state_hex(results_fd, ring_direct_o);
            4: write_state_hex(results_fd, mem_fixed_o);
            5: write_state_hex(results_fd, mem_direct_o);
          endcase
        end
      end
      for (variant_index = 0; variant_index < 6;
           variant_index = variant_index + 1) begin
        if (run_mask[variant_index]) begin
          $fwrite(results_fd, " %0d", latencies[variant_index]);
        end else begin
          $fwrite(results_fd, " -");
        end
      end
      for (variant_index = 0; variant_index < 6;
           variant_index = variant_index + 1) begin
        if (run_mask[variant_index]) begin
          $fwrite(results_fd, " %0d", intervals[variant_index]);
        end else begin
          $fwrite(results_fd, " -");
        end
      end
      $fwrite(results_fd, "\n");
    end
  endtask

  initial begin
    if (CONFIG_COUNT < 1) begin
      $fatal(1, "CONFIG_COUNT must be positive");
    end
    $readmemh(MASKS_FILE, mask_words);
    $readmemh(H4_FILE, h4_words);
    $readmemh(BLOCKS_FILE, blocks);

    cfg_begin = 1'b0;
    cfg_valid = 1'b0;
    cfg_word = 256'd0;
    cfg_commit = 1'b0;
    cfg_h4 = 12'd0;
    starts = 6'h00;
    block_i = 256'd0;
    cycle_counter = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    results_fd = $fopen(RESULTS_FILE, "w");
    if (results_fd == 0) begin
      $fatal(1, "could not open H2 results file: %0s", RESULTS_FILE);
    end

    run_protocol_controls();

    for (config_index = 0; config_index < CONFIG_COUNT;
         config_index = config_index + 1) begin
      configure_all(config_index);
      for (block_index = 0; block_index < BLOCK_COUNT;
           block_index = block_index + 1) begin
        run_all_and_write(config_index, block_index);
      end
    end

    $fclose(results_fd);
    $display("E256H_H2_INTEGRATED_CORE_TB_DONE");
    $finish;
  end
endmodule

// ---------------------------------------------------------------------------
// Parameterized control top.  The runner selects one storage organization,
// fixed/direct H4 path, mutation code, and optional alternate mask/H4 files.
// It always executes all eight blocks for every supplied configuration.
module e256h_h2_control_tb #(
    parameter integer STORAGE = 0,       // 0=ff, 1=ring, 2=mem
    parameter integer DIRECT_H4 = 1,
    parameter integer MUTATION = 0,
    parameter integer CONFIG_COUNT = 1,
    parameter [8*128-1:0] MASKS_FILE = "build/e256h-h2/control-masks.hex",
    parameter [8*128-1:0] H4_FILE = "build/e256h-h2/control-h4.hex",
    parameter [8*128-1:0] BLOCKS_FILE = "build/e256h-h2/blocks.hex",
    parameter [8*128-1:0] RESULTS_FILE = "build/e256h-h2/control-results.txt"
);
  localparam integer BLOCK_COUNT = 8;

  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  reg [255:0] mask_words [0:CONFIG_COUNT*13-1];
  reg [11:0]  h4_words [0:CONFIG_COUNT-1];
  reg [255:0] blocks [0:BLOCK_COUNT-1];

  reg          cfg_begin;
  reg          cfg_valid;
  wire         cfg_ready;
  reg  [255:0] cfg_word;
  reg          cfg_commit;
  reg  [11:0]  cfg_h4;
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

  e256h_h2_control_core #(
      .STORAGE(STORAGE), .DIRECT_H4(DIRECT_H4), .MUTATION(MUTATION)
  ) u_control (
      .clk(clk), .rst(rst), .cfg_begin(cfg_begin), .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready), .cfg_word(cfg_word), .cfg_commit(cfg_commit),
      .cfg_h4(cfg_h4), .key_valid(key_valid), .cfg_error(cfg_error),
      .start(start), .ready(ready), .block_i(block_i), .block_o(block_o),
      .busy(busy), .done(done)
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
      cfg_h4 = h4_words[selected_config];
      cfg_begin = 1'b1;
      @(negedge clk);
      cfg_begin = 1'b0;
      #1;
      if (!cfg_ready || key_valid || cfg_error) begin
        $fatal(1, "control begin handshake failed config=%0d", selected_config);
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
      #1;
      if (cfg_ready) begin
        $fatal(1, "control cfg_ready high after thirteen words");
      end
      @(negedge clk);
      cfg_commit = 1'b1;
      @(negedge clk);
      cfg_commit = 1'b0;
      #1;
      if (!key_valid || cfg_error || !ready) begin
        $fatal(1, "control commit failed config=%0d", selected_config);
      end
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
        $fatal(1, "control core not ready config=%0d block=%0d",
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
        timeout = timeout + 1;
        if (timeout > 20) begin
          $fatal(1, "control block timed out config=%0d block=%0d",
                 selected_config, selected_block);
        end
      end
      latency = cycle_counter - accept_cycle;
      if ((STORAGE == 2 && latency != 14) ||
          (STORAGE != 2 && latency != 12)) begin
        $fatal(1, "control latency mismatch storage=%0d latency=%0d",
               STORAGE, latency);
      end
      $fwrite(results_fd, "control %0d %0d %0d %0d %0d %03x ",
              MUTATION, STORAGE, DIRECT_H4, selected_config, selected_block,
              h4_words[selected_config]);
      write_state_hex(results_fd, block_o);
      $fwrite(results_fd, " %0d\n", latency);
    end
  endtask

  initial begin
    if (STORAGE < 0 || STORAGE > 2) begin
      $fatal(1, "STORAGE must be 0, 1, or 2");
    end
    if (DIRECT_H4 < 0 || DIRECT_H4 > 1) begin
      $fatal(1, "DIRECT_H4 must be 0 or 1");
    end
    if (MUTATION < 0 || MUTATION > 7) begin
      $fatal(1, "MUTATION must be in 0..7");
    end
    if (MUTATION == 1 && STORAGE == 1) begin
      $fatal(1, "wrong-key-address mutation requires ff or mem storage");
    end
    if ((MUTATION == 2 || MUTATION == 3) && DIRECT_H4 == 0) begin
      $fatal(1, "H4 mutation requires the runtime-direct path");
    end
    if (MUTATION == 4 && STORAGE != 1) begin
      $fatal(1, "broken-ring mutation requires ring storage");
    end
    if (MUTATION == 5 && STORAGE != 2) begin
      $fatal(1, "stale-memory mutation requires memory storage");
    end
    if (CONFIG_COUNT < 1) begin
      $fatal(1, "CONFIG_COUNT must be positive");
    end

    $readmemh(MASKS_FILE, mask_words);
    $readmemh(H4_FILE, h4_words);
    $readmemh(BLOCKS_FILE, blocks);

    cfg_begin = 1'b0;
    cfg_valid = 1'b0;
    cfg_word = 256'd0;
    cfg_commit = 1'b0;
    cfg_h4 = 12'd0;
    start = 1'b0;
    block_i = 256'd0;
    cycle_counter = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    results_fd = $fopen(RESULTS_FILE, "w");
    if (results_fd == 0) begin
      $fatal(1, "could not open control results file: %0s", RESULTS_FILE);
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
    $display("E256H_H2_CONTROL_TB_DONE");
    $finish;
  end
endmodule

// ---------------------------------------------------------------------------
// Exhaustive semantic bridge for the explicit H2 LUT6 S-box netlist.  The
// runner also checks every emitted value against its independent AES table.
module e256h_h2_sbox_tb #(
    parameter [8*128-1:0] RESULTS_FILE =
        "build/e256h-h2/sbox-results.txt"
);
  reg [7:0] x;
  wire [7:0] h2_y;
  wire [7:0] frozen_y;
  integer results_fd;
  integer value;

  e256h_h2_sbox u_h2 (.x(x), .y(h2_y));
  e256h_atk_sbox u_frozen (.x(x), .y(frozen_y));

  initial begin
    results_fd = $fopen(RESULTS_FILE, "w");
    if (results_fd == 0) begin
      $fatal(1, "could not open H2 S-box results file: %0s", RESULTS_FILE);
    end
    for (value = 0; value < 256; value = value + 1) begin
      x = value[7:0];
      #1;
      if (h2_y !== frozen_y) begin
        $fatal(1, "H2/frozen S-box mismatch x=%02x h2=%02x frozen=%02x",
               x, h2_y, frozen_y);
      end
      $fwrite(results_fd, "sbox %02x %02x %02x\n", x, h2_y, frozen_y);
    end
    $fclose(results_fd);
    $display("E256H_H2_SBOX_TB_DONE");
    $finish;
  end
endmodule

`default_nettype wire

`timescale 1ns / 1ps

// Golden co-sim through AXI4-Lite + AXIS table burst (enigma_256_axi).
//
//   ./Scripts/enigma256_axi_sim.sh
//
// Default: load tables via AXIS (2560 beats). +LITE=1 uses legacy WR_* path.

module enigma_256_axi_tb;
    reg         aclk = 0;
    reg         aresetn = 0;
    always #5 aclk = ~aclk;

    reg  [7:0]  awaddr = 0;
    reg         awvalid = 0;
    wire        awready;
    reg  [31:0] wdata = 0;
    reg  [3:0]  wstrb = 4'hF;
    reg         wvalid = 0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready = 1;
    reg  [7:0]  araddr = 0;
    reg         arvalid = 0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready = 1;

    reg  [7:0]  axis_tdata = 0;
    reg         axis_tvalid = 0;
    wire        axis_tready;
    reg         axis_tlast = 0;

    enigma_256_axi dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_tdata(axis_tdata), .s_axis_tvalid(axis_tvalid),
        .s_axis_tready(axis_tready), .s_axis_tlast(axis_tlast)
    );

    reg [7:0] table_mem [0:9][0:255];
    reg [7:0] plain_mem [0:1023];
    reg [7:0] cipher_mem [0:1023];
    integer i, t, errors, n_bytes, code, fd, polls, use_lite;
    reg [7:0] byte_v;
    reg [31:0] rtmp;
    string hexdir, path;

`include "Fixtures/enigma256_golden/tb_params.vh"

    task axi_write;
        input [7:0] addr;
        input [31:0] data;
        integer guard;
        begin
            guard = 0;
            @(posedge aclk);
            awaddr  <= addr;
            wdata   <= data;
            awvalid <= 1;
            wvalid  <= 1;
            @(posedge aclk);
            while (!(awready && wready) && guard < 100) begin
                guard = guard + 1;
                @(posedge aclk);
            end
            if (guard >= 100) begin
                $display("FATAL: AXI write addr ready timeout @ %h", addr);
                $finish(1);
            end
            awvalid <= 0;
            wvalid  <= 0;
            guard = 0;
            while (!bvalid && guard < 100) begin
                guard = guard + 1;
                @(posedge aclk);
            end
            if (guard >= 100) begin
                $display("FATAL: AXI write bvalid timeout @ %h", addr);
                $finish(1);
            end
            @(posedge aclk);
        end
    endtask

    task axi_read;
        input  [7:0] addr;
        output [31:0] data;
        integer guard;
        begin
            guard = 0;
            @(posedge aclk);
            araddr  <= addr;
            arvalid <= 1;
            @(posedge aclk);
            while (!arready && guard < 100) begin
                guard = guard + 1;
                @(posedge aclk);
            end
            if (guard >= 100) begin
                $display("FATAL: AXI read addr ready timeout @ %h", addr);
                $finish(1);
            end
            arvalid <= 0;
            guard = 0;
            while (!rvalid && guard < 100) begin
                guard = guard + 1;
                @(posedge aclk);
            end
            if (guard >= 100) begin
                $display("FATAL: AXI read rvalid timeout @ %h", addr);
                $finish(1);
            end
            data = rdata;
            @(posedge aclk);
        end
    endtask

    task axi_transfer;
        input  [7:0] din;
        output [7:0] dout;
        begin
            axi_write(8'h28, {24'd0, din});
            polls = 0;
            rtmp = 0;
            while (polls < 32) begin
                axi_read(8'h30, rtmp);
                if (rtmp[0]) begin
                    axi_read(8'h2C, rtmp);
                    dout = rtmp[7:0];
                    polls = 99;
                end else begin
                    polls = polls + 1;
                end
            end
            if (polls != 99) begin
                $display("FATAL: STATUS.valid timeout");
                $finish(1);
            end
        end
    endtask

    task axis_load_tables;
        integer guard;
        begin
            axi_write(8'h00, 32'h2); // CTRL[1] arm AXIS
            @(posedge aclk);
            for (t = 0; t < 10; t = t + 1) begin
                for (i = 0; i < 256; i = i + 1) begin
                    guard = 0;
                    @(posedge aclk);
                    axis_tdata  <= table_mem[t][i];
                    axis_tvalid <= 1;
                    axis_tlast  <= (t == 9 && i == 255);
                    @(posedge aclk);
                    while (!axis_tready && guard < 100) begin
                        guard = guard + 1;
                        @(posedge aclk);
                    end
                    if (guard >= 100) begin
                        $display("FATAL: AXIS tready timeout sel=%0d addr=%0d", t, i);
                        $finish(1);
                    end
                    axis_tvalid <= 0;
                    axis_tlast  <= 0;
                end
            end
            // Wait for done (STATUS[2])
            polls = 0;
            rtmp = 0;
            while (polls < 64) begin
                axi_read(8'h30, rtmp);
                if (rtmp[2]) begin
                    polls = 99;
                end else begin
                    polls = polls + 1;
                end
            end
            if (polls != 99) begin
                $display("FATAL: AXIS done timeout");
                $finish(1);
            end
            axi_read(8'h38, rtmp);
            if (rtmp[11:0] != 12'd2560) begin
                $display("FATAL: BURST_STATUS=%0d want 2560", rtmp[11:0]);
                $finish(1);
            end
            $display("AXIS table burst: %0d bytes OK", rtmp[11:0]);
        end
    endtask

    task lite_load_tables;
        begin
            for (t = 0; t < 10; t = t + 1) begin
                axi_write(8'h04, t[3:0]);
                for (i = 0; i < 256; i = i + 1) begin
                    axi_write(8'h08, i[7:0]);
                    axi_write(8'h0C, table_mem[t][i]);
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("HEXDIR=%s", hexdir))
            hexdir = "Fixtures/enigma256_golden";
        use_lite = $test$plusargs("LITE");
        n_bytes = ENIGMA256_N;

        path = {hexdir, "/tables/plugboard.hex"}; load_table(0);
        path = {hexdir, "/tables/r1_fwd.hex"};    load_table(1);
        path = {hexdir, "/tables/r1_rev.hex"};    load_table(2);
        path = {hexdir, "/tables/r2_fwd.hex"};    load_table(3);
        path = {hexdir, "/tables/r2_rev.hex"};    load_table(4);
        path = {hexdir, "/tables/r3_fwd.hex"};    load_table(5);
        path = {hexdir, "/tables/r3_rev.hex"};    load_table(6);
        path = {hexdir, "/tables/r4_fwd.hex"};    load_table(7);
        path = {hexdir, "/tables/r4_rev.hex"};    load_table(8);
        path = {hexdir, "/tables/reflector.hex"}; load_table(9);
        path = {hexdir, "/plaintext.hex"};  load_plain();
        path = {hexdir, "/ciphertext.hex"}; load_cipher();

        aresetn = 0;
        repeat (4) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);

        if (use_lite)
            lite_load_tables();
        else
            axis_load_tables();

        // Message key + LOAD_STATE
        axi_write(8'h10, ENIGMA256_LFSR[31:0]);
        axi_write(8'h14, ENIGMA256_LFSR[63:32]);
        axi_write(8'h18, ENIGMA256_R1);
        axi_write(8'h1C, ENIGMA256_R2);
        axi_write(8'h20, ENIGMA256_R3);
        axi_write(8'h24, ENIGMA256_R4);
        axi_write(8'h00, 32'h1); // CTRL load_state
        repeat (2) @(posedge aclk);

        errors = 0;
        for (i = 0; i < n_bytes; i = i + 1) begin
            axi_transfer(plain_mem[i], byte_v);
            if (byte_v !== cipher_mem[i]) begin
                $display("FAIL beat %0d: got %02x want %02x", i, byte_v, cipher_mem[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: enigma_256_axi matched %0d golden bytes (%s)",
                     n_bytes, use_lite ? "LITE" : "AXIS");
        else
            $display("FAIL: %0d mismatches", errors);
        $finish(errors == 0 ? 0 : 1);
    end

    task load_table;
        input integer sel;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin $display("FATAL: %s", path); $finish(1); end
            for (i = 0; i < 256; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                if (code != 1) begin $display("FATAL: short %s", path); $finish(1); end
                table_mem[sel][i] = byte_v;
            end
            $fclose(fd);
        end
    endtask

    task load_plain;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin $display("FATAL: %s", path); $finish(1); end
            for (i = 0; i < n_bytes; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                plain_mem[i] = byte_v;
            end
            $fclose(fd);
        end
    endtask

    task load_cipher;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin $display("FATAL: %s", path); $finish(1); end
            for (i = 0; i < n_bytes; i = i + 1) begin
                code = $fscanf(fd, "%h\n", byte_v);
                cipher_mem[i] = byte_v;
            end
            $fclose(fd);
        end
    endtask
endmodule

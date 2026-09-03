`timescale 1ns / 1ps

module polymorphic_rotor_generator (
    input  wire        clk,
    input  wire        rst_n,
    
    // Interface from HKDF (AXI Stream / FIFO)
    input  wire [7:0]  hkdf_rand_byte,
    input  wire        hkdf_valid,
    output reg         hkdf_ready,
    
    // Interface to Rotor BRAMs
    output reg  [7:0]  fwd_addr,
    output reg  [7:0]  fwd_data,
    output reg         fwd_we,
    
    output reg  [7:0]  rev_addr,
    output reg  [7:0]  rev_data,
    output reg         rev_we,
    
    // Control
    input  wire        start_generation,
    output reg         generation_complete
);

    // Hardware Fisher-Yates State Machine
    localparam STATE_INIT      = 3'd0;
    localparam STATE_WAIT_RAND = 3'd1;
    localparam STATE_READ_SWAP = 3'd2;
    localparam STATE_WRITE_FWD = 3'd3;
    localparam STATE_WRITE_REV = 3'd4;
    localparam STATE_DONE      = 3'd5;

    reg [2:0] state;
    reg [7:0] iterator_i;
    reg [7:0] random_j;
    
    // Temporary storage for the swap
    reg [7:0] val_i, val_j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_INIT;
            generation_complete <= 1'b0;
            hkdf_ready <= 1'b0;
            fwd_we <= 1'b0;
            rev_we <= 1'b0;
            iterator_i <= 8'd255;
        end else begin
            case (state)
                // Step 1: Pre-fill the array with 0...255 (Initialization omitted for brevity, 
                // assuming a separate pre-fill state machine ran before this).
                
                STATE_INIT: begin
                    if (start_generation) begin
                        iterator_i <= 8'd255;
                        state <= STATE_WAIT_RAND;
                    end
                end

                // Step 2: Pull a random index `j` from the HKDF stream
                STATE_WAIT_RAND: begin
                    hkdf_ready <= 1'b1;
                    if (hkdf_valid) begin
                        hkdf_ready <= 1'b0;
                        // For a true Fisher-Yates, j must be 0 <= j <= i.
                        // In hardware, a modulo is expensive, so we use a fast-range
                        // mapping: j = (hkdf_rand_byte * (iterator_i + 1)) >> 8
                        // (Implemented here as a placeholder operation)
                        random_j <= hkdf_rand_byte; // Simplified for illustration
                        
                        fwd_addr <= iterator_i;
                        state <= STATE_READ_SWAP;
                    end
                end

                // Step 3: We have `i` and `j`. We need to swap them. 
                // In hardware, this takes two read cycles and two write cycles.
                STATE_READ_SWAP: begin
                    // BRAM Read logic goes here. We retrieve val_i and val_j.
                    // Once retrieved, we write them back to swapped locations.
                    state <= STATE_WRITE_FWD;
                end

                // Step 4: Write the shuffled results to the Forward BRAM
                STATE_WRITE_FWD: begin
                    fwd_addr <= iterator_i;
                    fwd_data <= val_j;
                    fwd_we   <= 1'b1;
                    // In parallel, we must write the Inverse mapping!
                    // If fwd[i] = val_j, then rev[val_j] = i
                    rev_addr <= val_j;
                    rev_data <= iterator_i;
                    rev_we   <= 1'b1;
                    
                    state <= STATE_WRITE_REV;
                end

                // Step 5: Complete the swap and the inverse mapping
                STATE_WRITE_REV: begin
                    fwd_addr <= random_j;
                    fwd_data <= val_i;
                    fwd_we   <= 1'b1;
                    
                    rev_addr <= val_i;
                    rev_data <= random_j;
                    rev_we   <= 1'b1;
                    
                    if (iterator_i == 8'd1) begin
                        state <= STATE_DONE;
                    end else begin
                        iterator_i <= iterator_i - 1'b1;
                        state <= STATE_WAIT_RAND;
                    end
                end

                STATE_DONE: begin
                    fwd_we <= 1'b0;
                    rev_we <= 1'b0;
                    generation_complete <= 1'b1;
                end
            endcase
        end
    end
endmodule

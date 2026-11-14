`default_nettype none
`timescale 1ns/1ns

// LAUNCH CONFIGURATION
// > A host write captures the batch size; reset takes precedence over a write.
module dcr (
    input wire clk,                 // Clock for host updates
    input wire reset,               // Clear the configuration
    input wire write_enable,        // Commit the supplied batch size
    input wire [15:0] data,         // New batch size in rays
    output wire [15:0] ray_count    // Current batch size for the launcher
);
    reg [15:0] batch_size;
    wire [15:0] next_batch_size = reset ? 16'd0 : data;
    wire update_batch_size = reset | write_enable;

    always @(posedge clk) begin
        if (update_batch_size) begin
            batch_size <= next_batch_size;
        end
    end

    assign ray_count = batch_size;
endmodule

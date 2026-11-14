`default_nettype none
`timescale 1ns/1ns

// TRAVERSAL STACK
// > Holds deferred right children while their left siblings are visited.
// > The BVH builder must ensure that no ray needs more than 16 entries.
module stack (
    input wire clk,                 // Clock
    input wire reset,               // Reset stack pointer
    input wire clear,               // Start a new ray with an empty stack
    input wire push,                // Save a deferred node
    input wire pop,                 // Remove the top node
    input wire [31:0] in_node,      // Node to push
    output wire [31:0] top,         // Most recently pushed node
    output wire empty,              // No deferred nodes remain
    output wire full                // Stack has reached its capacity
);
    reg [31:0] entries [0:15];
    reg [4:0] sp;

    assign empty = (sp == 0);
    assign full = (sp == 16);
    assign top = entries[sp - 1];

    always @(posedge clk) begin
        if (reset || clear) begin
            sp <= 0;
        end else if (push && !full) begin
            entries[sp] <= in_node;
            sp <= sp + 1;
        end else if (pop && !empty) begin
            sp <= sp - 1;
        end
    end
endmodule

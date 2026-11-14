`default_nettype none
`timescale 1ns/1ns

// CHANNEL ARBITER
// > Assigns pending consumers to memory channels in rotating priority order.
// > A stalled channel retains its owner until a valid/ready handshake.
// > Consumers must keep their request, address and data stable until ready.
module controller #(
    parameter N = 2,               // Number of consumers
    parameter C = 1,               // Number of memory channels
    parameter A = 16,              // Word address width
    parameter D = 32               // Word data width
) (
    input wire clk,                // Clock
    input wire reset,              // Clear reservations and priority
    input wire [N-1:0] req,        // Consumer requests
    input wire [N*A-1:0] addr,     // Consumer addresses, packed
    input wire [N*D-1:0] wdata,    // Consumer write data, packed
    output reg [N-1:0] ready,      // Completed consumer requests
    output reg [N*D-1:0] rdata,    // Read data returned to consumers
    output reg [C-1:0] mem_valid,  // Channel requests
    output reg [C*A-1:0] mem_addr, // Channel addresses
    output reg [C*D-1:0] mem_wdata,// Channel write data
    input wire [C-1:0] mem_ready,  // Channel handshakes
    input wire [C*D-1:0] mem_rdata // Channel read data
);
    // Integers keep indexing readable even for non-power-of-two core counts.
    integer priority_start;
    integer owner [0:C-1];
    reg [C-1:0] reserved;
    integer selected [0:C-1];
    reg [C-1:0] assigned;
    reg [N-1:0] taken;
    integer channel, step, candidate;
    integer next_priority;

    always @* begin
        mem_valid = 0;
        mem_addr = 0;
        mem_wdata = 0;
        ready = 0;
        rdata = 0;
        assigned = 0;
        taken = 0;
        next_priority = priority_start;

        // Reserve all stalled owners first so a free channel cannot steal one.
        for (integer c = 0; c < C; c = c + 1) begin
            selected[c] = 0;
            if (reserved[c]) begin
                selected[c] = owner[c];
                assigned[c] = 1;
                taken[owner[c]] = 1;
            end
        end

        // Fill free channels in channel order, searching from the round-robin
        // pointer. A consumer can occupy at most one channel in a cycle.
        for (channel = 0; channel < C; channel = channel + 1) begin
            if (!assigned[channel]) begin
                for (step = 0; step < N; step = step + 1) begin
                    candidate = (priority_start + step) % N;
                    if (!assigned[channel] && req[candidate] && !taken[candidate]) begin
                        selected[channel] = candidate;
                        assigned[channel] = 1;
                        taken[candidate] = 1;
                    end
                end
            end

            if (assigned[channel]) begin
                mem_valid[channel] = req[selected[channel]];
                mem_addr[channel*A +: A] = addr[selected[channel]*A +: A];
                mem_wdata[channel*D +: D] = wdata[selected[channel]*D +: D];
                ready[selected[channel]] = mem_ready[channel] && mem_valid[channel];
                rdata[selected[channel]*D +: D] = mem_rdata[channel*D +: D];
                if (mem_valid[channel] && mem_ready[channel]) begin
                    next_priority = (selected[channel] + 1) % N;
                end
            end
        end
    end

    // Latch only stalled grants. Accepted transfers release their channel on
    // the same edge; the next accepted consumer determines the new priority.
    always @(posedge clk) begin
        if (reset) begin
            reserved <= 0;
            priority_start <= 0;
            for (integer c = 0; c < C; c = c + 1) begin
                owner[c] <= 0;
            end
        end else begin
            priority_start <= next_priority;
            for (integer c = 0; c < C; c = c + 1) begin
                if (assigned[c] && mem_valid[c] && !mem_ready[c]) begin
                    reserved[c] <= 1;
                    owner[c] <= selected[c];
                end else begin
                    reserved[c] <= 0;
                end
            end
        end
    end
endmodule

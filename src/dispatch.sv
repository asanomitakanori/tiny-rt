`default_nettype none
`timescale 1ns/1ns

// RAY LAUNCHER
// > Issues monotonically increasing ray indices to available cores.
// > Counts completed jobs when a core transitions from busy to idle.
module dispatch #(parameter N = 2) (
    input wire clk,                 // Clock
    input wire reset,               // Clear launch bookkeeping
    input wire start,               // Start a batch when idle
    input wire [15:0] count,        // Rays in this batch
    input wire [N-1:0] busy,        // Core execution status
    output reg [N-1:0] launch,      // One-cycle assignment mask
    output wire [15:0] ray_id,      // Index assigned to the selected core
    output reg done                 // All batch results have been written
);
    reg running;
    reg [16:0] issued;
    reg [16:0] completed;
    reg [N-1:0] previous_busy;
    integer finished_now;
    integer core_index;
    reg selected;

    assign ray_id = issued[15:0];

    always @* begin
        launch = 0;
        selected = 0;
        finished_now = 0;
        for (core_index = 0; core_index < N; core_index = core_index + 1) begin
            if (previous_busy[core_index] && !busy[core_index]) begin
                finished_now = finished_now + 1;
            end
            if (running && issued < count && !busy[core_index] && !selected) begin
                launch[core_index] = 1;
                selected = 1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            running <= 0;
            issued <= 0;
            completed <= 0;
            previous_busy <= 0;
            done <= 0;
        end else begin
            previous_busy <= busy;
            if (!running) begin
                if (start && !done) begin
                    running <= 1;
                    issued <= 0;
                    completed <= 0;
                end else if (!start) begin
                    done <= 0;
                end
            end else begin
                if (selected) begin
                    issued <= issued + 1;
                end
                completed <= completed + finished_now;
                if (issued == count && completed + finished_now == count) begin
                    running <= 0;
                    done <= 1;
                end
            end
        end
    end
endmodule

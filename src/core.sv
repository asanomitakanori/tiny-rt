`default_nettype none
`timescale 1ns/1ns

// RT CORE
// > Loads one ray, delegates traversal, and writes the closest triangle ID.
// > Holds each memory request until its controller reports completion.
module core #(parameter A = 16, F = 16) (
    input wire clk,                    // Clock
    input wire reset,                  // Reset the core
    input wire launch,                 // Start a ray
    input wire [15:0] ray_id,          // Ray index to load
    output wire busy,                  // Core is processing a ray
    output reg scene_req,              // Scene memory read request
    output reg [A-1:0] scene_addr,     // Scene word address
    input wire scene_ready,            // Scene read completed
    input wire [31:0] scene_data,      // Scene word read
    output reg fb_req,                 // Framebuffer write request
    output reg [F-1:0] fb_addr,        // Result word address
    output reg [31:0] fb_data,         // Closest triangle ID
    input wire fb_ready,               // Framebuffer write completed
    output reg [2:0] core_state,       // State exposed to the execution log
    output wire [3:0] traversal_state  // Traversal state for the log
);
    localparam IDLE = 0, LOAD = 1, START = 2, WAIT = 3, WRITE = 4;
    reg [15:0] id;
    reg [3:0] index;
    reg [287:0] ray;
    wire traversal_req;
    wire traversal_done;
    wire [A-1:0] traversal_addr;
    wire [31:0] result;

    assign busy = (core_state != IDLE);

    traversal #(.A(A)) traversal_instance (
        .clk(clk),
        .reset(reset),
        .start(core_state == START),
        .ray(ray),
        .req(traversal_req),
        .addr(traversal_addr),
        .ready(scene_ready),
        .data(scene_data),
        .done(traversal_done),
        .result(result),
        .state(traversal_state)
    );

    // Select the core's ray loader or the traversal unit as scene requester.
    always @* begin
        scene_req = 0;
        scene_addr = 0;
        fb_req = 0;
        fb_addr = id;
        fb_data = result;
        if (core_state == LOAD) begin
            scene_req = 1;
            scene_addr = id * 9 + index;
        end
        if (core_state == WAIT) begin
            scene_req = traversal_req;
            scene_addr = traversal_addr;
        end
        if (core_state == WRITE) begin
            fb_req = 1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            core_state <= IDLE;
            id <= 0;
            index <= 0;
            ray <= 0;
        end else begin
            case (core_state)
                IDLE: begin
                    if (launch) begin
                        id <= ray_id;
                        index <= 0;
                        core_state <= LOAD;
                    end
                end
                LOAD: begin
                    if (scene_ready) begin
                        ray[index*32 +: 32] <= scene_data;
                        if (index == 8) begin
                            core_state <= START;
                        end else begin
                            index <= index + 1;
                        end
                    end
                end
                START: begin
                    core_state <= WAIT;
                end
                WAIT: begin
                    if (traversal_done) begin
                        core_state <= WRITE;
                    end
                end
                WRITE: begin
                    if (fb_ready) begin
                        core_state <= IDLE;
                    end
                end
                default: begin
                    core_state <= IDLE;
                end
            endcase
        end
    end
endmodule

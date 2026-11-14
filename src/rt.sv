`default_nettype none
`timescale 1ns/1ns

// TINY-RT
// > Dispatches host-generated rays to a configurable number of RT cores.
// > Arbitrates scene reads and framebuffer writes through separate controllers.
module rt #(
    parameter NUM_CORES = 2,            // Concurrent RT cores
    parameter SCENE_ADDR_BITS = 16,     // Scene word address width
    parameter SCENE_DATA_BITS = 32,     // Scene word width (must be 32)
    parameter SCENE_CHANNELS = 1,       // Concurrent scene read channels
    parameter FB_ADDR_BITS = 16,        // Framebuffer word address width
    parameter FB_DATA_BITS = 32,        // Framebuffer word width (must be 32)
    parameter FB_CHANNELS = 1          // Concurrent framebuffer channels
) (
    input wire clk,                                              // Clock
    input wire reset,                                            // Reset device
    input wire start,                                            // Start launch
    input wire device_control_write_enable,                      // Write ray count
    input wire [15:0] device_control_data,                       // Host ray count
    output wire done,                                            // Launch finished
    output wire [SCENE_CHANNELS-1:0] scene_mem_read_valid,       // Scene requests
    output wire [SCENE_CHANNELS*SCENE_ADDR_BITS-1:0] scene_mem_read_address, // Addresses
    input wire [SCENE_CHANNELS-1:0] scene_mem_read_ready,         // Scene completions
    input wire [SCENE_CHANNELS*SCENE_DATA_BITS-1:0] scene_mem_read_data, // Read words
    output wire [FB_CHANNELS-1:0] fb_mem_write_valid,             // Result requests
    output wire [FB_CHANNELS*FB_ADDR_BITS-1:0] fb_mem_write_address, // Result addresses
    output wire [FB_CHANNELS*FB_DATA_BITS-1:0] fb_mem_write_data, // Result words
    input wire [FB_CHANNELS-1:0] fb_mem_write_ready             // Write completions
);
    wire [15:0] count, id;
    wire [NUM_CORES-1:0] launch, busy, sreq, sready, freq, fready;
    wire [NUM_CORES*SCENE_ADDR_BITS-1:0] saddr;
    wire [NUM_CORES*32-1:0] sdata, fdata;
    wire [NUM_CORES*FB_ADDR_BITS-1:0] faddr;

    dcr dcr_instance (
        .clk(clk),
        .reset(reset),
        .write_enable(device_control_write_enable),
        .data(device_control_data),
        .ray_count(count)
    );

    dispatch #(.N(NUM_CORES)) dispatch_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .count(count),
        .busy(busy),
        .launch(launch),
        .ray_id(id),
        .done(done)
    );

    // Each core has independent requests but shares the external channels.
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            wire [2:0] core_state;
            wire [3:0] traversal_state;
            core #(.A(SCENE_ADDR_BITS), .F(FB_ADDR_BITS)) core_instance (
                .clk(clk),
                .reset(reset),
                .launch(launch[i]),
                .ray_id(id),
                .busy(busy[i]),
                .scene_req(sreq[i]),
                .scene_addr(saddr[i*SCENE_ADDR_BITS +: SCENE_ADDR_BITS]),
                .scene_ready(sready[i]),
                .scene_data(sdata[i*32 +: 32]),
                .fb_req(freq[i]),
                .fb_addr(faddr[i*FB_ADDR_BITS +: FB_ADDR_BITS]),
                .fb_data(fdata[i*32 +: 32]),
                .fb_ready(fready[i]),
                .core_state(core_state),
                .traversal_state(traversal_state)
            );
        end
    endgenerate

    // Read-only scene controller; its write-data output is unused.
    controller #(.N(NUM_CORES), .C(SCENE_CHANNELS), .A(SCENE_ADDR_BITS), .D(32)) scene_controller (
        .clk(clk),
        .reset(reset),
        .req(sreq),
        .addr(saddr),
        .wdata({NUM_CORES*32{1'b0}}),
        .ready(sready),
        .rdata(sdata),
        .mem_valid(scene_mem_read_valid),
        .mem_addr(scene_mem_read_address),
        .mem_wdata(),
        .mem_ready(scene_mem_read_ready),
        .mem_rdata(scene_mem_read_data)
    );

    // Write-only framebuffer controller; its read-data output is unused.
    controller #(.N(NUM_CORES), .C(FB_CHANNELS), .A(FB_ADDR_BITS), .D(32)) fb_controller (
        .clk(clk),
        .reset(reset),
        .req(freq),
        .addr(faddr),
        .wdata(fdata),
        .ready(fready),
        .rdata(),
        .mem_valid(fb_mem_write_valid),
        .mem_addr(fb_mem_write_address),
        .mem_wdata(fb_mem_write_data),
        .mem_ready(fb_mem_write_ready),
        .mem_rdata({FB_CHANNELS*32{1'b0}})
    );
endmodule

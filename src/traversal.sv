`default_nettype none
`timescale 1ns/1ns

// BVH TRAVERSAL
// > Reads nodes and triangles, tests them, and retains the closest hit.
// > A small stack holds right children while the left subtree is visited.
module traversal #(parameter A = 16) (
    input wire clk,                 // Clock
    input wire reset,               // Reset traversal
    input wire start,               // Begin a new ray
    input wire [287:0] ray,         // Packed origin, direction, inverse direction
    output reg req,                 // Scene memory read request
    output reg [A-1:0] addr,        // Scene word address
    input wire ready,               // Memory read completed
    input wire [31:0] data,         // Memory word read
    output reg done,                // Traversal finished
    output reg [31:0] result,       // Closest triangle ID or miss sentinel
    output reg [3:0] state          // Current traversal state
);
    localparam NODE_BASE = 40960;
    localparam TRI_BASE = 49152;
    localparam IDLE = 0, NODE = 1, BOX = 2, TRI = 3;
    localparam TEST = 4, NEXT = 5, FINISH = 6;

    // Node and triangle reads reuse the same nine-word scratch buffer.
    reg [31:0] words [0:8];
    reg [3:0] index;
    reg [31:0] node, first, remaining, tri_id;
    reg signed [63:0] best_t, best_det;
    reg have_best;

    // The ray is packed in scene-memory order, one signed Q16.16 word per axis.
    wire signed [31:0] ray_origin_x = ray[0 +: 32];
    wire signed [31:0] ray_origin_y = ray[32 +: 32];
    wire signed [31:0] ray_origin_z = ray[64 +: 32];
    wire signed [31:0] ray_dir_x = ray[96 +: 32];
    wire signed [31:0] ray_dir_y = ray[128 +: 32];
    wire signed [31:0] ray_dir_z = ray[160 +: 32];
    wire signed [31:0] ray_inv_dir_x = ray[192 +: 32];
    wire signed [31:0] ray_inv_dir_y = ray[224 +: 32];
    wire signed [31:0] ray_inv_dir_z = ray[256 +: 32];

    // Interpret the scratch words as a node after the NODE read.
    wire [31:0] node_min_x = words[0];
    wire [31:0] node_min_y = words[1];
    wire [31:0] node_min_z = words[2];
    wire [31:0] node_max_x = words[3];
    wire [31:0] node_max_y = words[4];
    wire [31:0] node_max_z = words[5];
    wire [31:0] node_left_or_first = words[6];
    wire [31:0] node_count = words[7];

    // The same scratch words become triangle vertices after the TRI read.
    wire signed [31:0] tri_v0_x = words[0];
    wire signed [31:0] tri_v0_y = words[1];
    wire signed [31:0] tri_v0_z = words[2];
    wire signed [31:0] tri_v1_x = words[3];
    wire signed [31:0] tri_v1_y = words[4];
    wire signed [31:0] tri_v1_z = words[5];
    wire signed [31:0] tri_v2_x = words[6];
    wire signed [31:0] tri_v2_y = words[7];
    wire signed [31:0] tri_v2_z = words[8];

    wire stack_empty, stack_full;
    wire [31:0] stack_top;
    wire box_hit, tri_hit;
    wire signed [63:0] new_t, new_det;
    wire stack_push = (state == BOX && box_hit && node_count == 0);
    wire stack_pop = (state == NEXT && !stack_empty);

    stack stack_instance (
        .clk(clk),
        .reset(reset),
        .clear(start),
        .push(stack_push),
        .pop(stack_pop),
        .in_node(node_left_or_first + 1),
        .top(stack_top),
        .empty(stack_empty),
        .full(stack_full)
    );

    box_test box_instance (
        .ox(ray_origin_x),
        .oy(ray_origin_y),
        .oz(ray_origin_z),
        .dx(ray_dir_x),
        .dy(ray_dir_y),
        .dz(ray_dir_z),
        .ix(ray_inv_dir_x),
        .iy(ray_inv_dir_y),
        .iz(ray_inv_dir_z),
        .minx(node_min_x),
        .miny(node_min_y),
        .minz(node_min_z),
        .maxx(node_max_x),
        .maxy(node_max_y),
        .maxz(node_max_z),
        .hit(box_hit)
    );

    tri_test tri_instance (
        .ox(ray_origin_x),
        .oy(ray_origin_y),
        .oz(ray_origin_z),
        .dx(ray_dir_x),
        .dy(ray_dir_y),
        .dz(ray_dir_z),
        .ax(tri_v0_x),
        .ay(tri_v0_y),
        .az(tri_v0_z),
        .bx(tri_v1_x),
        .by(tri_v1_y),
        .bz(tri_v1_z),
        .cx(tri_v2_x),
        .cy(tri_v2_y),
        .cz(tri_v2_z),
        .best_t(best_t),
        .best_det(best_det),
        .have_best(have_best),
        .hit(tri_hit),
        .t_out(new_t),
        .det_out(new_det)
    );

    // Keep the current word request asserted until the controller returns ready.
    always @* begin
        req = 0;
        addr = 0;
        if (state == NODE) begin
            req = 1;
            addr = NODE_BASE + node * 8 + index;
        end else if (state == TRI) begin
            req = 1;
            addr = TRI_BASE + tri_id * 9 + index;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            result <= 32'hffffffff;
            index <= 0;
            node <= 0;
            have_best <= 0;
            best_t <= 0;
            best_det <= 0;
            first <= 0;
            remaining <= 0;
            tri_id <= 0;
        end else begin
            case (state)
                // IDLE: initialize a new ray at root node zero.
                IDLE: begin
                    if (start) begin
                        done <= 0;
                        result <= 32'hffffffff;
                        have_best <= 0;
                        node <= 0;
                        index <= 0;
                        state <= NODE;
                    end
                end

                // NODE: fetch the eight words needed to decide where to go.
                NODE: begin
                    if (ready) begin
                        words[index] <= data;
                        if (index == 7) begin
                            index <= 0;
                            state <= BOX;
                        end else begin
                            index <= index + 1;
                        end
                    end
                end

                // BOX: skip misses, descend left on internal hits, or start
                // the leaf. A right child is pushed in parallel with descent.
                BOX: begin
                    if (!box_hit) begin
                        state <= NEXT;
                    end else if (node_count == 0) begin
                        node <= node_left_or_first;
                        state <= NODE;
                    end else begin
                        first <= node_left_or_first;
                        tri_id <= node_left_or_first;
                        remaining <= node_count;
                        state <= TRI;
                    end
                end

                // TRI: fetch all three vertices of the current leaf triangle.
                TRI: begin
                    if (ready) begin
                        words[index] <= data;
                        if (index == 8) begin
                            index <= 0;
                            state <= TEST;
                        end else begin
                            index <= index + 1;
                        end
                    end
                end

                // TEST: retain a closer hit, then continue through this leaf.
                TEST: begin
                    if (tri_hit) begin
                        result <= tri_id;
                        have_best <= 1;
                        best_t <= new_t;
                        best_det <= new_det;
                    end
                    if (remaining > 1) begin
                        remaining <= remaining - 1;
                        tri_id <= tri_id + 1;
                        state <= TRI;
                    end else begin
                        state <= NEXT;
                    end
                end

                // NEXT: resume a deferred right subtree, or finish if empty.
                NEXT: begin
                    if (stack_empty) begin
                        state <= FINISH;
                    end else begin
                        node <= stack_top;
                        state <= NODE;
                    end
                end

                // FINISH: make the result visible to the core for one cycle.
                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

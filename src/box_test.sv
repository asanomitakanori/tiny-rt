`default_nettype none
`timescale 1ns/1ns

// BOX TEST
// > Intersects a ray with an axis-aligned bounding box using slabs.
// > Directions and host-precomputed inverse directions are signed Q16.16.
module box_test (
    input wire signed [31:0] ox,    // Ray origin X
    input wire signed [31:0] oy,    // Ray origin Y
    input wire signed [31:0] oz,    // Ray origin Z
    input wire signed [31:0] dx,    // Ray direction X
    input wire signed [31:0] dy,    // Ray direction Y
    input wire signed [31:0] dz,    // Ray direction Z
    input wire signed [31:0] ix,    // Inverse direction X
    input wire signed [31:0] iy,    // Inverse direction Y
    input wire signed [31:0] iz,    // Inverse direction Z
    input wire signed [31:0] minx,  // Box minimum X
    input wire signed [31:0] miny,  // Box minimum Y
    input wire signed [31:0] minz,  // Box minimum Z
    input wire signed [31:0] maxx,  // Box maximum X
    input wire signed [31:0] maxy,  // Box maximum Y
    input wire signed [31:0] maxz,  // Box maximum Z
    output reg hit                  // Ray overlaps all three slabs
);
    reg signed [63:0] lo, hi, a, b, tmp;
    reg signed [31:0] o, d, inv, mn, mx;
    integer axis;

    always @* begin
        // Start with the forward ray interval [0, infinity).
        lo = 0;
        hi = 64'sh7fffffffffffffff;
        hit = 1;

        for (axis = 0; axis < 3; axis = axis + 1) begin
            case (axis)
                0: begin
                    o = ox;
                    d = dx;
                    inv = ix;
                    mn = minx;
                    mx = maxx;
                end
                1: begin
                    o = oy;
                    d = dy;
                    inv = iy;
                    mn = miny;
                    mx = maxy;
                end
                default: begin
                    o = oz;
                    d = dz;
                    inv = iz;
                    mn = minz;
                    mx = maxz;
                end
            endcase

            // A parallel ray must already be inside this slab.
            if (d == 0) begin
                if (o < mn || o > mx) begin
                    hit = 0;
                end
            end else begin
                // Q16.16 * Q16.16 gives Q32.32; shift back to Q16.16.
                a = (($signed(mn) - $signed(o)) * $signed(inv)) >>> 16;
                b = (($signed(mx) - $signed(o)) * $signed(inv)) >>> 16;
                if (a > b) begin
                    tmp = a;
                    a = b;
                    b = tmp;
                end
                if (a > lo) begin
                    lo = a;
                end
                if (b < hi) begin
                    hi = b;
                end
            end
        end
        // Empty intersection means at least one slab excludes the ray.
        if (hi < lo) begin
            hit = 0;
        end
    end
endmodule

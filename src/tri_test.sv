`default_nettype none
`timescale 1ns/1ns

// TRIANGLE TEST
// > Moller-Trumbore intersection using signed Q16.16 arithmetic.
// > Keeps t/det as a rational number, avoiding a hardware divider.
module tri_test (
    input wire signed [31:0] ox,      // Ray origin X
    input wire signed [31:0] oy,      // Ray origin Y
    input wire signed [31:0] oz,      // Ray origin Z
    input wire signed [31:0] dx,      // Ray direction X
    input wire signed [31:0] dy,      // Ray direction Y
    input wire signed [31:0] dz,      // Ray direction Z
    input wire signed [31:0] ax,      // Vertex 0 X
    input wire signed [31:0] ay,      // Vertex 0 Y
    input wire signed [31:0] az,      // Vertex 0 Z
    input wire signed [31:0] bx,      // Vertex 1 X
    input wire signed [31:0] by,      // Vertex 1 Y
    input wire signed [31:0] bz,      // Vertex 1 Z
    input wire signed [31:0] cx,      // Vertex 2 X
    input wire signed [31:0] cy,      // Vertex 2 Y
    input wire signed [31:0] cz,      // Vertex 2 Z
    input wire signed [63:0] best_t,  // Previous distance numerator
    input wire signed [63:0] best_det,// Previous distance denominator
    input wire have_best,             // A previous hit exists
    output reg hit,                   // This triangle is the closest so far
    output reg signed [63:0] t_out,   // New distance numerator
    output reg signed [63:0] det_out  // New distance denominator
);
    reg signed [63:0] e1x, e1y, e1z, e2x, e2y, e2z;
    reg signed [63:0] px, py, pz, sx, sy, sz, qx, qy, qz;
    reg signed [63:0] det, u, v, t;
    reg signed [127:0] lhs, rhs;

    // Shift each product independently, matching Python's floor rounding.
    function signed [63:0] mul(input signed [63:0] a, b);
        reg signed [127:0] product;
        begin
            product = a * b;
            mul = product >>> 16;
        end
    endfunction

    always @* begin
        // Edge vectors from vertex 0, still in Q16.16.
        e1x = $signed(bx) - $signed(ax);
        e1y = $signed(by) - $signed(ay);
        e1z = $signed(bz) - $signed(az);
        e2x = $signed(cx) - $signed(ax);
        e2y = $signed(cy) - $signed(ay);
        e2z = $signed(cz) - $signed(az);

        // pvec = direction cross edge2; det = edge1 dot pvec.
        px = mul(dy, e2z) - mul(dz, e2y);
        py = mul(dz, e2x) - mul(dx, e2z);
        pz = mul(dx, e2y) - mul(dy, e2x);
        det = mul(e1x, px) + mul(e1y, py) + mul(e1z, pz);

        // u numerator uses the vector from vertex 0 to the ray origin.
        sx = $signed(ox) - $signed(ax);
        sy = $signed(oy) - $signed(ay);
        sz = $signed(oz) - $signed(az);
        u = mul(sx, px) + mul(sy, py) + mul(sz, pz);

        // qvec supplies the v and distance numerators.
        qx = mul(sy, e1z) - mul(sz, e1y);
        qy = mul(sz, e1x) - mul(sx, e1z);
        qz = mul(sx, e1y) - mul(sy, e1x);
        v = mul(dx, qx) + mul(dy, qy) + mul(dz, qz);
        t = mul(e2x, qx) + mul(e2y, qy) + mul(e2z, qz);

        // Normalize the sign so all inside-triangle comparisons use det > 0.
        if (det < 0) begin
            det = -det;
            u = -u;
            v = -v;
            t = -t;
        end

        // Compare t/det with best_t/best_det using full-width products.
        lhs = t * best_det;
        rhs = best_t * det;
        hit = (det > 0 && u >= 0 && v >= 0 && u + v <= det && t > 0 &&
               (!have_best || lhs < rhs));
        t_out = t;
        det_out = det;
    end
endmodule

module sa #(
    parameter N = 2,
    parameter W = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic en,

    input  logic cfg_is4b,
    input  logic cfg_is_signed,
    input  logic set_w,

    input  logic [N*W-1:0] in_a_flat,
    input  logic [N*W-1:0] in_w_flat,
    input  logic [N*4*W-1:0] acc_in_flat,

    output logic [N*W-1:0] out_a_flat,
    output logic [N*W-1:0] out_w_flat,
    output logic [N*4*W-1:0] acc_out_flat
);

    logic [W-1:0] in_a [0:N-1];
    logic [W-1:0] in_w [0:N-1];
    logic [4*W-1:0] acc_in [0:N-1];

    logic [W-1:0] out_a [0:N-1];
    logic [W-1:0] out_w [0:N-1];
    logic [4*W-1:0] acc_out [0:N-1];

    logic [W-1:0] a_wire [0:N][0:N-1];
    logic [W-1:0] w_wire [0:N][0:N-1];
    logic [4*W-1:0] acc_wire [0:N][0:N-1];

    logic cfg_is4b_out_wire [0:N-1][0:N];
    logic cfg_is_signed_out_wire [0:N-1][0:N];

    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : FLAT_MAP
            assign in_a[k]   = in_a_flat[(k+1)*W-1 : k*W];
            assign in_w[k]   = in_w_flat[(k+1)*W-1 : k*W];
            assign acc_in[k] = acc_in_flat[(k+1)*4*W-1 : k*4*W];

            assign out_a_flat[(k+1)*W-1 : k*W] = out_a[k];
            assign out_w_flat[(k+1)*W-1 : k*W] = out_w[k];
            assign acc_out_flat[(k+1)*4*W-1 : k*4*W] = acc_out[k];
        end
    endgenerate

    genvar r, c;
    generate
        for (c = 0; c < N; c = c + 1) begin : tie_north
            assign a_wire[0][c] = in_a[c];
        end

        for (r = 0; r < N; r = r + 1) begin : tie_west
            assign w_wire[0][r]   = in_w[r];
            assign acc_wire[0][r] = acc_in[r];
            assign cfg_is4b_out_wire[r][0]      = cfg_is4b;
            assign cfg_is_signed_out_wire[r][0] = cfg_is_signed;
        end

        for (c = 0; c < N; c = c + 1) begin : tie_south
            assign out_a[c] = a_wire[N][c];
        end

        for (r = 0; r < N; r = r + 1) begin : tie_east
            assign out_w[r]   = w_wire[N][r];
            assign acc_out[r] = acc_wire[N][r];
        end

        for (r = 0; r < N; r = r + 1) begin : rows
            for (c = 0; c < N; c = c + 1) begin : cols
                pe #(
                    .W(W)
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .cfg_is4b(cfg_is4b_out_wire[r][c]),
                    .cfg_is_signed(cfg_is_signed_out_wire[r][c]),
                    .en(en),
                    .set_w(set_w),
                    .cfg_is4b_out(cfg_is4b_out_wire[r][c+1]),
                    .cfg_is_signed_out(cfg_is_signed_out_wire[r][c+1]),
                    .in_a(a_wire[r][c]),
                    .out_a(a_wire[r+1][c]),
                    .in_w(w_wire[c][r]),
                    .out_w(w_wire[c+1][r]),
                    .acc_in(acc_wire[c][r]),
                    .acc_out(acc_wire[c+1][r])
                );
            end
        end
    endgenerate

endmodule
module delay_pipe #(
    parameter D_WIDTH = 8,
    parameter LATENCY = 1
) (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic [D_WIDTH-1:0] data_in,
    input  logic clear,
    output logic [D_WIDTH-1:0] data_out
);

    logic [D_WIDTH-1:0] pipe [0:LATENCY-1];
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < LATENCY; i = i + 1)
                pipe[i] <= '0;
        end else if (clear) begin
            for (i = 0; i < LATENCY; i = i + 1)
                pipe[i] <= '0;
        end else if (en) begin
            pipe[0] <= data_in;
            for (i = 0; i < LATENCY-1; i = i + 1)
                pipe[i+1] <= pipe[i];
        end
    end

    assign data_out = pipe[LATENCY-1];

endmodule


module sa_top #(
    parameter N = 4,
    parameter W = 8
) (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic valid_a,
    input  logic clear,

    input  logic cfg_is4b,
    input  logic cfg_is_signed,
    input  logic set_w,

    input  logic [N*W-1:0] in_a_flat,
    input  logic [N*W-1:0] in_w_flat,
    output logic [N*4*W-1:0] result_out_flat,
    output logic valid_out
);

    logic [W-1:0] sa_in_a_ext [0:N-1];
    logic [W-1:0] sa_in_w_ext [0:N-1];
    logic [W-1:0] sa_in_a     [0:N-1];
    logic [4*W-1:0] sa_acc_out [0:N-1];
    logic [4*W-1:0] result_out_arr [0:N-1];

    logic [N*W-1:0] sa_in_a_flat_sig;
    logic [N*W-1:0] sa_in_w_flat_sig;
    logic [N*4*W-1:0] sa_acc_out_flat_sig;
    logic [N*4*W-1:0] zero_acc_flat;

    assign zero_acc_flat = '0;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : FLAT_IO_MAP
            assign sa_in_a_ext[i] = in_a_flat[(i+1)*W-1 : i*W];
            assign sa_in_w_ext[i] = in_w_flat[(i+1)*W-1 : i*W];

            assign sa_in_a_flat_sig[(i+1)*W-1 : i*W] = sa_in_a[i];
            assign sa_in_w_flat_sig[(i+1)*W-1 : i*W] = sa_in_w_ext[i];

            assign sa_acc_out[i] = sa_acc_out_flat_sig[(i+1)*4*W-1 : i*4*W];
            assign result_out_flat[(i+1)*4*W-1 : i*4*W] = result_out_arr[i];
        end
    endgenerate

    assign sa_in_a[0] = sa_in_a_ext[0];

    generate
        genvar c;
        for (c = 1; c < N; c = c + 1) begin : skew_inputs
            delay_pipe #(
                .D_WIDTH(W),
                .LATENCY(c)
            ) skew_a (
                .clk(clk),
                .rst_n(rst_n),
                .en(en),
                .clear(1'b0),
                .data_in(sa_in_a_ext[c]),
                .data_out(sa_in_a[c])
            );
        end
    endgenerate

    sa #(
        .N(N),
        .W(W)
    ) sa_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .cfg_is4b(cfg_is4b),
        .cfg_is_signed(cfg_is_signed),
        .set_w(set_w),
        .in_a_flat(sa_in_a_flat_sig),
        .in_w_flat(sa_in_w_flat_sig),
        .acc_in_flat(zero_acc_flat),
        .out_a_flat(),
        .out_w_flat(),
        .acc_out_flat(sa_acc_out_flat_sig)
    );

    generate
        genvar r;
        for (r = 0; r < N-1; r = r + 1) begin : deskew_outputs
            delay_pipe #(
                .D_WIDTH(4*W),
                .LATENCY(N-r-1)
            ) deskew_acc (
                .clk(clk),
                .rst_n(rst_n),
                .en(en),
                .clear(1'b0),
                .data_in(sa_acc_out[r]),
                .data_out(result_out_arr[r])
            );
        end
    endgenerate

    assign result_out_arr[N-1] = sa_acc_out[N-1];

    delay_pipe #(
        .D_WIDTH(1),
        .LATENCY(2*N-1)
    ) valid_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .clear(clear),
        .data_in(valid_a),
        .data_out(valid_out)
    );

endmodule
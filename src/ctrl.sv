module ctrl #(
    parameter BUS_W = 8,
    parameter FULL_WIDTH = 4,
    parameter N = 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic input_valid,
    input  logic [BUS_W-1:0] data_in, // MSB->LSB

    output logic write_enable,
    output logic [BUS_W-1:0] data_out
);

    localparam OPCODE_NOP      = 4'b0000;
    localparam OPCODE_SET_MODE = 4'b0010; // [0010_00PS]
    localparam OPCODE_SET_DIM  = 4'b0100;
    localparam OPCODE_LOAD_W   = 4'b0110;
    localparam OPCODE_EXEC     = 4'b1000;

    logic sa_enable, sa_valid_a, sa_clear, sa_set_w, set_4b, set_signed, set_dim;
    logic cfg_is4b, cfg_is_signed;
    logic [3:0] num_activations;

    logic [1:0] cntr0;
    logic [3:0] cntr1;
    logic rst_cntr0, rst_cntr1, incr_cntr0, incr_cntr1;

    // flat SA interface
    logic [N*FULL_WIDTH-1:0] sa_in_flat;
    logic [N*4*FULL_WIDTH-1:0] flat_sa_acc_out;
    logic sa_acc_out_valid;

    // counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cntr0 <= '0;
            cntr1 <= '0;
        end else begin
            if (rst_cntr0) cntr0 <= '0;
            else if (incr_cntr0) cntr0 <= cntr0 + 1'b1;

            if (rst_cntr1) cntr1 <= '0;
            else if (incr_cntr1) cntr1 <= cntr1 + 1'b1;
        end
    end

    // config registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_is4b       <= 1'b0;
            cfg_is_signed  <= 1'b0;
            num_activations <= '0;
        end else begin
            if (set_4b)      cfg_is4b <= data_in[1];
            if (set_signed)  cfg_is_signed <= data_in[0];
            if (set_dim)     num_activations <= data_in[3:0];
        end
    end

    // pack input bus into flat SA input lanes
    assign sa_in_flat[FULL_WIDTH-1:0] = data_in[3:0];

    generate
        if (N > 1) begin : GEN_LANE1
            assign sa_in_flat[2*FULL_WIDTH-1:FULL_WIDTH] = data_in[7:4];
        end
        if (N > 2) begin : GEN_ZERO_UNUSED
            genvar t;
            for (t = 2; t < N; t = t + 1) begin : ZERO_UNUSED
                assign sa_in_flat[(t+1)*FULL_WIDTH-1:t*FULL_WIDTH] = '0;
            end
        end
    endgenerate

    assign data_out =
        (cntr0 == 2'd0) ? flat_sa_acc_out[7:0]   :
        (cntr0 == 2'd1) ? flat_sa_acc_out[15:8]  :
        (cntr0 == 2'd2) ? flat_sa_acc_out[23:16] :
                          flat_sa_acc_out[31:24];

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOADING_W,
        STATE_COMPUTE,
        STATE_COMPUTE_WB
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= STATE_IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state   = state;
        sa_enable    = 1'b0;
        sa_valid_a   = (cntr1 < num_activations);
        sa_clear     = 1'b0;
        sa_set_w     = 1'b0;
        set_4b       = 1'b0;
        set_signed   = 1'b0;
        set_dim      = 1'b0;
        write_enable = 1'b0;
        rst_cntr0    = 1'b0;
        incr_cntr0   = 1'b0;
        rst_cntr1    = 1'b0;
        incr_cntr1   = 1'b0;

        case (state)
            STATE_IDLE: begin
                if (input_valid) begin
                    case (data_in[7:4])
                        OPCODE_SET_MODE: begin
                            set_4b     = 1'b1;
                            set_signed = 1'b1;
                        end

                        OPCODE_SET_DIM: begin
                            set_dim = 1'b1;
                        end

                        OPCODE_LOAD_W: begin
                            next_state = STATE_LOADING_W;
                            rst_cntr1  = 1'b1;
                        end

                        OPCODE_EXEC: begin
                            sa_clear   = 1'b1;
                            rst_cntr1  = 1'b1;
                            rst_cntr0  = 1'b1;
                            next_state = STATE_COMPUTE;
                        end

                        default: begin
                            next_state = STATE_IDLE;
                        end
                    endcase
                end
            end

            STATE_LOADING_W: begin
                if (input_valid) begin
                    sa_set_w   = 1'b1;
                    incr_cntr1 = 1'b1;
                    sa_enable  = 1'b1;

                    if (cntr1 == (N-1))
                        next_state = STATE_IDLE;
                    else
                        next_state = STATE_LOADING_W;
                end
            end

            STATE_COMPUTE: begin
                if (input_valid) begin
                    sa_enable  = ~sa_acc_out_valid;
                    incr_cntr1 = (cntr1 != num_activations) & (~sa_acc_out_valid);

                    if (sa_acc_out_valid) begin
                        write_enable = 1'b1;
                        incr_cntr0   = 1'b1;
                        next_state   = STATE_COMPUTE_WB;
                    end
                end
            end

            STATE_COMPUTE_WB: begin
                if (input_valid) begin
                    if (sa_acc_out_valid) begin
                        write_enable = 1'b1;
                        incr_cntr0   = 1'b1;

                        if (cntr0 == 2'd3) begin
                            sa_enable = 1'b1;
                            if (cntr1 != num_activations)
                                incr_cntr1 = 1'b1;
                        end
                    end else begin
                        next_state = STATE_IDLE;
                    end
                end
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end

    sa_top #(
        .N(N),
        .W(FULL_WIDTH)
    ) sa_top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(sa_enable),
        .valid_a(sa_valid_a),
        .clear(sa_clear),
        .cfg_is4b(cfg_is4b),
        .cfg_is_signed(cfg_is_signed),
        .set_w(sa_set_w),
        .in_a_flat(sa_in_flat),
        .in_w_flat(sa_in_flat),
        .result_out_flat(flat_sa_acc_out),
        .valid_out(sa_acc_out_valid)
    );

endmodule
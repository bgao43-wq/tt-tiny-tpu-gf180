module pe #(
    parameter int W = 4
) (
    input  logic        clk,
    input  logic        rst_n,

    // --- Control ---
    input  logic        cfg_is4b,      // 0: 8-bit mode | 1: Dual 4-bit mode
    input  logic        cfg_is_signed, 
    input  logic        en,            // Global enable / clock gate
    input  logic        set_w,         // When high, `in_w` is stored into the weight register.
    output logic        cfg_is4b_out,  // Flopped output of cfg_is4b
    output logic        cfg_is_signed_out, // Flopped output of cfg_is_signed

    // --- Data Path: Activations (Moving North to South) ---
    input  logic [W-1:0]  in_a,          // {a_h, a_l} in 4b mode
    output logic [W-1:0]  out_a,         // Flopped output in_a

    // --- Data Path: Weights (Moving West to East) ---
    input  logic [W-1:0]  in_w,          // {w_h, w_l} in 4b mode
    output logic [W-1:0]  out_w,         // Flopped output of in_w

    // --- Data Path: Accumulation (Moving West to East) ---
    // 32-bit width to avoid overflow across the array
    // In 4b mode: [31:16] is acc_hi, [15:0] is acc_lo
    input  logic [4*W-1:0] acc_in,        
    output logic [4*W-1:0] acc_out        
);

    // Internal pipeline registers for systolic flow
    logic [W-1:0]  a_reg, w_reg;
    logic [4*W-1:0] acc_reg;

    // --- Weight register update ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg <= 0;
        end else if (en && set_w) begin
            w_reg <= in_w; // Update weight register only when set_w is high
        end
    end


    // --- Arithmetic Logic ---
    logic        [2*W-1:0] product;
    logic signed [W/2:0]  a_ext_lo, a_ext_hi, w_ext_lo, w_ext_hi;
    logic signed [W+1:0]  prod_Hh, prod_Hl, prod_Lh, prod_Ll;
    logic signed [2*W-1:0] shifted_Hl, shifted_Lh;

    // Multiplication
    // Sign-extend inputs based on mode and signedness
    // lower 4 bits are always zero-extended, except in 4b-signed mode,
    // because in all 8-bit mode, w = (w_h<<4) + w_l, w_l is effectively unsigned.
    assign a_ext_lo = (cfg_is4b & cfg_is_signed) ? {in_a[W/2-1], in_a[W/2-1:0]} : {1'b0, in_a[W/2-1:0]};
    assign w_ext_lo = (cfg_is4b & cfg_is_signed) ? {w_reg[W/2-1], w_reg[W/2-1:0]} : {1'b0, w_reg[W/2-1:0]};
    assign a_ext_hi = cfg_is_signed ? {in_a[W-1], in_a[W-1:W/2]} : {1'b0, in_a[W-1:W/2]};
    assign w_ext_hi = cfg_is_signed ? {w_reg[W-1], w_reg[W-1:W/2]} : {1'b0, w_reg[W-1:W/2]};

    // Compute partial products
    assign prod_Hh = a_ext_hi * w_ext_hi;
    assign prod_Hl = a_ext_hi * w_ext_lo;
    assign prod_Lh = a_ext_lo * w_ext_hi;
    assign prod_Ll = a_ext_lo * w_ext_lo;
    assign shifted_Hl = (2*W)'(prod_Hl) <<< (W/2);
    assign shifted_Lh = (2*W)'(prod_Lh) <<< (W/2);

    // Combine partial products into the final product
    assign product = cfg_is4b ? {prod_Hh[W-1:0], prod_Ll[W-1:0]} :
                     {{prod_Hh[W-1:0], {W{1'b0}}} + shifted_Hl + shifted_Lh + (2*W)'(prod_Ll)};

    // Accumulate the product with the incoming accumulator value
    logic [2*W-1:0] sum_lo, sum_hi;
    logic carry;
    // In 4b mode, the upper 8 bits of the product are added to the corresponding accumulator, according to the signedness
    assign         sum_hi  = acc_in[4*W-1:2*W] + (cfg_is4b ? (cfg_is_signed ? {{W{product[2*W-1]}}, product[2*W-1:W]} : product[2*W-1:W]) :
    // In 8b mode, the upper 8 bits of the product are either all zeros or all sign bits, plus carry from the lower addition
                                                        (cfg_is_signed ? {(2*W){product[2*W-1]}} + carry : carry));
    // In 4b mode, same for both lower and upper half.
    assign {carry, sum_lo} = acc_in[2*W-1:0]  + (cfg_is4b ? (cfg_is_signed ? {{W{product[W-1]}}, product[W-1:0]} : product[W-1:0]) :
    // In 8b mode, the lower 8 bits of the product are directly added to the accumulator
                                                         product[2*W-1:0]);
                                    

    // --- Register data flow ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg   <= 0;
            acc_reg <= 0;
            cfg_is4b_out <= 0;
            cfg_is_signed_out <= 0;
        end else if (en) begin
            a_reg   <= in_a;
            acc_reg <= {sum_hi, sum_lo}; // Update accumulator with the new sum
            cfg_is4b_out <= cfg_is4b;
            cfg_is_signed_out <= cfg_is_signed;
        end
    end

    // register outputs
    assign out_a   = a_reg;
    assign out_w   = w_reg;
    assign acc_out = acc_reg;

endmodule

module pe_fixed #(
    parameter int W = 8
) (
    input  logic        clk,
    input  logic        rst_n,

    // --- Control ---
    input  logic        cfg_is4b,      // 0: 8-bit mode | 1: Dual 4-bit mode
    input  logic        cfg_is_signed, 
    input  logic        en,            // Global enable / clock gate
    input  logic        set_w,         // When high, `in_w` is stored into the weight register.
    output logic        cfg_is4b_out,  // Flopped output of cfg_is4b
    output logic        cfg_is_signed_out, // Flopped output of cfg_is_signed

    // --- Data Path: Activations (Moving North to South) ---
    input  logic [W-1:0]  in_a,          // {a_h, a_l} in 4b mode
    output logic [W-1:0]  out_a,         // Flopped output in_a

    // --- Data Path: Weights (Moving West to East) ---
    input  logic [W-1:0]  in_w,          // {w_h, w_l} in 4b mode
    output logic [W-1:0]  out_w,         // Flopped output of in_w

    // --- Data Path: Accumulation (Moving West to East) ---
    // 32-bit width to avoid overflow across the array
    // In 4b mode: [31:16] is acc_hi, [15:0] is acc_lo
    input  logic [4*W-1:0] acc_in,        
    output logic [4*W-1:0] acc_out        
);

    // Internal pipeline registers for systolic flow
    logic [W-1:0]  a_reg, w_reg;
    logic [4*W-1:0] acc_reg;

    // --- Weight register update ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg <= 0;
        end else if (en && set_w) begin
            w_reg <= in_w; // Update weight register only when set_w is high
        end
    end


    // --- Arithmetic Logic ---

    logic [W:0] a_ext, w_ext;
    logic signed [2*W+1:0] product_fixed;
    assign a_ext = cfg_is_signed ? {{in_a[W-1]}, in_a} : {1'b0, in_a};
    assign w_ext = cfg_is_signed ? {{w_reg[W-1]}, w_reg} : {1'b0, w_reg};

    assign product_fixed = a_ext * w_ext;

    // --- Register data flow ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg   <= 0;
            acc_reg <= 0;
            cfg_is4b_out <= 0;
            cfg_is_signed_out <= 0;
        end else if (en) begin
            a_reg   <= in_a;
            acc_reg <= product_fixed + acc_in; // Update accumulator with the new sum
            cfg_is4b_out <= cfg_is4b;
            cfg_is_signed_out <= cfg_is_signed;
        end
    end

    // register outputs
    assign out_a   = a_reg;
    assign out_w   = w_reg;
    assign acc_out = acc_reg;

endmodule
module hdmi_tmds_oserdes_xilinx (
    input  wire       pix_clk,
    input  wire       pix_5x_clk,
    input  wire       rst,
    input  wire [9:0] data,
    output wire       out_p,
    output wire       out_n
);
    wire serial_out;
    wire cascade_shift1;
    wire cascade_shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1)
    ) u_master (
        .OQ(serial_out),
        .OFB(),
        .TQ(),
        .TFB(),
        .SHIFTOUT1(),
        .SHIFTOUT2(),
        .CLK(pix_5x_clk),
        .CLKDIV(pix_clk),
        .D1(data[0]),
        .D2(data[1]),
        .D3(data[2]),
        .D4(data[3]),
        .D5(data[4]),
        .D6(data[5]),
        .D7(data[6]),
        .D8(data[7]),
        .OCE(1'b1),
        .RST(rst),
        .SHIFTIN1(cascade_shift1),
        .SHIFTIN2(cascade_shift2),
        .T1(1'b0),
        .T2(1'b0),
        .T3(1'b0),
        .T4(1'b0),
        .TBYTEIN(1'b0),
        .TCE(1'b0),
        .TBYTEOUT()
    );

    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"),
        .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10),
        .SERDES_MODE("SLAVE"),
        .TRISTATE_WIDTH(1)
    ) u_slave (
        .OQ(),
        .OFB(),
        .TQ(),
        .TFB(),
        .SHIFTOUT1(cascade_shift1),
        .SHIFTOUT2(cascade_shift2),
        .CLK(pix_5x_clk),
        .CLKDIV(pix_clk),
        .D1(1'b0),
        .D2(1'b0),
        .D3(data[8]),
        .D4(data[9]),
        .D5(1'b0),
        .D6(1'b0),
        .D7(1'b0),
        .D8(1'b0),
        .OCE(1'b1),
        .RST(rst),
        .SHIFTIN1(1'b0),
        .SHIFTIN2(1'b0),
        .T1(1'b0),
        .T2(1'b0),
        .T3(1'b0),
        .T4(1'b0),
        .TBYTEIN(1'b0),
        .TCE(1'b0),
        .TBYTEOUT()
    );

    OBUFDS #(.IOSTANDARD("TMDS_33")) u_obuf (
        .I(serial_out),
        .O(out_p),
        .OB(out_n)
    );
endmodule

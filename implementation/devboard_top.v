`timescale 1ns / 1ps

module devboard_top #( parameter CLK_FREQ = 32'd300_000_000 )(
	// Misc
	output wire [7:0] led,
	input wire [7:0] switch,
	input wire [3:0] button,
	input wire clk_100,
	input wire clk_synth0_p,
	input wire clk_synth0_n,
	
	//Ethernet
	input wire GTX_CLK_0,
	input wire ETH_REFCLK,
	 
	output wire ETH_RESET_0,
	output wire [7:0] GMII_TXD_0,
	output wire       GMII_TX_EN_0,
	output wire       GMII_TX_ER_0,
	output wire       GMII_TX_CLK_0,
	input wire  [7:0] GMII_RXD_0,
	input wire        GMII_RX_DV_0,
	input wire        GMII_RX_ER_0,
	input wire        GMII_RX_CLK_0,
	input wire        MII_TX_CLK_0,
	input wire        GMII_COL_0,
	input wire        GMII_CRS_0
);


wire clk_200;
wire locked;
wire rst_n = locked & !button[0];
wire rst = ~rst_n;
assign led[7:0] = {rst,rst,~rst, button, 1'b0};


DCM_BASE #(
 	.CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
 				//   7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
 	.CLKFX_DIVIDE(1), // Can be any integer from 1 to 32
 	.CLKFX_MULTIPLY(4), // Can be any integer from 2 to 32
 	.CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
 	.CLKIN_PERIOD(10.0), // Specify period of input clock in ns from 1.25 to 1000.00
 	.CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift mode of NONE or FIXED
 	.CLK_FEEDBACK("NONE"), // Specify clock feedback of NONE or 1X
 	.DCM_PERFORMANCE_MODE("MAX_SPEED"), // Can be MAX_SPEED or MAX_RANGE
 	.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
 						//   an integer from 0 to 15
 	.DFS_FREQUENCY_MODE("LOW"), // LOW or HIGH frequency mode for frequency synthesis
 	.DLL_FREQUENCY_MODE("LOW"), // LOW, HIGH, or HIGH_SER frequency mode for DLL
 	.DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
 	.FACTORY_JF(16'hf0f0), // FACTORY JF value suggested to be set to 16'hf0f0
 	.PHASE_SHIFT(0), // Amount of fixed phase shift from -255 to 1023
 	.STARTUP_WAIT("FALSE") // Delay configuration DONE until DCM LOCK, TRUE/FALSE
) DCM_BASE_inst (
 	.CLK0(CLK0),         // 0 degree DCM CLK output
 	.CLK180(CLK180),     // 180 degree DCM CLK output
 	.CLK270(CLK270),    // 270 degree DCM CLK output
 	.CLK2X(clk_200),    // 2X DCM CLK output
 	.CLK2X180(CLK2X180), // 2X, 180 degree DCM CLK out
 	.CLK90(CLK90),       // 90 degree DCM CLK output
 	.CLKDV(CLKDV),       // Divided DCM CLK out (CLKDV_DIVIDE)
 	.CLKFX(CLKFX),       // DCM CLK synthesis out (M/D)
 	.CLKFX180(CLKFX180), // 180 degree CLK synthesis out
 	.LOCKED(locked),     // DCM LOCK status output
 	.CLKFB(CLKFB),       // DCM clock feedback
	.CLKIN(clk_100),       // Clock input (from IBUFG, BUFG or DCM)
	.RST(1'b0)            // DCM asynchronous reset input
);

wire udp_rx_clk;
wire udp_tx_clk;
wire [7:0] udp_rx;
wire udp_rx_dv;
reg [15: 0] udp_tx_pending_data=0; //max 1472 byte
wire udp_tx;
wire udp_tx_rden;

eth_if eth_if_inst (
    .rst(rst), 
    .clk_200(clk_200), 
    .ETH_RESET(ETH_RESET_0), 
    .GTX_CLK(GTX_CLK_0),
    .GMII_TXD(GMII_TXD_0), 
    .GMII_TX_EN(GMII_TX_EN_0), 
    .GMII_TX_ER(GMII_TX_ER_0), 
    .GMII_TX_CLK(GMII_TX_CLK_0), 
    .GMII_RXD(GMII_RXD_0), 
    .GMII_RX_DV(GMII_RX_DV_0), 
    .GMII_RX_ER(GMII_RX_ER_0), 
    .GMII_RX_CLK(GMII_RX_CLK_0), 
    .MII_TX_CLK(MII_TX_CLK_0), 
    .GMII_COL(GMII_COL_0), 
    .GMII_CRS(GMII_CRS_0),
    
    .udp_rx_clk(udp_rx_clk), 
    .udp_rx(udp_rx), 
    .udp_rx_dv(udp_rx_dv), 
    .udp_tx_pending_data(udp_tx_pending_data), 
    .udp_tx_clk(udp_tx_clk), 
    .udp_tx(udp_tx), 
    .udp_tx_rden(udp_tx_rden)
);

wire [15:0] rd_data_count;
always @(udp_tx_clk) udp_tx_pending_data <= rd_data_count<1472 ? rd_data_count : 1472;

eth_fifo fifo (
   .rst(1'b0), // input rst
   .wr_clk(udp_rx_clk), // input wr_clk
   .din(udp_rx), // input [7 : 0] din
   .wr_en(udp_rx_dv), // input wr_en
   .full(full), // output full

   .rd_clk(udp_tx_clk), // input rd_clk
   .rd_en(udp_tx_rden), // input rd_en
   .dout(udp_tx), // output [7 : 0] dout
   .empty(), // output empty
   .rd_data_count(rd_data_count) // output [15 : 0] rd_data_count
);

endmodule

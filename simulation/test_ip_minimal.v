`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   19:52:13 10/26/2013
// Design Name:   ip_minimal
// Module Name:   /home/alecher/devboard_eth/test_ip_minimal.v
// Project Name:  devboard_eth
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: ip_minimal
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module test_ip_minimal;

	// Inputs
	reg eth_tx_clk;
	reg eth_tx_ack;
	reg eth_rx_clk;
	reg [7:0] eth_rx_data;
	reg eth_rx_data_valid;
	reg eth_rx_frame_good;
	reg eth_rx_frame_bad;
	reg [15: 0] udp_tx_pending_data; //max 1472 byte
	wire [7:0] udp_tx;

	// Outputs
	wire [7:0] eth_tx_data;
	wire eth_tx_data_en;
	wire [7:0] udp_rx;
	wire udp_rx_dv;
	wire udp_tx_rden;

	// Instantiate the Unit Under Test (UUT)
	ip_minimal uut (
		.eth_tx_clk(eth_tx_clk), 
		.eth_tx_data(eth_tx_data), 
		.eth_tx_data_en(eth_tx_data_en), 
		.eth_tx_ack(eth_tx_ack), 
		.eth_rx_clk(eth_rx_clk), 
		.eth_rx_data(eth_rx_data), 
		.eth_rx_data_valid(eth_rx_data_valid), 
		.eth_rx_frame_good(eth_rx_frame_good), 
		.eth_rx_frame_bad(eth_rx_frame_bad),
		.udp_rx(udp_rx),
		.udp_rx_dv(udp_rx_dv),
		.udp_tx_pending_data(udp_tx_pending_data),
		.udp_tx(udp_tx),
		.udp_tx_rden(udp_tx_rden)
	);

	initial begin
		// Initialize Inputs
		eth_tx_clk = 0;
		eth_tx_ack = 0;
		eth_rx_clk = 0;
		eth_rx_data = 0;
		eth_rx_data_valid = 0;
		eth_rx_frame_good = 0;
		eth_rx_frame_bad = 0;
		udp_tx_pending_data = 0;
		//udp_tx = 8'hBA;

		forever begin
			#4 eth_tx_clk<=~eth_tx_clk;
			#1 eth_rx_clk<=~eth_rx_clk;
		end
		// Wait 100 ns for global reset to finish
		#100;
        
		// Add stimulus here

	end
	

reg eth_tx_data_en_r=0;
reg [4:0] ask_delay=0;

always @(posedge eth_tx_clk) begin
	eth_tx_data_en_r<=eth_tx_data_en;
	ask_delay<={ask_delay[3:0],({eth_tx_data_en_r,eth_tx_data_en}==2'b01)};
	eth_tx_ack<=ask_delay[4];
end

parameter udp_len = 50;
reg [7:0] udp [udp_len-1:0];
	
parameter arp_ack_len = 42;
reg [7:0] arp_ack [arp_ack_len-1:0] ;

initial $readmemh ("pkg_arp_ack.hex", arp_ack) ;
initial $readmemh ("pkg_udp.hex", udp) ;
//initial $readmemh ("pkg_udp_trunc.hex", udp) ;
//initial $writememh ("pkg_arp_ack.hex",  arp_ack );

reg [4:0] send_state = 0;
reg [4:0] send_state_next = 0;

reg [31:0]w=100;

reg [9:0] pkg_pos=0;
reg need_answer = 0;

always @(posedge eth_rx_clk)
    case (send_state)
	0: if (w) w<=w-1; else send_state<=10;
	
	2: begin
		w<=4;
		send_state<=3;
		pkg_pos<=0;
	end
	   
	3: if (w) w <= w - 1; else begin send_state<=4; eth_rx_frame_good<=1; end
	4: begin send_state<=need_answer?5:6; eth_rx_frame_good<=0; end
	5: if (eth_tx_data_en) send_state<=6;
	6: if (!eth_tx_data_en) send_state<=send_state_next;
	
	10: begin
		eth_rx_data_valid<=1;
		if (pkg_pos!=arp_ack_len) begin
			pkg_pos<=pkg_pos+1; 
			eth_rx_data<=arp_ack[pkg_pos];
		end else begin
			eth_rx_data_valid<=0;
			send_state<=2;
			send_state_next<=11;
			need_answer<=1;
		end
	end
	
	11: begin
		eth_rx_data_valid<=1;
		if (pkg_pos!=udp_len) begin
			pkg_pos<=pkg_pos+1;
			eth_rx_data<=udp[pkg_pos];
		end else begin
			eth_rx_data_valid<=0;
			send_state<=2;
			send_state_next<=11;
			need_answer<=0;
		end
	end
    endcase

wire [15:0] rd_data_count;
always @(eth_tx_clk) udp_tx_pending_data <= rd_data_count<1472 ? rd_data_count : 1472;

eth_fifo fifo (
  .rst(1'b0), // input rst
  .wr_clk(eth_rx_clk), // input wr_clk
  .din(udp_rx), // input [7 : 0] din
  .wr_en(udp_rx_dv), // input wr_en
  .full(full), // output full

  .rd_clk(eth_tx_clk), // input rd_clk
  .rd_en(udp_tx_rden), // input rd_en
  .dout(udp_tx), // output [7 : 0] dout
  .empty(), // output empty
  .rd_data_count(rd_data_count) // output [15 : 0] rd_data_count
);
 
endmodule


`timescale 1ns / 1ps

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
	reg [7:0] udp_tx;

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
		udp_tx = 0;

		forever begin
			#4 eth_tx_clk<=~eth_tx_clk;
			#1 eth_rx_clk<=~eth_rx_clk;
		end
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

reg [31:0] w = 100;

reg [9:0] pkg_pos = 0;
reg need_answer = 0;

always @(posedge eth_rx_clk) case (send_state)
	0: if (w) w<=w-1; else send_state<=10;

	2: begin
		w<=4;
		send_state<=3;
		pkg_pos<=0;
	end
    
	3: begin
		if (w) w <= w - 1;
		else begin
			send_state<=4;
			eth_rx_frame_good<=1;
		end
	end

	4: begin
		send_state<=need_answer?5:6;
		eth_rx_frame_good<=0;
	end

	5: if (eth_tx_data_en) send_state<=6;
	6: if (!eth_tx_data_en) send_state<=send_state_next;

	// Send ARP request
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

	// Send short UDP packet
	11: begin
		eth_rx_data_valid<=1;
		if (pkg_pos!=udp_len) begin
			pkg_pos<=pkg_pos+1;
			eth_rx_data<=udp[pkg_pos];
		end else begin
			eth_rx_data_valid<=0;
			send_state<=2;
			send_state_next<=14;
			need_answer<=0;
		end
	end
	
	
	14: begin
		w <= 1000;
		send_state <= 15;
	end
	
	15: begin
		if (w) w <= w - 1;
		else $finish();
	end
endcase

// --- PCAP output
integer t = 0;
initial forever #1 t <= t + 1;

integer pcap;
initial begin
	pcap = $fopen("test.pcap", "wb");
	$fwrite(pcap, "%u", 192'hA1B2C3D4_00040002_00000000_00000000_FFFF0000_00000001);
end

// TX
reg [8:0] tx_packet [9100:0];
integer tx_packet_len = 0;
integer tx_packet_readpos;

reg [1:0] eth_tx_pkt = 0;
always @(posedge eth_tx_data_en) begin
	$display("TX begin");
	eth_tx_pkt <= 1;
	tx_packet_len <= 0;
end

always @(posedge eth_tx_ack) begin
	eth_tx_pkt <= eth_tx_pkt + 1;
end

always @(posedge eth_tx_clk)
	if (eth_tx_data_en && eth_tx_pkt==2) begin
		$write("%X ", eth_tx_data);
		tx_packet[tx_packet_len] <= eth_tx_data;
		tx_packet_len <= tx_packet_len + 1;
	end

always @(negedge eth_tx_data_en) 
	if (eth_tx_pkt==2) begin
		$display("\nTX end");
		eth_tx_pkt <= 0;
		$fwrite(pcap, "%u", {t, 32'h0, tx_packet_len, tx_packet_len});
		for (tx_packet_readpos = 0; tx_packet_readpos < tx_packet_len; tx_packet_readpos = tx_packet_readpos + 1)
			$fwrite(pcap, "%c", tx_packet[tx_packet_readpos]);
	end

// RX
reg [8:0] rx_packet [9100:0];
integer rx_packet_len = 0;
integer rx_packet_readpos;

always @(posedge eth_rx_data_valid) begin
	$display("RX begin");
	rx_packet_len <= 0;
end

always @(posedge eth_rx_clk)
	if (eth_rx_data_valid) begin
		$write("%X ", eth_rx_data);
		rx_packet[rx_packet_len] <= eth_rx_data;
		rx_packet_len <= rx_packet_len + 1;
	end

always @(negedge eth_rx_data_valid) begin
	$display("\nRX end");
	if (rx_packet_len) begin
		$fwrite(pcap, "%u", {t, 32'h0, rx_packet_len, rx_packet_len});
		for (rx_packet_readpos = 0; rx_packet_readpos < rx_packet_len; rx_packet_readpos = rx_packet_readpos + 1)
			$fwrite(pcap, "%c", rx_packet[rx_packet_readpos]);
	end
end

// ---

endmodule

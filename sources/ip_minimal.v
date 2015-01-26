`timescale 1ns / 1ps

module ip_minimal(
//Ethernet MAC
    input wire         eth_tx_clk,
    output reg [ 7: 0] eth_tx_data,
    output reg         eth_tx_data_en,
    input wire         eth_tx_ack,
 
    input wire         eth_rx_clk,
    input wire [ 7: 0] eth_rx_data,
    input wire         eth_rx_data_valid,
    input wire         eth_rx_frame_good,
    input wire         eth_rx_frame_bad,
    
    output reg [ 7: 0] udp_rx,
    output reg         udp_rx_dv,
    
    input wire [ 7: 0] udp_tx,
    input wire [15: 0] udp_tx_pending_data,
    output reg         udp_tx_rden
);

initial begin
    eth_tx_data <= 8'h00;
    eth_tx_data_en <= 0;
    udp_rx <= 8'h00;
    udp_rx_dv <= 0;
    udp_tx_rden <= 0;
end


reg [47:0] my_mac_addr = 48'h00_AA_BB_CC_DD_EE;
wire [31:0] my_ip_addr = {8'd10, 8'd5, 8'd5, 8'd5}; //{8'd192, 8'd168, 8'd1, 8'd123};
/*

reg [47:0] dest_mac_addr = 48'h30_85_a9_13_05_32;
reg [31:0] dest_ip_addr =  32'h0a_05_05_01;*/

// ----------------- Rx

`define RX_ST_PKT_BEGIN          8'b00000001
`define RX_ST_PKT_DROP           8'b00000010
`define RX_ST_PKT_GOOD_OR_BAD    8'b00000100
`define RX_ST_PKT_MYADDR         8'b00001000

`define RX_ST_PKT_TYPE_ARP       8'b00010000
`define RX_ST_PKT_TYPE_IP        8'b00100000
`define RX_ST_PKT_IP_UDP         8'b01000000
`define RX_ST_PKT_IP_UDP_PAYLOAD 8'b10000000


reg [7:0] rx_state = `RX_ST_PKT_BEGIN;
reg [15:0] rx_pos = 0;

reg [47:0] rx_mac;
reg [7:0] eth_rx_data_r=0;
wire [15:0] eth_rx_data_word = {eth_rx_data_r, eth_rx_data};
always @(posedge eth_rx_clk) if (eth_rx_data_valid) begin
	//rx_buf[rx_pos] <= eth_rx_data;
	eth_rx_data_r <= eth_rx_data;
	case (rx_pos)
		0, 6  : rx_mac[47:40] <= eth_rx_data;
		1, 7  : rx_mac[39:32] <= eth_rx_data;
		2, 8  : rx_mac[31:24] <= eth_rx_data;
		3, 9  : rx_mac[23:16] <= eth_rx_data;
		4, 10 : rx_mac[15: 8] <= eth_rx_data;
		5, 11 : rx_mac[ 7: 0] <= eth_rx_data;
	endcase
	
	rx_pos <= rx_pos+1;
end else rx_pos <= 0;

`define SEND_PKT_NONE      0
`define SEND_PKT_ARP_REPLY 1
`define SEND_PKT_UDP       2

reg [7:0] rx_send_event;
reg reply_req=0;
reg reply_ack=0;

reg [15:0] rx_udp_len;

reg [47:0] arp_reply_mac;
reg [31:0] arp_reply_ip;
reg [4+15:0] rx_ip_crc;

always @(posedge eth_rx_clk/* or negedge eth_rx_data_valid*/) 
/*if (eth_rx_data_valid == 0 && rx_state !=`RX_ST_PKT_GOOD_OR_BAD) 
	rx_state <= `RX_ST_PKT_BEGIN;
else */case (rx_state)
	`RX_ST_PKT_BEGIN:
		if (rx_pos == 6)
			if (&rx_mac || rx_mac == my_mac_addr) rx_state <= `RX_ST_PKT_MYADDR;
			else rx_state <= `RX_ST_PKT_DROP;

	`RX_ST_PKT_DROP:
		if (!eth_rx_data_valid) rx_state <= `RX_ST_PKT_BEGIN;
	
	`RX_ST_PKT_MYADDR:
		if (rx_pos == 13) case (eth_rx_data_word) 
			16'h0806: rx_state <= `RX_ST_PKT_TYPE_ARP;
			16'h0800: begin
				rx_state <= `RX_ST_PKT_TYPE_IP;
				rx_ip_crc <= 0;
			end
		endcase
		
	`RX_ST_PKT_TYPE_ARP:
		case (rx_pos)
			15: if (eth_rx_data_word != 16'h0001) rx_state <= `RX_ST_PKT_DROP; // ARP type Ethernet
			17: if (eth_rx_data_word != 16'h0800) rx_state <= `RX_ST_PKT_DROP; // Protocol IP
			19: if (eth_rx_data_word != 16'h0604) rx_state <= `RX_ST_PKT_DROP; // hw and ip lenght
			21: if (eth_rx_data_word != 16'h0001) rx_state <= `RX_ST_PKT_DROP; // Opcode request
			22: arp_reply_mac[47:40] <= eth_rx_data;
			23: arp_reply_mac[39:32] <= eth_rx_data;
			24: arp_reply_mac[31:24] <= eth_rx_data;
			25: arp_reply_mac[23:16] <= eth_rx_data;
			26: arp_reply_mac[15: 8] <= eth_rx_data;
			27: arp_reply_mac[ 7: 0] <= eth_rx_data;
			28: arp_reply_ip[31:24] <= eth_rx_data;
			29: arp_reply_ip[23:16] <= eth_rx_data;
			30: arp_reply_ip[15: 8] <= eth_rx_data;
			31: arp_reply_ip[ 7: 0] <= eth_rx_data;
			41: begin 
				rx_send_event <= `SEND_PKT_ARP_REPLY;
				rx_state <= `RX_ST_PKT_GOOD_OR_BAD;
			end
		endcase
		
	`RX_ST_PKT_TYPE_IP: begin
			if (rx_pos & 1'b1) rx_ip_crc<=rx_ip_crc+eth_rx_data_word;
			casex (rx_pos)
				14: if (eth_rx_data != 8'h4_5) rx_state <= `RX_ST_PKT_DROP; // IPv4 header len 20 bytes
				//16:if (eth_rx_data_word// != 8'h45) rx_state <= `RX_ST_PKT_DROP; // Total lenght
				//18: eth_rx_data_word id
				//19: 0x02 - dont fragment
				//21: fragment offs
				//22: ttl
				23: if (eth_rx_data != 8'h11) rx_state <= `RX_ST_PKT_DROP; // UDP
				//25: //checksum
				//26..29 src ip
				30: if (eth_rx_data != my_ip_addr[31:24]) rx_state <= `RX_ST_PKT_DROP;
				31: if (eth_rx_data != my_ip_addr[23:16]) rx_state <= `RX_ST_PKT_DROP;
				32: if (eth_rx_data != my_ip_addr[15: 8]) rx_state <= `RX_ST_PKT_DROP;
				33: begin
					if (((rx_ip_crc[15+4:16] + rx_ip_crc[15:0] + eth_rx_data_word) != 16'hFFFF) && (eth_rx_data != my_ip_addr[ 7: 0])) rx_state <= `RX_ST_PKT_DROP;
					else rx_state <= `RX_ST_PKT_IP_UDP;
				end
			endcase
		end

	`RX_ST_PKT_IP_UDP:
		case (rx_pos)
			//34 35 src port
			//36 37 dst port
			39: rx_udp_len <= eth_rx_data_word-8-1;
			//40 41 crc
			41: begin
				// TODO: Check CRC
				rx_state <= `RX_ST_PKT_IP_UDP_PAYLOAD;
			end
		endcase
		
	`RX_ST_PKT_IP_UDP_PAYLOAD:
		if (rx_udp_len) begin
			rx_udp_len<=rx_udp_len-1;
		end else begin
			rx_state<= `RX_ST_PKT_GOOD_OR_BAD;
			rx_send_event <= `SEND_PKT_NONE;
		end
		
	`RX_ST_PKT_GOOD_OR_BAD:
		if (eth_rx_frame_good || eth_rx_frame_bad) begin
			rx_state<= `RX_ST_PKT_BEGIN;
			reply_req <= reply_req ^ (eth_rx_frame_good && |rx_send_event);
		end
endcase

always @(posedge eth_rx_clk) 
	if (rx_state == `RX_ST_PKT_IP_UDP_PAYLOAD) begin
		udp_rx_dv<=1;
		udp_rx<=eth_rx_data;
	end else udp_rx_dv<=0;

// ----------------- Tx

`define TX_ST_WAIT           8'b00000001
`define TX_ST_HEADER         8'b00000010
`define TX_ST_HEADER_TAIL    8'b00001000
`define TX_ST_END            8'b00010000
`define TX_ST_END_WAIT       8'b00100000

reg [10:0] eth_tx_state = `TX_ST_WAIT;
reg [15:0] tx_pos;
reg [15:0] tx_len = 0;
reg eth_tx_start=0;
reg [47:0] dest_mac_addr;
reg [7:0] tx_send_event=0;

reg [7:0] eth_tx_data_payload;
reg [15:0] udp_payload_size;

`define HEADER_MAC 14
`define HEADER_IP 20
`define HEADER_UDP 8

wire [15:0] udp_payload_size_udp = udp_payload_size+`HEADER_UDP;
wire [15:0] udp_payload_size_ip = udp_payload_size_udp+`HEADER_IP;
reg [23:0] tx_ip_check; //FIXME

always @(posedge eth_tx_clk)
begin
	if (reply_ack != reply_req) begin
		reply_ack <= reply_req;
		tx_send_event <= rx_send_event;
	end else
	if (udp_tx_pending_data) begin
		tx_send_event <= `SEND_PKT_UDP;
	end

	case (eth_tx_state)
		`TX_ST_WAIT: if (tx_send_event) begin
			case (tx_send_event)
				`SEND_PKT_ARP_REPLY: begin dest_mac_addr <= arp_reply_mac; tx_len<=42; end
				`SEND_PKT_UDP: begin  dest_mac_addr <= arp_reply_mac; /*FIXME*/  tx_len<=udp_tx_pending_data+`HEADER_MAC+`HEADER_IP+`HEADER_UDP; udp_payload_size<=udp_tx_pending_data; end
			endcase
			eth_tx_state <= `TX_ST_HEADER;
			tx_pos<=1;
		end

		`TX_ST_HEADER: begin
			eth_tx_data_en<=1;
			if (eth_tx_ack) begin
				eth_tx_state <= `TX_ST_HEADER_TAIL;
				tx_pos<=tx_pos+1;
				eth_tx_data<=dest_mac_addr[39:32];
			end else eth_tx_data<=dest_mac_addr[47:40];
		end

		`TX_ST_HEADER_TAIL: begin
			tx_pos<=tx_pos+1;
			eth_tx_data<=eth_tx_data_payload;
			case (tx_pos)
				2:eth_tx_data <=dest_mac_addr[31:24];
				3:eth_tx_data <=dest_mac_addr[23:16];
				4:eth_tx_data <=dest_mac_addr[15: 8];
				5:eth_tx_data <=dest_mac_addr[ 7: 0];

				6: eth_tx_data<=my_mac_addr[47:40];
				7: eth_tx_data<=my_mac_addr[39:32];
				8: eth_tx_data<=my_mac_addr[31:24];
				9: eth_tx_data<=my_mac_addr[23:16];
				10: eth_tx_data<=my_mac_addr[15: 8];
				11: eth_tx_data<=my_mac_addr[ 7: 0];
				default: eth_tx_data<=eth_tx_data_payload;
			endcase
			
			if (tx_send_event ==  `SEND_PKT_UDP) begin
				case (tx_pos)
				
					20: tx_ip_check <= 16'h4500 + udp_payload_size_ip + 16'hBABA + 16'h0511;
					21: tx_ip_check <= tx_ip_check + my_ip_addr[31:16]+my_ip_addr[15:0]+arp_reply_ip[31:16]+arp_reply_ip[15:0];
					22: tx_ip_check <= tx_ip_check[15:0]+tx_ip_check[23:16];
					23: tx_ip_check <= ~tx_ip_check[15:0];
					
					40: udp_tx_rden<=1'b1;
					default: if (tx_pos+1 >= tx_len-1) udp_tx_rden<=1'b0;
				endcase
				
				
			end
			
			if (tx_pos+1 >= tx_len) eth_tx_state <= `TX_ST_END;
		end
		
		`TX_ST_END: begin
			eth_tx_data_en<=0;
			eth_tx_state <= `TX_ST_END_WAIT;
			tx_send_event<=`SEND_PKT_NONE;
		end
		
		`TX_ST_END_WAIT: eth_tx_state <= `TX_ST_WAIT;
	endcase

end


always @(tx_pos)
	if (tx_send_event == `SEND_PKT_ARP_REPLY) case (tx_pos)
		12: eth_tx_data_payload=8'h08; // ARP
		13: eth_tx_data_payload=8'h06;
		
		14: eth_tx_data_payload=8'h00; // ARP type ethernet
		15: eth_tx_data_payload=8'h01;
		
		16: eth_tx_data_payload=8'h08; // Proto type: IP
		17: eth_tx_data_payload=8'h00;
		
		18: eth_tx_data_payload=8'h06; // hw size
		19: eth_tx_data_payload=8'h04; // proto size
		
		20: eth_tx_data_payload=8'h00; // opcode 02 - reply
		21: eth_tx_data_payload=8'h02; // 
		
		22: eth_tx_data_payload=my_mac_addr[47:40]; //sender mac from
		23: eth_tx_data_payload=my_mac_addr[39:32];
		24: eth_tx_data_payload=my_mac_addr[31:24];
		25: eth_tx_data_payload=my_mac_addr[23:16];
		26: eth_tx_data_payload=my_mac_addr[15: 8];
		27: eth_tx_data_payload=my_mac_addr[ 7: 0];
		
		28: eth_tx_data_payload=my_ip_addr[31:24]; //sender ip from
		29: eth_tx_data_payload=my_ip_addr[23:16];
		30: eth_tx_data_payload=my_ip_addr[15: 8];
		31: eth_tx_data_payload=my_ip_addr[ 7: 0];
		
		32: eth_tx_data_payload=arp_reply_mac[47:40]; //target mac (send to)
		33: eth_tx_data_payload=arp_reply_mac[39:32]; 
		34: eth_tx_data_payload=arp_reply_mac[31:24]; 
		35: eth_tx_data_payload=arp_reply_mac[23:16]; 
		36: eth_tx_data_payload=arp_reply_mac[15: 8]; 
		37: eth_tx_data_payload=arp_reply_mac[ 7: 0]; 
		
		38: eth_tx_data_payload=arp_reply_ip[31:24]; //target ip (send to)
		39: eth_tx_data_payload=arp_reply_ip[23:16]; 
		40: eth_tx_data_payload=arp_reply_ip[15: 8]; 
		41: eth_tx_data_payload=arp_reply_ip[ 7: 0]; 
	endcase
	else 
	if (tx_send_event ==  `SEND_PKT_UDP) case (tx_pos)
		12: eth_tx_data_payload=8'h08; // IP
		13: eth_tx_data_payload=8'h00;

		14: eth_tx_data_payload=8'h45; // IPv4 header len 20 bytes
		15: eth_tx_data_payload=8'h00; // Fields
		
		16: eth_tx_data_payload=udp_payload_size_ip[15: 8]; // Lenght
		17: eth_tx_data_payload=udp_payload_size_ip[ 7: 0];
		
		18: eth_tx_data_payload=8'hBA; // ID
		19: eth_tx_data_payload=8'hBA;
		
		20: eth_tx_data_payload=8'h00; // Fragment offset
		21: eth_tx_data_payload=8'h00;
		
		22: eth_tx_data_payload=8'h05; // TTL
		
		23: eth_tx_data_payload=8'h11; // Payload type; UDP
		
		24: eth_tx_data_payload=tx_ip_check[15: 8]; // Check sum
		25: eth_tx_data_payload=tx_ip_check[ 7: 0];
		
		26: eth_tx_data_payload=my_ip_addr[31:24]; //Source IP
		27: eth_tx_data_payload=my_ip_addr[23:16];
		28: eth_tx_data_payload=my_ip_addr[15: 8];
		29: eth_tx_data_payload=my_ip_addr[ 7: 0];

		30: eth_tx_data_payload=arp_reply_ip[31:24]; //Destination IP FIXME
		31: eth_tx_data_payload=arp_reply_ip[23:16];
		32: eth_tx_data_payload=arp_reply_ip[15: 8];
		33: eth_tx_data_payload=arp_reply_ip[ 7: 0];

		//UDP
		34: eth_tx_data_payload=8'h11; // Source port
		35: eth_tx_data_payload=8'h22;
		
		36: eth_tx_data_payload=8'h12; // Destination port
		37: eth_tx_data_payload=8'h34;
		
		38: eth_tx_data_payload=udp_payload_size_udp[15: 8]; // Lenght 
		39: eth_tx_data_payload=udp_payload_size_udp[ 7: 0];
		
		40: eth_tx_data_payload=8'h00; //Check sum UDP
		41: eth_tx_data_payload=8'h00;

		default: eth_tx_data_payload=udp_tx;
	endcase
	else eth_tx_data_payload=8'hZZ;

endmodule

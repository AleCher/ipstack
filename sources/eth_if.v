`timescale 1ns / 1ps

module eth_if(
	input wire rst,
	input wire clk_200,
	
	input wire        GTX_CLK,
	 
	output wire       ETH_RESET,
	output wire [7:0] GMII_TXD,
	output wire       GMII_TX_EN,
	output wire       GMII_TX_ER,
	output wire       GMII_TX_CLK,
	input wire  [7:0] GMII_RXD,
	input wire        GMII_RX_DV,
	input wire        GMII_RX_ER,
	input wire        GMII_RX_CLK,
	input wire        MII_TX_CLK,
	input wire        GMII_COL,
	input wire        GMII_CRS,
	
	output wire udp_rx_clk,
	output wire [7:0] udp_rx,
	output wire udp_rx_dv,

	input wire [15: 0] udp_tx_pending_data, //max 1472 byte
	output wire udp_tx_clk,
	input wire [7:0] udp_tx,
	output wire udp_tx_rden
);

(* KEEP_HIERARCHY="TRUE" *)
wire tx_clk;
wire rx_clk;

assign ETH_RESET = 1'b1; // active lo
assign udp_rx_clk = tx_clk;
assign udp_tx_clk = rx_clk;

wire [7:0] emac0_rx_data;
wire       emac0_rx_data_valid;
wire       emac0_rx_data_goodframe;
wire       emac0_rx_data_badframe;

wire [7:0] emac0_tx_data;
wire       emac0_tx_data_valid;
wire       emac0_tx_data_ack;

wire gmii_rx_clk_delay;

ethmac_block emac_block_inst (
	// EMAC0 Clocking
	// TX Clock output from EMAC
	.TX_CLK_OUT                          (),

	// EMAC0 TX Clock input from BUFG
	.TX_CLK_0                            (tx_clk),

	// Client Receiver Interface - EMAC0
	.EMAC0CLIENTRXD                      (emac0_rx_data),
	.EMAC0CLIENTRXDVLD                   (emac0_rx_data_valid),
	.EMAC0CLIENTRXGOODFRAME              (emac0_rx_data_goodframe),
	.EMAC0CLIENTRXBADFRAME               (emac0_rx_data_badframe),
	.EMAC0CLIENTRXFRAMEDROP              (),
	.EMAC0CLIENTRXSTATS                  (),
	.EMAC0CLIENTRXSTATSVLD               (),
	.EMAC0CLIENTRXSTATSBYTEVLD           (),

	// Client Transmitter Interface - EMAC0
	.CLIENTEMAC0TXD                      (emac0_tx_data),
	.CLIENTEMAC0TXDVLD                   (emac0_tx_data_valid),
	.EMAC0CLIENTTXACK                    (emac0_tx_data_ack),
	.CLIENTEMAC0TXFIRSTBYTE              (1'b0),
	.CLIENTEMAC0TXUNDERRUN               (1'b0),
	.EMAC0CLIENTTXCOLLISION              (),
	.EMAC0CLIENTTXRETRANSMIT             (),
	.CLIENTEMAC0TXIFGDELAY               (8'h00),
	.EMAC0CLIENTTXSTATS                  (),
	.EMAC0CLIENTTXSTATSVLD               (),
	.EMAC0CLIENTTXSTATSBYTEVLD           (),

	// MAC Control Interface - EMAC0
	.CLIENTEMAC0PAUSEREQ                 (0),
	.CLIENTEMAC0PAUSEVAL                 (0),

		// Clock Signal - EMAC0
	.GTX_CLK_0(1'b0),


	// GMII Interface - EMAC0
	.GMII_TXD_0                          (GMII_TXD),
	.GMII_TX_EN_0                        (GMII_TX_EN),
	.GMII_TX_ER_0                        (GMII_TX_ER),
	.GMII_TX_CLK_0                       (GMII_TX_CLK),
	.GMII_RXD_0                          (GMII_RXD),
	.GMII_RX_DV_0                        (GMII_RX_DV),
	.GMII_RX_ER_0                        (GMII_RX_ER),
	.GMII_RX_CLK_0                       (rx_clk),
	
	.RESET(rst)
);

IDELAYCTRL dlyctrl0 (
	.RDY(),
	.REFCLK(clk_200),
	.RST(rst)
);

BUFG bufg_tx (.I(gtx_clk_i), .O(tx_clk));
IBUF gtx_clk0_ibuf (.I(GTX_CLK), .O(gtx_clk_i));
BUFG bufg_rx (.I(gmii_rx_clk_delay), .O(rx_clk));

IODELAY gmii_rxc0_delay (
	.IDATAIN(GMII_RX_CLK),
	.ODATAIN(1'b0),
	.DATAOUT(gmii_rx_clk_delay),
	.DATAIN(1'b0),
	.C(1'b0),
	.T(1'b0),
	.CE(1'b0),
	.INC(1'b0),
	.RST(1'b0)
);

defparam gmii_rxc0_delay.IDELAY_TYPE = "FIXED";
defparam gmii_rxc0_delay.IDELAY_VALUE = 0;
defparam gmii_rxc0_delay.DELAY_SRC = "I";
defparam gmii_rxc0_delay.SIGNAL_PATTERN = "CLOCK";

ip_minimal ipcore (
	.eth_tx_clk(tx_clk), 
	.eth_tx_data(emac0_tx_data), 
	.eth_tx_data_en(emac0_tx_data_valid), 
	.eth_tx_ack(emac0_tx_data_ack),
	
	.eth_rx_clk(rx_clk), 
	.eth_rx_data(emac0_rx_data), 
	.eth_rx_data_valid(emac0_rx_data_valid), 
	.eth_rx_frame_good(emac0_rx_data_goodframe), 
	.eth_rx_frame_bad(emac0_rx_data_badframe),
    
	.udp_rx(udp_rx),
	.udp_rx_dv(udp_rx_dv),
	.udp_tx_pending_data(udp_tx_pending_data),
	.udp_tx(udp_tx),
	.udp_tx_rden(udp_tx_rden)
);

endmodule

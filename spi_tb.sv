///////////////////////////////////////////////////////////////////////////////
// Description:       Simple test bench for SPI Master module
///////////////////////////////////////////////////////////////////////////////

`timescale 10 ns/10 ns
module SPI_Master_TB ();
  
  parameter SPI_MODE = 0; // CPOL = 1, CPHA = 1
  parameter CLKS_PER_HALF_BIT = 1;  // 6.25 MHz

  logic r_Rst_L     = 1'b1;  
  logic w_SPI_Clk;
  logic r_Clk       = 1'b0;
  
  wire [3:0] w_SIO_OUT;
  logic [1:0] w_BUS_MODE;
  // Master Specific
  logic rr_Pulse = 1'b0;
	wire [3:0] input_value;
	reg [3:0] output_value;
	reg output_value_valid;
	reg [7:0] tx_byte;
	logic tt_Pulse;

  spi_master
  #(.SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) SPI_Master_UUT
  (
   // Control/Data Signals,
   .i_Rst_L(r_Rst_L),     // FPGA Reset
   .i_Clk(r_Clk),       // FPGA Clock
   
   // TX (MOSI) Signals
   .i_TX_Byte(tx_byte),        // Byte to transmit on MOSI
   .i_TX_DV(tt_Pulse),          // Data Valid Pulse with i_TX_Byte
   .o_TX_Ready(),       // Transmit Ready for next byte
   
   // RX (MISO) Signals
   .i_RX_Pulse(rr_Pulse),
   .o_RX_DV(),     // Data Valid pulse (1 clock cycle)
   .o_RX_Byte(),   // Byte received on MISO

   .BUS_MODE_IN(w_BUS_MODE),
   // SPI Interface
   .o_SPI_Clk(w_SPI_Clk),
   .SIO_OUT(w_SIO_OUT)
   );

assign input_value = w_SIO_OUT;
assign w_SIO_OUT = (output_value_valid==1'b1) ? output_value : 4'bZZZZ;

always 
begin
    r_Clk = 1'b1; 
    #2; // high for 2 * timescale = 20 ns

    r_Clk = 1'b0;
    #2; // low for 2 * timescale = 20 ns
end

  initial
    begin
		tx_byte = 8'h38;
		//output_value_valid = 1'b1;
		//output_value = 4'd9;
		w_BUS_MODE = 2'd0;
		r_Rst_L = 1'b0;
		#4 r_Rst_L = 1'b1;
		#4 tt_Pulse = 1'b1;
		#4 tt_Pulse = 1'b0;
		
		
		
    end // initial begin

endmodule // SPI_Slave
///////////////////////////////////////////////////////////////////////////////
// Description: SPI (Serial Peripheral Interface) Master
//              Creates master based on input configuration.
//              Sends a byte one bit at a time on MOSI
//              Will also receive byte data one bit at a time on MISO.
//              Any data on input byte will be shipped out on MOSI.
//
//              To kick-off transaction, user must pulse i_TX_DV.
//              This module supports multi-byte transmissions by pulsing
//              i_TX_DV and loading up i_TX_Byte when o_TX_Ready is high.
//
//              This module is only responsible for controlling Clk, MOSI, 
//              and MISO.  If the SPI peripheral requires a chip-select, 
//              this must be done at a higher level.
//
// Note:        i_Clk must be at least 2x faster than i_SPI_Clk
//
// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.
//              Can be configured in one of 4 modes:
//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)
//               0   |             0             |        0
//               1   |             0             |        1
//               2   |             1             |        0
//               3   |             1             |        1
//              More: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers
//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is
//              derived from i_Clk.  Set to integer number of clocks for each
//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2
//              would create o_SPI_CLK of 25 MHz.  Must be >= 2
//
///////////////////////////////////////////////////////////////////////////////

module spi_master
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 1)
  (
   // Control/Data Signals,
   input        i_Rst_L,     // FPGA Reset
   input        i_Clk,       // FPGA Clock
   
   // TX (MOSI) Signals
   input [7:0]  i_TX_Byte,        // Byte to transmit on MOSI
   input        i_TX_DV,          // Data Valid Pulse with i_TX_Byte
   output reg   o_TX_Ready,       // Transmit Ready for next byte
   
   // RX (MISO) Signals
   input 		i_RX_Pulse,
   output reg       o_RX_DV,     // Data Valid pulse (1 clock cycle)
   output reg [7:0] o_RX_Byte,   // Byte received on MISO

	input [1:0] BUS_MODE_IN,
   // SPI Interface
   output reg o_SPI_Clk,
   inout [3:0] SIO_OUT
   );

  // SPI Interface (All Runs at SPI Clock Domain)
  wire w_CPOL;     // Clock polarity
  wire w_CPHA;     // Clock phase
  reg [3:0] SIO_r = 4'd0;

  reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count = 0;
  reg r_SPI_Clk;
  reg [3:0] SIO_w = 4'd0;
  
  reg [4:0] r_SPI_Clk_Edges = 0;
  reg r_Leading_Edge = 0;
  reg r_Trailing_Edge = 0;
  reg       r_TX_DV = 0;
  reg 		r_RX_Pulse = 0;
  reg [7:0] r_TX_Byte = 0;
  reg [1:0] BUS_MODE = 0;
  reg Latch_Once = 1'b1;

  reg [2:0] r_RX_Bit_Count = 3'd7;
  reg [2:0] r_TX_Bit_Count = 3'd7;

  // CPOL: Clock Polarity
  // CPOL=0 means clock idles at 0, leading edge is rising edge.
  // CPOL=1 means clock idles at 1, leading edge is falling edge.
  assign w_CPOL  = (SPI_MODE == 2) | (SPI_MODE == 3);

  // CPHA: Clock Phase
  // CPHA=0 means the "out" side changes the data on trailing edge of clock
  //              the "in" side captures data on leading edge of clock
  // CPHA=1 means the "out" side changes the data on leading edge of clock
  //              the "in" side captures data on the trailing edge of clock
  assign w_CPHA  = (SPI_MODE == 1) | (SPI_MODE == 3);


  assign SIO_OUT = (i_TX_DV == 1'b1 | r_TX_DV == 1'b1) ? SIO_w : 4'bZZZZ;


  // Purpose: Generate SPI Clock correct number of times when DV pulse comes
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_TX_Ready      <= 1'b0;
	  o_RX_DV		<= 1'b0;
      r_SPI_Clk_Edges <= 0;
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      r_SPI_Clk       <= w_CPOL; // assign default state to idle state
      r_SPI_Clk_Count <= 0;
	  BUS_MODE		<= 0;
    end
    else
    begin
		
      if ((i_TX_DV | i_RX_Pulse) && Latch_Once)
      begin
		BUS_MODE	<= BUS_MODE_IN;
		r_Leading_Edge  <= 1'b0;
		r_Trailing_Edge <= 1'b0;
		r_SPI_Clk       <= w_CPOL;
        o_TX_Ready      <= 1'b0;
		o_RX_DV			<= 1'b0;
		if (BUS_MODE_IN == 1)
		begin
			r_SPI_Clk_Edges <= 8;  
		end
		else if (BUS_MODE_IN == 2 | BUS_MODE == 3)
		begin
			r_SPI_Clk_Edges <= 4; 
		end
		else begin
			r_SPI_Clk_Edges <= 16; 
		end
        
      end
      else if (r_SPI_Clk_Edges > 0)
      begin
        o_TX_Ready <= 1'b0;
        o_RX_DV	   <= 1'b0;
        if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT - 1'b1)		
        begin
          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1'b1;
          r_SPI_Clk_Count <= 0;
          r_SPI_Clk       <= ~r_SPI_Clk;
			 if(r_Leading_Edge) begin
				r_Leading_Edge	<= 1'b0;
				r_Trailing_Edge	<= 1'b1;
			 end
			 else begin
				r_Leading_Edge	<= 1'b1;
				r_Trailing_Edge	<= 1'b0;
			 end
        end
        else
        begin
          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1'b1;
        end
      end  
      else
      begin
		r_Leading_Edge  <= 1'b0;
		r_Trailing_Edge <= 1'b0;
		r_SPI_Clk_Edges <= 0;
		r_SPI_Clk       <= w_CPOL;
		o_TX_Ready <= 1'b1;
		o_RX_DV	<= 1'b1;
		BUS_MODE	<= BUS_MODE;
      end
      
      
    end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)


  // Purpose: Register i_TX_Byte when Data Valid is pulsed.
  // Keeps local storage of byte in case higher level module changes the data
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_TX_Byte <= 8'h00;
      r_TX_DV   <= 1'b0;
	  r_RX_Pulse	<= 1'b0;
	  Latch_Once <= 1'b1;
    end
    else begin
		if((i_RX_Pulse | i_TX_DV) && Latch_Once) begin
			Latch_Once	<= 1'b0;
			r_TX_DV <= i_TX_DV; 		// 1 clock cycle delay
			r_RX_Pulse	<= i_RX_Pulse;
			r_TX_Byte <= i_TX_Byte;
		end
		else 
		begin
			if(o_TX_Ready | o_RX_DV)
			begin
				Latch_Once <= 1'b1;
				if(o_TX_Ready) begin
					r_TX_DV	<= 1'b0;
				end
				if(o_RX_DV) begin
					r_RX_Pulse	<= 1'b0;
				end
			end
		end
    end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)


  // Purpose: Generate MOSI data
  // Works with both CPHA=0 and CPHA=1
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r_TX_Bit_Count <= 3'b111; // send MSb first
	  SIO_w	<= 4'd0;
    end
    else
    begin
		if(i_TX_DV && Latch_Once)
		begin
			if(~w_CPHA)
			begin
				if (BUS_MODE_IN == 1) 		//SDIO
				begin
					SIO_w[0] <= i_TX_Byte[3'b110];
					SIO_w[1] <= i_TX_Byte[3'b111];
					r_TX_Bit_Count	<= r_TX_Bit_Count - 3'd2;
				end
				else if(BUS_MODE_IN == 2 | BUS_MODE_IN == 3)
				begin			//SQIO
					SIO_w[0] <= i_TX_Byte[3'b100];
					SIO_w[1] <= i_TX_Byte[3'b101];
					SIO_w[2] <= i_TX_Byte[3'b110];
					SIO_w[3] <= i_TX_Byte[3'b111];
					r_TX_Bit_Count	<= r_TX_Bit_Count - 3'd4;
				end
				else begin
					SIO_w[0] <= i_TX_Byte[3'b111];
					r_TX_Bit_Count <= r_TX_Bit_Count - 3'd1;
				end
			end
		end
      // Catch the case where we start transaction and CPHA = 0
      else if (r_TX_DV)
	  begin
		if ((r_Leading_Edge & w_CPHA) | (r_Trailing_Edge & ~w_CPHA))
		begin
			if (BUS_MODE == 1)
			begin
				if(r_TX_Bit_Count == 1) begin
					r_TX_Bit_Count	<= 3'd7;
					SIO_w[1] <= r_TX_Byte[r_TX_Bit_Count];
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count - 1'b1];
				end
				else begin
					SIO_w[1] <= r_TX_Byte[r_TX_Bit_Count];
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count - 1'b1];
					r_TX_Bit_Count	<= r_TX_Bit_Count - 3'd2;
				end
			end
			
			else if(BUS_MODE == 2 | BUS_MODE == 3)
			begin
				if(r_TX_Bit_Count == 3)begin
					r_TX_Bit_Count	<= 3'd7;
					SIO_w[3] <= r_TX_Byte[r_TX_Bit_Count];
					SIO_w[2] <= r_TX_Byte[r_TX_Bit_Count - 2'b01];
					SIO_w[1] <= r_TX_Byte[r_TX_Bit_Count - 2'b10];
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count - 2'b11];
				end
				else begin
					SIO_w[3] <= r_TX_Byte[r_TX_Bit_Count];
					SIO_w[2] <= r_TX_Byte[r_TX_Bit_Count - 2'b01];
					SIO_w[1] <= r_TX_Byte[r_TX_Bit_Count - 2'b10];
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count - 2'b11];
					r_TX_Bit_Count	<= r_TX_Bit_Count - 3'd4;
				end
			end
			else begin	//BUS_MODE == 0
				if(r_TX_Bit_Count == 0) begin
					r_TX_Bit_Count	<= 3'd7;
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count];
				end
				else begin
					SIO_w[0] <= r_TX_Byte[r_TX_Bit_Count];
					r_TX_Bit_Count	<= r_TX_Bit_Count - 3'd1;
				end
			end
		end
	  end	//else if rTXDV
    end		//else of reset
  end		//always


  // Purpose: Read in MISO data.
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_RX_Byte      <= 8'h00;
      r_RX_Bit_Count <= 3'b111;
    end
    else
    begin
	//Initialize
	if(i_RX_Pulse && Latch_Once)
	begin
		o_RX_Byte	<= 8'h00;
	end
    
      if (r_RX_Pulse)
	  begin
		if ((r_Leading_Edge & ~w_CPHA) | (r_Trailing_Edge & w_CPHA))
		begin
			if (BUS_MODE == 1)
			begin
				if(r_RX_Bit_Count == 1) begin
					r_RX_Bit_Count	<= 3'd7;
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[1];
					o_RX_Byte[r_RX_Bit_Count - 1'b1]	<= SIO_r[0];
				end
				else begin
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[1];
					o_RX_Byte[r_RX_Bit_Count - 1'b1]	<= SIO_r[0];
					r_RX_Bit_Count	<= r_RX_Bit_Count - 3'd2;
				end
			end
			
			else if (BUS_MODE == 2 | BUS_MODE == 3) 
			begin
				if(r_RX_Bit_Count == 3)begin
					r_RX_Bit_Count	<= 3'd7;
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[3];
					o_RX_Byte[r_RX_Bit_Count - 2'b01]	<= SIO_r[2];
					o_RX_Byte[r_RX_Bit_Count - 2'b10]	<= SIO_r[1];
					o_RX_Byte[r_RX_Bit_Count - 2'b11]	<= SIO_r[0];
				end
				else begin
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[3];
					o_RX_Byte[r_RX_Bit_Count - 2'b01]	<= SIO_r[2];
					o_RX_Byte[r_RX_Bit_Count - 2'b10]	<= SIO_r[1];
					o_RX_Byte[r_RX_Bit_Count - 2'b11]	<= SIO_r[0];
					r_RX_Bit_Count	<= r_RX_Bit_Count - 3'd4;
				end
			end
			
			else begin
				if(r_RX_Bit_Count == 0) begin
					r_RX_Bit_Count	<= 3'd7;
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[0];
				end
				else begin
					o_RX_Byte[r_RX_Bit_Count]	<= SIO_r[0];
					r_RX_Bit_Count	<= r_RX_Bit_Count - 3'd1;
				end
			end
		end
	  end	//else if rTXDV
    end
  end
  
  
  // Purpose: Add clock delay to signals for alignment.
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      o_SPI_Clk  <= w_CPOL;
    end
    else
      begin
		SIO_r <= SIO_OUT;
        o_SPI_Clk <= r_SPI_Clk;
      end // else: !if(~i_Rst_L)
  end // always @ (posedge i_Clk or negedge i_Rst_L)
  

endmodule // SPI_Master
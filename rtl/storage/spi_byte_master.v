// SPI mode 0. All logic uses clk; SCK is an output, never a fabric clock.
module spi_byte_master (
    input wire clk, input wire rst_n,
    input wire start, input wire [7:0] tx_data,
    input wire [15:0] half_period,
    input wire miso, output reg sck, output reg mosi,
    output reg busy, output reg done, output reg [7:0] rx_data
);
    reg [15:0] divider;
    reg [2:0] bit_index;
    reg [7:0] tx_shift, rx_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck<=0; mosi<=1; busy<=0; done<=0; rx_data<=0;
            divider<=0; bit_index<=0; tx_shift<=0; rx_shift<=0;
        end else begin
            done<=0;
            if (!busy) begin
                sck<=0;
                if (start) begin
                    busy<=1; bit_index<=7; tx_shift<=tx_data;
                    mosi<=tx_data[7]; divider<=half_period-1'b1;
                    rx_shift<=0;
                end
            end else if (divider!=0) divider<=divider-1'b1;
            else begin
                divider<=half_period-1'b1;
                if (!sck) begin
                    sck<=1; rx_shift<={rx_shift[6:0],miso};
                end else begin
                    sck<=0;
                    if (bit_index==0) begin
                        busy<=0; done<=1; rx_data<=rx_shift; mosi<=1;
                    end else begin
                        bit_index<=bit_index-1'b1;
                        tx_shift<={tx_shift[6:0],1'b1}; mosi<=tx_shift[6];
                    end
                end
            end
        end
    end
endmodule

`timescale 1ns/1ps
module board_wrapper_tb;
    reg clk=0,rst_n=1,key_n=1;
    always #10 clk=~clk;
    wire [3:0] led;
    wire cs,sck,mosi,hclk,d0,d1,d2;
    hdmi_player_board_top #(.ENABLE_FADE(0),.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4)) dut(
        .SYS_CLK(clk),.Reset_n(rst_n),.KEY_LOAD_N(key_n),.KEY_SPECTRUM_N(1'b1),.KEY_AUTO_N(1'b1),.KEY_PREV_N(1'b1),.SW_AUDIO_N(1'b1),.SW_MUTE_N(1'b1),.KEY_NEXT_N(1'b1),.key_in(7'h7f),.key_img(4'hf),.LED(led),
        .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(1'b1),
        .HDMI_CLK_P(hclk),.HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2));
    task cycles(input integer n);repeat(n)@(negedge clk);endtask
    task press;key_n=0;cycles(10);key_n=1;cycles(10);endtask
    initial begin
        // Power-on reset must work even if the reset button starts released.
        cycles(7);if(dut.board_reset_n!==0)$fatal(1,"power-on reset too short");
        wait(dut.board_reset_n);cycles(2);
        if(dut.u_player.starts!=0 || dut.request_pending)$fatal(1,"spurious boot request");
        dut.u_player.memory_drive=1;dut.u_player.card_drive=1;cycles(2);
        if(led[1:0]!==2'b11)$fatal(1,"initialization LED wiring");
        // Bounce must not trigger. A request before ready is retained.
        key_n=0;cycles(1);key_n=1;cycles(1);key_n=0;cycles(1);key_n=1;cycles(12);
        if(dut.request_pending || dut.u_player.starts!=0)$fatal(1,"bounce triggered load");
        press();if(!dut.request_pending || dut.u_player.starts!=0)$fatal(1,"request was not queued");
        dut.u_player.ready_drive=1;cycles(3);
        if(dut.u_player.starts!=1 || dut.request_pending)$fatal(1,"queued request did not fire once");
        // A held button produces one request, even after ready remains high.
        key_n=0;cycles(40);
        if(dut.u_player.starts!=2)$fatal(1,"held key repeated");
        key_n=1;cycles(12);
        dut.u_player.display_drive=1;cycles(4);
        if(led[2]!==1)$fatal(1,"display status not synchronized");
        dut.u_player.underflow_drive=1;cycles(4);
        dut.u_player.underflow_drive=0;cycles(4);
        if(led[3]!==1)$fatal(1,"error indicator not sticky");
        // Reset discards a queued request and clears indicators.
        dut.u_player.ready_drive=0;press();
        if(!dut.request_pending)$fatal(1,"busy request missing");
        rst_n=0;#1;
        if(dut.board_reset_n!==0 || dut.request_pending!==0 || led!==0)$fatal(1,"external reset propagation");
        dut.u_player.memory_drive=0;dut.u_player.card_drive=0;dut.u_player.display_drive=0;
        cycles(2);rst_n=1;wait(dut.board_reset_n);
        dut.u_player.ready_drive=1;cycles(12);
        if(dut.u_player.starts!=2)$fatal(1,"stale request after reset");
        press();if(dut.u_player.starts!=3)$fatal(1,"fresh request after reset");
        if({cs,sck,mosi,hclk,d2,d1,d0}!==7'b1011010)$fatal(1,"external signal wiring");
        $display("BOARD_WRAPPER_PASS starts=3 bounce_ignored=1 held_key_once=1 pending_retained=1 poweron_and_external_reset=1 led_cdc_and_sticky_error=1 fixed_configuration=1");
        $finish;
    end
    initial begin #20000;$fatal(1,"wrapper timeout");end
endmodule

module hdmi_player_top #(parameter CLK_HZ=50000000,parameter ENABLE_AUDIO=0,parameter ENABLE_FADE=0,parameter ENABLE_SPECTRUM=0,parameter SPECTRUM_DB_CYCLES=262144,parameter FADE_STEP=1)(
    input audio_enable,audio_mute,output audio_error,output [7:0] audio_error_code,
input select_last,output [15:0] opened_file_index,
    input spectrum_key_n,input [6:0] key_in, input [3:0] key_img,
    input SYS_CLK,Reset_n,start,input [15:0] file_index,input [20:0] frame_base_addr,
    output load_ready,load_busy,load_done,load_error,output [7:0] load_error_code,
    output [3:0] debug_error_flags,
    output card_initialized,sd_cs_n,sd_sck,sd_mosi,input sd_miso,
    output memory_frame_write_done,LED,display_ready,display_underflow,
    output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P
);
    reg ready_drive=0,memory_drive=0,card_drive=0,display_drive=0,underflow_drive=0;
    integer starts=0;
    always @(posedge SYS_CLK)if(Reset_n && start)begin
        if(!load_ready || file_index!==0 || frame_base_addr!==0)$fatal(1,"incorrect core configuration");
        starts=starts+1;
    end
    reg [1:0] fake_busy=0;
    reg fake_done=0;
    always @(posedge SYS_CLK) begin
        if(!Reset_n)begin fake_busy<=0;fake_done<=0;end
        else begin
            fake_done<=0;
            if(start)fake_busy<=2;
            else if(fake_busy!=0)begin fake_busy<=fake_busy-1'b1;if(fake_busy==1)fake_done<=1;end
        end
    end
    assign audio_error=0;assign audio_error_code=0;
assign opened_file_index=0;
    assign load_ready=Reset_n && ready_drive && fake_busy==0;assign load_busy=fake_busy!=0;assign load_done=fake_done;
    assign debug_error_flags=4'b0000;
    assign load_error=0;assign load_error_code=0;assign card_initialized=Reset_n && card_drive;
    assign LED=Reset_n && memory_drive;assign display_ready=Reset_n && display_drive;
    assign display_underflow=Reset_n && underflow_drive;assign memory_frame_write_done=0;
    assign {sd_cs_n,sd_sck,sd_mosi,HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P}=7'b1011010;
endmodule

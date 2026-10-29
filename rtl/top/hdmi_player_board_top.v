// HX4S20 board wrapper. KEY1 resets; KEY2 queues one image-load request.
// The application core keeps its reusable configuration/status interface.
module hdmi_player_board_top #(
    parameter integer CLK_HZ=50000000,
    parameter integer POWERUP_CYCLES=CLK_HZ/50,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50
)(
    input wire SYS_CLK,
    input wire Reset_n,
    input wire KEY_LOAD_N,
    output wire [3:0] LED,
    output wire sd_cs_n,
    output wire sd_sck,
    output wire sd_mosi,
    input wire sd_miso,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P
);
    localparam integer POWER_BITS=POWERUP_CYCLES>1?$clog2(POWERUP_CYCLES):1;
    localparam integer DEBOUNCE_BITS=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    // Explicit FPGA initialization also supplies reset when KEY1 is not held
    // during configuration. After any reset, wait 20 ms at the default clock.
    reg [POWER_BITS-1:0] power_count=0;
    reg power_ready=0;
    always @(posedge SYS_CLK or negedge Reset_n) begin
        if(!Reset_n) begin power_count<=0;power_ready<=0;end
        else if(!power_ready) begin
            if(power_count==POWERUP_CYCLES-1) power_ready<=1;
            else power_count<=power_count+1'b1;
        end
    end
    wire reset_request=!Reset_n || !power_ready;
    reg [1:0] reset_release;
    always @(posedge SYS_CLK or posedge reset_request) begin
        if(reset_request)reset_release<=0;
        else reset_release<={reset_release[0],1'b1};
    end
    wire board_reset_n=reset_release[1];

    reg key_meta,key_sync,key_stable,key_previous;
    reg [DEBOUNCE_BITS-1:0] key_count;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n) begin
            key_meta<=1;key_sync<=1;key_stable<=1;key_previous<=1;key_count<=0;
        end else begin
            key_meta<=KEY_LOAD_N;
            key_sync<=key_meta;
            key_previous<=key_stable;
            if(key_sync==key_stable)key_count<=0;
            else if(key_count==DEBOUNCE_CYCLES-1)begin
                key_stable<=key_sync;key_count<=0;
            end else key_count<=key_count+1'b1;
        end
    end
    wire key_press=key_previous && !key_stable;
    reg request_pending;
    wire load_ready,load_error,card_initialized,memory_ready;
    wire display_ready,display_underflow;
    wire load_start=request_pending && load_ready;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n)request_pending<=0;
        else if(key_press)request_pending<=1;
        else if(load_start)request_pending<=0;
    end

    // These two independent indicators originate in the pixel domain.
    reg [1:0] display_status_meta,display_status_sync;
    reg error_seen;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n)begin
            display_status_meta<=0;display_status_sync<=0;error_seen<=0;
        end else begin
            display_status_meta<={display_ready,display_underflow};
            display_status_sync<=display_status_meta;
            if(load_error || display_status_sync[0])error_seen<=1;
        end
    end
    // Four discrete LEDs are active high (not the multiplexed digit LEDs).
    assign LED={error_seen,display_status_sync[1],card_initialized,memory_ready};

    hdmi_player_top #(.CLK_HZ(CLK_HZ)) u_player (
        .SYS_CLK(SYS_CLK),.Reset_n(board_reset_n),
        .start(load_start),.file_index(16'd0),.frame_base_addr(21'd0),
        .load_ready(load_ready),.load_busy(),.load_done(),
        .load_error(load_error),.load_error_code(),.card_initialized(card_initialized),
        .sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
        .memory_frame_write_done(),.LED(memory_ready),
        .display_ready(display_ready),.display_underflow(display_underflow),
        .HDMI_CLK_P(HDMI_CLK_P),.HDMI_D2_P(HDMI_D2_P),
        .HDMI_D1_P(HDMI_D1_P),.HDMI_D0_P(HDMI_D0_P)
    );
endmodule

module fir 
#(  parameter pADDR_WIDTH  = 12,                    // * width of aaddress
    parameter pDATA_WIDTH  = 32,                    // * width of data transfer
    parameter pCONFIG_REF  = 8,                     // *  
    parameter pCLEAR_WIDTH = 32                    // * clear_buff width (need to be smaller than data、address width)
)
(
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n,

    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,  

    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast,
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A

);


wire [(pCLEAR_WIDTH-1):0]                       clear_buff;

//-------------------------------------------------------------------------------------------------------------//
//                                         AXI-LITE INTERFACE (TAP INPUT)                        
//-------------------------------------------------------------------------------------------------------------//
reg [(pDATA_WIDTH-1):0]                         tbuff_data          , tbuff_data_nxt ;
reg [(pDATA_WIDTH-1):0]                         rtbuff_data         , rtbuff_data_nxt;
reg [(pADDR_WIDTH-1):0]                         tbuff_addr          , tbuff_addr_nxt ;

reg                                             EN_h                , EN_h_nxt;
reg                                             tbuff_data_v        , tbuff_data_v_nxt;
reg                                             tbuff_addr_v        , tbuff_addr_v_nxt;
reg                                             arready_r           , arready_r_nxt;
reg                                             rvalid_r            , rvalid_r_nxt;
reg                                             rtbuff_valid        , rtbuff_valid_nxt;
reg                                             awready_r           , awready_r_nxt;
reg                                             wready_r            , wready_r_nxt;
reg                                             arready_nxt;

reg [3:0]                                       WE_h;
reg [(pADDR_WIDTH-1):0]                         tap_A_r ;
reg [4:0]                                       h_out_p_r           , h_out_p_r_nxt;
//-------------------------------------------------------------------------------------------------------------//
//                                         AXI-STREAM INTERFACE (DATA INPUT)                        
//-------------------------------------------------------------------------------------------------------------//
reg[(pDATA_WIDTH-1):0]                          x_buff_d            , x_buff_d_nxt ;
reg                                             x_buff_v            , x_buff_v_nxt ;
reg                                             ss_tlast_r          , ss_tlast_r_nxt ;
reg                                             data_full_r         , data_full_r_nxt;
reg                                             ss_tready_r         , ss_tready_r_nxt;
reg [3:0]                                       WE_x_r              , WE_x_r_nxt ;
//-------------------------------------------------------------------------------------------------------------//
//                                             FIR ENGINE                        
//-------------------------------------------------------------------------------------------------------------//
reg [2:0]                                       ap_reg              , ap_reg_nxt;
reg [(pDATA_WIDTH-1):0]                         config_data_length  , config_data_length_nxt ;
reg [(pDATA_WIDTH-1):0]                         config_tap_num      , config_tap_num_nxt ;
reg [(pDATA_WIDTH-1):0]                         config_rdata        , x_in_cnt;
reg [(pDATA_WIDTH-1):0]                         y_buff              , y_buff_nxt;
wire[(pDATA_WIDTH-1):0]                         y_cnt_lave          ;

reg [4:0]                                       x_in_p_r            , x_in_p_r_nxt ;
reg [4:0]                                       x_out_p_r           , x_out_p_r_nxt ;
wire[4:0]                                       x_p_diff_oi         , x_p_diff_io;

reg [(pDATA_WIDTH-1):0]                         x_dat_r             , h_dat_r;
reg [(pDATA_WIDTH-1):0]                         x_dat_r_nxt         , h_dat_r_nxt;
reg signed [(pDATA_WIDTH-1):0]                  acc_reg             , acc_reg_nxt;
reg signed [(pDATA_WIDTH-1):0]                  mul_reg             , mul_reg_nxt;

reg                                             ss_stall            , ss_stall_nxt ;
reg                                             ss_stall_3          , ss_stall_3_nxt ;
reg                                             ss_stall_1          , ss_stall_2 ;
reg                                             ss_stall_1_nxt      , ss_stall_2_nxt;

reg [2:0]                                       dirty_v_cnt         , dirty_v_cnt_nxt ;
reg[(pDATA_WIDTH-1):0]                          data_out_cnt        , data_out_cnt_nxt ;
reg                                             sm_tlast_r          , sm_tlast_r_nxt;
reg                                             sm_tvalid_r         , sm_tvalid_r_nxt ;
reg                                             sm_stall            , sm_stall_nxt ;
reg                                             sm_stall_1          , sm_stall_1_nxt ;
reg                                             fir_last ;

reg                                             acc_clear           , acc_clear_nxt ;
reg                                             clear_last          , clear_last_nxt ;
reg                                             clear_last_1        , clear_last_1_nxt ;
reg                                             clear_last_2        , clear_last_2_nxt ;
reg                                             clear_last_3        , clear_last_3_nxt ;
//-------------------------------------------------------------------------------------------------------//
//                                            PARAMETER SET
//-------------------------------------------------------------------------------------------------------//

assign clear_buff   = { pCLEAR_WIDTH{1'b0} };


//-------------------------------------------------------------------------------------------------------//
//                                          FIR ENGINE (PIPELINE)
//-------------------------------------------------------------------------------------------------------//
assign sm_tdata     = y_buff;
assign sm_tvalid    = sm_tvalid_r;
assign sm_tlast     = sm_tlast_r ;

assign x_p_diff_oi  = x_out_p_r - x_in_p_r ;
assign x_p_diff_io  = x_in_p_r - x_out_p_r ;
assign y_cnt_lave   = config_data_length - data_out_cnt ;


always @(*) begin           //---sm_tvalid
    if(dirty_v_cnt < 3'd2) begin
        dirty_v_cnt_nxt = (acc_clear && (!ss_stall_1) && (!sm_stall_1))? (dirty_v_cnt + 3'd1) : (dirty_v_cnt);
    end else begin
        dirty_v_cnt_nxt = dirty_v_cnt ;
    end
end

always @(*) begin           //---sm_tvalid
    if(dirty_v_cnt < 3'd2)begin
        sm_tvalid_r_nxt = 1'b0;
    end else begin
        if(sm_tready && sm_tvalid_r)begin
            sm_tvalid_r_nxt = 1'b0;
        end else if(!sm_tvalid_r) begin
            sm_tvalid_r_nxt = (acc_clear && (!ss_stall_1) && (!sm_stall_1))? 1'b1 : 1'b0;
        end else begin
            sm_tvalid_r_nxt = sm_tvalid_r ;
        end
    end
end

always @(*) begin
    x_dat_r_nxt = data_Do ;
    h_dat_r_nxt = tap_Do  ;
    mul_reg_nxt = (x_in_cnt > 32'd0)? x_dat_r * h_dat_r : 32'd0 ;
end

always @(*) begin           //---acc_reg
    if(x_in_cnt > 32'd0)begin
        acc_reg_nxt = (acc_clear)? mul_reg : (mul_reg + acc_reg);
    end else begin
        acc_reg_nxt = acc_reg ;
    end
end 

always @(*) begin           //---cleanear stage
    fir_last  = (x_in_cnt == config_data_length)? 1'b1: 1'b0 ;
    clear_last_1_nxt = clear_last ;
    clear_last_2_nxt = clear_last_1;
    clear_last_3_nxt = clear_last_2;
end

always @(*) begin           //---last data cleaner
    if(fir_last)begin
        if(data_full_r)begin
            clear_last_nxt = (x_p_diff_oi == 5'd1) ? 1'b1 : 1'b0;
        end else begin
            clear_last_nxt = (x_out_p_r == 5'd0)? 1'b1 : 1'b0;
        end
    end else begin
        clear_last_nxt = 1'b0 ;
    end
end

always @(*) begin           //--- h_out_pointer
    if(!data_full_r)begin
        if(x_out_p_r == 5'd0)begin
            h_out_p_r_nxt = 5'd0 ;
        end else begin
            h_out_p_r_nxt = h_out_p_r + 5'd1;
        end
    end else if(x_in_p_r == 5'd31)begin
        if(x_out_p_r == 5'd0)begin
            h_out_p_r_nxt = 5'd0 ;
        end else begin
            h_out_p_r_nxt = h_out_p_r + 5'd1;
        end
    end else begin
        if(x_p_diff_oi == 5'd1)begin
            h_out_p_r_nxt = 5'd0 ;
        end else begin
            h_out_p_r_nxt = h_out_p_r + 5'd1;
        end
    end
end

always @(*) begin           //--- x_in_pointer
    if(!data_full_r)begin
        if(x_out_p_r == 5'd0)begin
            x_in_p_r_nxt = x_in_p_r + 5'd1 ;
        end else begin
            x_in_p_r_nxt = x_in_p_r ;
        end
    end else if(x_in_p_r == 5'd31)begin
        if(x_out_p_r == 5'd0)begin
            x_in_p_r_nxt = x_in_p_r + 5'd1;
        end else begin
            x_in_p_r_nxt = x_in_p_r ;
        end
    end else begin
        if(x_p_diff_oi == 5'd1)begin
            x_in_p_r_nxt = x_in_p_r + 5'd1;
        end else begin
            x_in_p_r_nxt = x_in_p_r ;
        end
    end
end

always @(*) begin           //--- x_out_pointer
    if(!data_full_r)begin
        if(x_out_p_r == 5'd0)begin
            x_out_p_r_nxt = x_in_p_r_nxt ;
        end else begin
            x_out_p_r_nxt = x_out_p_r - 5'd1;
        end
    end else if(x_in_p_r == 5'd31)begin
        if(x_out_p_r == 5'd0)begin
            x_out_p_r_nxt = x_in_p_r_nxt ;
        end else begin
            x_out_p_r_nxt = x_out_p_r - 5'd1;
        end
    end else begin
        if(x_p_diff_oi == 5'd1)begin
            x_out_p_r_nxt = x_in_p_r_nxt ;
        end else begin
            x_out_p_r_nxt = x_out_p_r - 5'd1;
        end
    end
end

always @(*) begin           //---y_buff
    y_buff_nxt = (acc_clear || clear_last_3)? acc_reg : y_buff;
end

always @(*) begin           //---y_cnt
    if(sm_tvalid_r && sm_tready)begin
        data_out_cnt_nxt = data_out_cnt +1 ;
    end else begin
        data_out_cnt_nxt = data_out_cnt ;
    end
end



always @(*) begin           //---sm_stall
    if(sm_stall)begin
        sm_stall_nxt = (sm_tvalid_r && sm_tready)?  1'b0 : 1'b1 ;
    end else if(!data_full_r)begin
        if(x_in_p_r < 5'd2)begin
            sm_stall_nxt = 1'b0 ;  
        end else begin    
            sm_stall_nxt = ((h_out_p_r == 5'd1) && sm_tvalid_r && (!sm_tready))? 1'b1 : 1'b0 ;
        end    
    end else  begin
        sm_stall_nxt = ((h_out_p_r == 5'd1) && sm_tvalid_r && (!sm_tready))? 1'b1 : 1'b0 ;
    end
end

always @(*) begin           //---sm_tlast
    if(sm_tlast_r)begin
        if(sm_tready && sm_tvalid_r)begin
            sm_tlast_r_nxt = 1'b0;
        end else begin
            sm_tlast_r_nxt = sm_tlast_r;
        end
    end else if(y_cnt_lave == 32'd1)begin
        if(sm_tvalid_r_nxt)begin
            sm_tlast_r_nxt = 1'b1;
        end else begin
            sm_tlast_r_nxt = 1'b0;
        end
    end else begin
        sm_tlast_r_nxt = 1'b0;
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //*---sm_stall
    if(!axis_rst_n)begin
        sm_stall   <= 1'b0;
        sm_stall_1 <= 1'b0;
    end else if(ap_reg[0])begin
        sm_stall   <= 1'b0;
        sm_stall_1 <= 1'b0;
    end else if(ap_reg[1])begin
        sm_stall   <= 1'b0;
        sm_stall_1 <= 1'b0; 
    end else if(!ap_reg[2])begin
        sm_stall   <= sm_stall_nxt ;
        sm_stall_1 <= sm_stall_1_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //*---h_out_pointer
    if(!axis_rst_n)begin
        h_out_p_r <= 5'd0 ;
    end else if(ap_reg[0])begin
        h_out_p_r <= 5'd0 ;  
    end else if(ap_reg[1])begin   
        h_out_p_r <= 5'd0 ;
    end else if((!ap_reg[2]) && (!ss_stall) && (!sm_stall))begin
        h_out_p_r <= h_out_p_r_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //*---x_pointer
    if(!axis_rst_n)begin
        x_out_p_r <= 5'd0 ;
        x_in_p_r  <= 5'd31 ;
    end else if(ap_reg[0])begin
        x_out_p_r <= 5'd0 ;
        x_in_p_r  <= 5'd31 ;  
    end else if(ap_reg[1])begin
        x_out_p_r <= 5'd0 ;
        x_in_p_r  <= 5'd31 ;     
    end else if((!ap_reg[2]) && (!ss_stall) && (!sm_stall))begin
        x_out_p_r <= x_out_p_r_nxt ;
        x_in_p_r  <= x_in_p_r_nxt  ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---sm_tvalid
    if(!axis_rst_n)begin
        sm_tvalid_r <= 1'b0 ;
        dirty_v_cnt <= 3'd0 ;
    end else if(ap_reg[0])begin
        sm_tvalid_r <= 1'b0 ;
        dirty_v_cnt <= 3'd0;
    end else if(ap_reg[1])begin
        sm_tvalid_r <= 1'b0 ;
        dirty_v_cnt <= 3'd0;
    end else if(!ap_reg[2]) begin
        sm_tvalid_r <= sm_tvalid_r_nxt ;
        dirty_v_cnt <= dirty_v_cnt_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---y_buff
    if(!axis_rst_n)begin
        y_buff <= clear_buff[(pDATA_WIDTH-1):0];
    end else if(ap_reg[0])begin
        y_buff <= clear_buff[(pDATA_WIDTH-1):0];
    end else if(ap_reg[1])begin
        y_buff <= clear_buff[(pDATA_WIDTH-1):0];
    end else if((!ap_reg[2]) && (!ss_stall_1) && (!sm_stall_1))begin
        y_buff <= y_buff_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //*---y_cnt
    if(!axis_rst_n)begin
        data_out_cnt <= clear_buff[(pDATA_WIDTH-1):0] ;
    end else if(ap_reg[0])begin
        data_out_cnt <= clear_buff[(pDATA_WIDTH-1):0] ;
    end else if(ap_reg[1])begin
        data_out_cnt <= clear_buff[(pDATA_WIDTH-1):0] ; 
    end else if ((!ap_reg[2]))begin
        data_out_cnt <= data_out_cnt_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---sm_tlast
    if(!axis_rst_n)begin
        sm_tlast_r <= 1'b0;
    end else if(ap_reg[0])begin
        sm_tlast_r <= 1'b0;
    end else if(ap_reg[1])begin
        sm_tlast_r <= 1'b0;
    end else if((!ap_reg[2])) begin
        sm_tlast_r <= sm_tlast_r_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- pipeline data reg
    if(!axis_rst_n)begin
        x_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
        h_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
    end else if(ap_reg)begin
        x_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
        h_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
    end else if(ap_reg[1])begin
        x_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
        h_dat_r <= clear_buff[(pDATA_WIDTH-1):0] ;
    end else if((!ap_reg[2]) && (!ss_stall_1 ) && (!sm_stall_1))begin
        x_dat_r <= x_dat_r_nxt ;
        h_dat_r <= h_dat_r_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---pipeline mul、acc reg       
    if(!axis_rst_n)begin
        mul_reg   <= 32'd0;
        acc_reg   <= 32'd0 ;
    end else if(ap_reg[0])begin
        mul_reg   <= 32'd0;
        acc_reg   <= 32'd0;
    end else if(ap_reg[1])begin
        mul_reg   <= 32'd0;
        acc_reg   <= 32'd0;      
    end else if ((!ap_reg[2]) && (!ss_stall_1 ) && (!sm_stall_1) )begin
        mul_reg   <= mul_reg_nxt ;
        acc_reg   <= acc_reg_nxt ;
    end    
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //--- last data cleaner stage
    if(!axis_rst_n)begin
        clear_last      <= 1'b0;
        clear_last_1    <= 1'b0;
        
    end else if(ap_reg[0])begin
        clear_last      <= 1'b0;
        clear_last_1    <= 1'b0;
        
    end else if(ap_reg[1])begin
        clear_last      <= 1'b0;
        clear_last_1    <= 1'b0;
        
    end else if((!ap_reg[2])) begin
        clear_last      <= clear_last_nxt ;
        clear_last_1    <= clear_last_1_nxt ;
        
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //--- last data cleaner
    if(!axis_rst_n)begin
        clear_last_2  <= 1'b0;
        clear_last_3  <= 1'b0;
    end else if(ap_reg[0])begin
        clear_last_2  <= 1'b0;
        clear_last_3  <= 1'b0;
    end else if(ap_reg[1])begin
        clear_last_2  <= 1'b0;
        clear_last_3  <= 1'b0;    
    end else if((!ap_reg[2]) && (!sm_stall_1)) begin
        clear_last_2  <= clear_last_2_nxt ;
        clear_last_3  <= clear_last_3_nxt ;

    end
end
//-------------------------------------------------------------------------------------------------------//
//                                     AXI-LITE INTERFACE (X input)
//-------------------------------------------------------------------------------------------------------//
assign ss_tready    = ss_tready_r;

assign data_A       = (WE_x_r[0])? {clear_buff[(pADDR_WIDTH-8):0] , x_in_p_r , 2'b0} : {clear_buff[(pADDR_WIDTH-7):0] , x_out_p_r , 2'd0}; 
assign data_EN      = (!ap_reg[2]);
assign data_WE      = WE_x_r;
assign data_Di      = x_buff_d;
assign x_dat        = data_Do ;


always @(*) begin           //---data_full_r : check whether the data ram is full
    if(x_in_cnt == 32'd32)begin
        data_full_r_nxt = 1'b1;
    end else begin
        data_full_r_nxt = data_full_r ;
    end
end



always @(*) begin           //--- x_buff_d
    if(ss_tready_r && ss_tvalid )begin
        x_buff_d_nxt = ss_tdata ; 
    end else begin
        x_buff_d_nxt = x_buff_d ;
    end
end

always @(*) begin               //--- x_buff_v
    if((ss_tlast_r) && (!x_buff_v))begin
        x_buff_v_nxt = x_buff_v ;
    end else if(ss_tlast_r && (x_buff_v))begin
        if(WE_x_r[0])begin
            x_buff_v_nxt = 1'b0 ;
        end else begin
            x_buff_v_nxt = x_buff_v ;
        end
    end else if(!x_buff_v)begin
        if(ss_tready_r && ss_tvalid)begin
            x_buff_v_nxt = 1'b1;
        end else begin
            x_buff_v_nxt = x_buff_v ;
        end
    end else if(data_WE) begin
        x_buff_v_nxt = 1'b0;
    end else begin
        x_buff_v_nxt = x_buff_v ;
    end
end

always @(*) begin               //---ss_tlast_r
    if(ss_tlast)begin
        if(ss_tready_r && ss_tvalid)begin
            ss_tlast_r_nxt = 1'b1;
        end else begin
            ss_tlast_r_nxt = ss_tlast_r ;
        end
    end else begin
        ss_tlast_r_nxt = ss_tlast_r ;
    end
end

always @(*) begin           //--- ss_tready_r
    if(ss_tlast_r)begin
        ss_tready_r_nxt = 1'b0;
    end else if(ss_tvalid && ss_tready_r)begin
        ss_tready_r_nxt = 1'b0 ;
    end else begin
        if(ss_tvalid && (!x_buff_v) && (!sm_stall))begin
            ss_tready_r_nxt = 1'b1;
        end else begin
            ss_tready_r_nxt = 1'b0;
        end
    end
end

always @(*) begin           //--- ss_stall
    if(ss_tlast_r && (!x_buff_v))begin
        ss_stall_nxt = 1'b0;
    end else begin
        if(ss_stall)begin
            if(WE_x_r && x_buff_v)begin
                ss_stall_nxt = 1'b0 ;
            end else begin
                ss_stall_nxt = ss_stall ;
            end
        end else if(!data_full_r)begin
            if(x_out_p_r == 5'd0)begin
                ss_stall_nxt = 1'b1;
            end else begin
                ss_stall_nxt = ss_stall ;
            end
        end else if(x_in_p_r == 5'd31)begin
            if(x_out_p_r == 5'd0)begin
                ss_stall_nxt = 1'b1;
            end else begin
                ss_stall_nxt = ss_stall ;
            end
        end else begin
            if(x_p_diff_oi == 5'd1)begin
                ss_stall_nxt = 1'b1;
            end else begin
                ss_stall_nxt = ss_stall;
            end
        end
    end
end

always @(*)begin            //--- ss_stall_123
    ss_stall_1_nxt = ss_stall ;
    sm_stall_1_nxt = sm_stall  ;
end

always @(*) begin               //*----acc_clear *
    if(!data_full_r)begin
        case(x_in_p_r)
            5'd0 :    acc_clear_nxt = 1'b0 ; 
            5'd1 :    acc_clear_nxt = 1'b1 ;
            5'd2 :    acc_clear_nxt = ((h_out_p_r == 5'd2)|| (h_out_p_r==5'd0) )? 1'b1 : 1'b0 ;
            default : acc_clear_nxt = (h_out_p_r == 5'd2)? 1'b1 : 1'b0 ;
        endcase    
    end else begin    
        acc_clear_nxt = (h_out_p_r == 5'd2)? 1'b1 :1'b0 ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //*--- acc_clear*
    if(!axis_rst_n)begin
        acc_clear  <= 1'b0;
    end else if(ap_reg[0])begin
        acc_clear  <= 1'b0;
    end else if(ap_reg[1])begin
        acc_clear  <= 1'b0;
    end else if((!ap_reg[2]) && (!sm_stall_1) && (!ss_stall_1)) begin
        acc_clear  <= acc_clear_nxt ;
    end
end


always @(posedge axis_clk or negedge axis_rst_n)begin           //--- ss_stall
    if(!axis_rst_n)begin;
        ss_stall_1  <= 1'b0;
        ss_stall    <= 1'b0;
    end else if(ap_reg[0])begin
        ss_stall_1  <= 1'b0;
        ss_stall    <= 1'b0;  
    end else if(ap_reg[1])begin
        ss_stall_1  <= 1'b0;
        ss_stall    <= 1'b0;
    end else if((!ap_reg[2]) && (!sm_stall)) begin
        ss_stall_1  <= ss_stall_1_nxt;
        ss_stall    <= ss_stall_nxt ;
    end
end
always @(*) begin
    if(ss_stall)begin
        WE_x_r = 4'B1111;
    end else begin
        WE_x_r = 4'b0000;
    end
end




always @(posedge axis_clk or negedge axis_rst_n ) begin         //--- x_in_cnt
    if(!axis_rst_n)begin
        x_in_cnt <= 32'd0;
    end else if(ap_reg[0])begin
        x_in_cnt <= 32'd0;
    end else if(ap_reg[1])begin
        x_in_cnt <= 32'd0;
    end else if(WE_x_r && x_buff_v && (!sm_stall)) begin
        x_in_cnt <= (x_in_cnt +32'd1) ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- ss_tready_r
    if(!axis_rst_n)begin
        ss_tready_r <= 1'b0;
    end else if(ap_reg[0])begin
        ss_tready_r <= 1'b0;
    end else if(ap_reg[1])begin
        ss_tready_r <= 1'b0;
    end else if(!ap_reg[2]) begin
        ss_tready_r <= ss_tready_r_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- x_buff
    if(!axis_rst_n)begin
        x_buff_v <= 1'b0;
        x_buff_d <= clear_buff[(pDATA_WIDTH-1):0];
    end else if(ap_reg[0])begin
        x_buff_v <= 1'b0;
        x_buff_d <= clear_buff[(pDATA_WIDTH-1):0];
    end else if(ap_reg[1])begin
        x_buff_v <= 1'b0;
        x_buff_d <= clear_buff[(pDATA_WIDTH-1):0];
    end else if(!ap_reg[2])begin
        x_buff_v <= x_buff_v_nxt ;
        x_buff_d <= x_buff_d_nxt ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---ss_tlast_r / data_full_r
    if(!axis_rst_n)begin
        ss_tlast_r <= 1'b0;
        data_full_r <= 1'b0 ;
    end else if(ap_reg[0])begin
        ss_tlast_r <= 1'b0;
        data_full_r <= 1'b0 ;
    end else if(ap_reg[1])begin
        ss_tlast_r <= 1'b0;
        data_full_r <= 1'b0 ;  
    end else if(!ap_reg[2])begin
        ss_tlast_r <= ss_tlast_r_nxt ;
        data_full_r <= data_full_r_nxt ;
    end
end

//-------------------------------------------------------------------------------------------------------//
//                                     AXI-LITE INTERFACE (H input)
//-------------------------------------------------------------------------------------------------------//
assign rdata   = rtbuff_data;
assign rvalid  = rvalid_r;
assign awready = awready_r;
assign wready  = wready_r;
assign arready = arready_r;

assign tap_WE  = WE_h;
assign tap_EN  = EN_h;
assign tap_Di  = tbuff_data;
assign tap_A   = tap_A_r;
assign h_dat   = tap_Do ;

always @(*) begin           //---wready
    if(wready)begin
        wready_r_nxt = 1'b0;
    end else if((!tbuff_data_v)&& wvalid)begin
        wready_r_nxt = 1'b1;
    end else begin
        wready_r_nxt = 1'b0;
    end
end

always @(*)begin            //--- awready
    if(awready)begin
        awready_r_nxt = 1'b0;
    end if((!tbuff_addr_v) && awvalid)begin
        awready_r_nxt = 1'b1;
    end else begin
        awready_r_nxt = 1'b0;
    end
end

always @(*) begin           //---tap_A_r
    if(WE_h)begin
        tap_A_r = tbuff_addr-12'h80;
    end else if(ap_reg[2] && (arvalid && arready_r_nxt)) begin
        tap_A_r = araddr-12'h80;
    end else begin
        if(!ap_reg[2])begin
            tap_A_r = {clear_buff[(pDATA_WIDTH-8):0] , h_out_p_r , 2'd0};        
        end else begin
            tap_A_r = clear_buff[(pADDR_WIDTH-1):0];
        end
    end
end

always @(*) begin           //*---rtbuff_data
    if(arvalid) begin
        if(!rvalid)begin
            if(arready_r)begin
                if(araddr[(pCONFIG_REF-1):0] < 8'h19)begin
                    rtbuff_data_nxt = config_rdata;
                end else begin 
                    if(ap_reg[2])begin
                        rtbuff_data_nxt = tap_Do;
                    end else begin
                        rtbuff_data_nxt = 32'hffff_ffff;
                    end
                end
            end else begin
                rtbuff_data_nxt = rtbuff_data;
            end
        end else begin
            rtbuff_data_nxt = rtbuff_data;
        end
    end else begin
        rtbuff_data_nxt = rtbuff_data;
    end
end

always @(*) begin           //*---rtbuff_valid
    if(arready_r)begin
        rtbuff_valid_nxt = 1'b1;
    end else if(rready)begin
        rtbuff_valid_nxt = 1'b0;
    end else begin
        rtbuff_valid_nxt = rtbuff_valid;
    end
end

always @(*) begin           //*---arready_r
    if(arready)begin
        arready_r_nxt = 1'b0;
    end else if(arvalid)begin
        if(((!tbuff_addr_v) && (!tbuff_data_v)) && ((!tbuff_addr_v_nxt) && (!tbuff_data_v_nxt)))begin
            arready_r_nxt = 1'b1;
        end else begin
            arready_r_nxt = 1'b0;
        end
    end else begin
        arready_r_nxt = 1'b0;
    end
end

always @(*) begin           //*---EN_h        
    if(!ap_reg[1])begin
        EN_h_nxt = 1'b1;;        //ap not done
    end else begin        
        EN_h_nxt = 1'b0;    //ap  iddle
    end
end

always @(*) begin           //*---rvalid_r
    if(rvalid && rready)begin
        rvalid_r_nxt = 1'b0;
    end else if(rtbuff_valid)begin
        rvalid_r_nxt = 1'b1;
    end else begin
        rvalid_r_nxt = 1'b0;
    end
end

always @(*) begin           //*---WE_h
    if(ap_reg[2])begin
        if(tbuff_addr_v && tbuff_data_v)begin
            if(tbuff_addr>12'h18)begin
                WE_h = 4'b1111;
            end else begin
                WE_h = 4'b0000;
            end
        end else begin
            WE_h = 4'b0000;
        end
    end else begin
        WE_h = 4'b0000;
    end
end

always @(*) begin           //*---tbuff_data_v
    if(!WE_h)begin
        if(wvalid && (!tbuff_data_v))begin
            tbuff_data_v_nxt = 1'b1; 
        end else begin
            if(tbuff_addr_v && tbuff_data_v)begin
                if(tbuff_addr <12'h19)begin
                    tbuff_data_v_nxt = 1'b0; 
                end else begin
                    tbuff_data_v_nxt = tbuff_data_v; 
                end
            end else begin
                tbuff_data_v_nxt = tbuff_data_v;
            end
        end
    end else begin
        tbuff_data_v_nxt = 1'b0;
    end
end

always @(*) begin           //*---tbuff_data
    if(wvalid && (!tbuff_data_v))begin
        tbuff_data_nxt = wdata; 
    end else begin
        tbuff_data_nxt = tbuff_data;
    end
end

always @(*) begin           //*---tbuff_addr_v
    if(!WE_h)begin
        if(awvalid && (!tbuff_addr_v))begin
            tbuff_addr_v_nxt = 1'b1; 
        end else begin
            if(tbuff_addr_v && tbuff_data_v)begin
                if(tbuff_addr <12'h19)begin
                    tbuff_addr_v_nxt = 1'b0; 
                end else begin
                    tbuff_addr_v_nxt = tbuff_addr_v; 
                end
            end else begin
                tbuff_addr_v_nxt = tbuff_addr_v;
            end
        end
    end else begin
        tbuff_addr_v_nxt = 1'b0;
    end
end

always @(*) begin           //*---tbuff_addr
    if(awvalid && (!tbuff_addr_v))begin
        tbuff_addr_nxt = awaddr; 
    end else begin
        tbuff_addr_nxt = tbuff_addr ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //*---tbuff_data_v
    if(!axis_rst_n)begin
        tbuff_data_v <= 1'b0;
    end else begin
        tbuff_data_v <= tbuff_data_v_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*--- tbuff_data
    if(!axis_rst_n)begin
        tbuff_data <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        tbuff_data <= tbuff_data_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---tbuff_addr_v
    if(!axis_rst_n)begin
        tbuff_addr_v <= 1'b0;
    end else begin
        tbuff_addr_v <= tbuff_addr_v_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*--- tbuff_addr
    if(!axis_rst_n)begin
        tbuff_addr <= clear_buff[(pADDR_WIDTH-1):0];
    end else begin
        tbuff_addr <= tbuff_addr_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---EN_h
    if(!axis_rst_n)begin
        EN_h <= 1'b0 ;
    end else begin
        EN_h <= EN_h_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---arready_r
    if(!axis_rst_n)begin
        arready_r <= 1'b0;
    end else begin
        arready_r <= arready_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---rvalid_r
    if(!axis_rst_n)begin
        rvalid_r <= 1'b0;
    end else begin
        rvalid_r <= rvalid_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //*---rtbuff_valid
    if(!axis_rst_n)begin
        rtbuff_valid <= 1'b0;
    end else begin
        rtbuff_valid <= rtbuff_valid_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---rtbuff_data
    if(!axis_rst_n)begin
        rtbuff_data <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        rtbuff_data <= rtbuff_data_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---wready
    if(!axis_rst_n)begin
        wready_r <= 1'b0;
    end else begin
        wready_r <= wready_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---awready
    if(!axis_rst_n)begin
        awready_r <= 1'b0;
    end else begin
        awready_r <= awready_r_nxt;
    end
end

//-------------------------------------------------------------------------------------------------------//
//                                         CONFIGURATION REG 
//-------------------------------------------------------------------------------------------------------//
always @(*)begin            //*---config_rdata
    if(arvalid)begin
        if(araddr < 12'h19)begin
            if(araddr == 12'h000)begin //read ap
                config_rdata = {clear_buff[(pDATA_WIDTH-1):3] ,ap_reg};
            end else if(araddr < 12'h0f)begin
                config_rdata = clear_buff[(pDATA_WIDTH-1):0] ;
            end else if(araddr < 12'h14)begin //read data length
                config_rdata = config_data_length;
            end else if(araddr < 12'h19)begin //read tap num
                config_rdata = config_tap_num;
            end else begin
                config_rdata = clear_buff[(pDATA_WIDTH-1):0];
            end
        end else begin
            config_rdata = clear_buff[(pDATA_WIDTH-1):0];
        end
    end else begin
        config_rdata = clear_buff[(pDATA_WIDTH-1):0];
    end 
end 

always @(*) begin           //*---ap_reg
    if(sm_tlast_r && sm_tready)begin
        ap_reg_nxt = 3'b110;           
    end else if(!ap_reg[2])begin // * ap not idle
        ap_reg_nxt = 3'b000;
    end else begin // * ap idle
        if(ap_reg[0]==1'b1)begin
            ap_reg_nxt = 3'b000;
        end else begin  
            if(tbuff_data_v && tbuff_addr_v)begin // 
                if(tbuff_addr == 12'b0000_0000_0000)begin
                    case(tap_Di[2:0])
                        3'b000: ap_reg_nxt = 3'b100; 
                        3'b001: ap_reg_nxt = 3'b001; 
                        3'b010: ap_reg_nxt = ap_reg; 
                        3'b011: ap_reg_nxt = 3'b001;
                        3'b100: ap_reg_nxt = 3'b100;
                        3'b101: ap_reg_nxt = 3'b001;
                        3'b110: ap_reg_nxt = ap_reg;
                        3'b111: ap_reg_nxt = 3'b001;   
                    endcase
                end else begin
                    ap_reg_nxt = ap_reg;
                end
            end else begin
                ap_reg_nxt = ap_reg;
            end
        end
    end
end

always @(*) begin           //*---config_data_length
    if(!ap_reg[2])begin //* ap not iddle 
        config_data_length_nxt = config_data_length;
    end else begin    //* ap iddle
        if(tbuff_addr_v && tbuff_data_v)begin 
            case(tbuff_addr)
                12'h10: config_data_length_nxt = tbuff_data;
                12'h11: config_data_length_nxt = tbuff_data;
                12'h12: config_data_length_nxt = tbuff_data;
                12'h13: config_data_length_nxt = tbuff_data;
                //12'h14: config_data_length_nxt = tbuff_data;
                default:  config_data_length_nxt = config_data_length;
            endcase
        end else begin
            config_data_length_nxt = config_data_length;
        end
    end
end

always @(*)begin            //*---tap_num
    if(!ap_reg[2])begin //* ap not idle
        config_tap_num_nxt = config_tap_num ;
    end else begin
        if(tbuff_addr_v && tbuff_data_v)begin 
            case(tbuff_addr)
                12'h14 : config_tap_num_nxt = tbuff_data;
                12'h15 : config_tap_num_nxt = tbuff_data;
                12'h16 : config_tap_num_nxt = tbuff_data;
                12'h17 : config_tap_num_nxt = tbuff_data;
                12'h18 : config_tap_num_nxt = tbuff_data;
                default: config_tap_num_nxt = config_tap_num ;
            endcase
        end else begin
            config_tap_num_nxt = config_tap_num ;
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin            //*---ap_reg
    if(!axis_rst_n)begin
        ap_reg <= 3'b100;
    end else begin
        ap_reg <= ap_reg_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*-- config_data_length
    if(!axis_rst_n)begin
        config_data_length <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        config_data_length <= config_data_length_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin            //*---tap_num
    if(!axis_rst_n)begin
        config_tap_num <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        config_tap_num <= config_tap_num_nxt;
    end
end


endmodule
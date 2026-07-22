
/*
----------------------------------------------------------------------------------
Copyright (c) 2013-2014

  Embedded and Network Computing Lab.
  Open SSD Project
  Hanyang University

All rights reserved.

----------------------------------------------------------------------------------

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  1. Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.

  2. Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.

  3. All advertising materials mentioning features or use of this source code
     must display the following acknowledgement:
     This product includes source code developed 
     by the Embedded and Network Computing Lab. and the Open SSD Project.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

----------------------------------------------------------------------------------

http://enclab.hanyang.ac.kr/
http://www.openssd-project.org/
http://www.hanyang.ac.kr/

----------------------------------------------------------------------------------
*/


`timescale 1ns / 1ps

module nvme_cq_check # (
	parameter	C_PCIE_DATA_WIDTH			= 512,
	parameter	C_PCIE_ADDR_WIDTH			= 48 //modified
)
(
	input									pcie_user_clk,
	input									pcie_user_rst_n,

	input									pcie_msi_en,

	input									cq_rst_n,
	input									cq_valid,
	input									io_cq_irq_en,
	input	[31:0]							cq_irq_retry_cycles,
	
	input	[7:0]							cq_tail_ptr,
	input	[7:0]							cq_head_ptr,
	input									cq_head_update,

	output									cq_legacy_irq_req,
	output									cq_msi_irq_req,
	input									cq_msi_irq_ack
	
);

localparam	LP_CQ_IRQ_DELAY_TIME			= 16'h0008;
localparam	LP_CQ_IRQ_PRE_DELAY_TIME		= 16'h0010;


localparam	S_IDLE							= 5'b00001;
localparam	S_CQ_MSI_IRQ_DELAY			= 5'b00010;
localparam	S_CQ_MSI_IRQ_REQ				= 5'b00100;
localparam	S_CQ_MSI_HEAD_SET				= 5'b01000;
localparam	S_CQ_MSI_IRQ_TIMER			= 5'b10000;

reg		[4:0]								cur_state;
reg		[4:0]								next_state;

reg		[7:0]								r_cq_tail_ptr;
reg		[7:0]								r_cq_msi_irq_head_ptr;
reg		[31:0]								r_irq_timer;
reg											r_cq_legacy_irq_req;
reg											r_cq_msi_irq_req;
reg											r_irq_armed;

wire											w_cq_rst_n;
wire											w_cq_irq_enabled;
wire											w_cq_msi_pending;

assign cq_legacy_irq_req = r_cq_legacy_irq_req;
assign cq_msi_irq_req = r_cq_msi_irq_req;

assign w_cq_rst_n = pcie_user_rst_n & cq_rst_n;
assign w_cq_irq_enabled = pcie_msi_en & cq_valid & io_cq_irq_en;
assign w_cq_msi_pending = r_irq_armed & (r_cq_msi_irq_head_ptr != r_cq_tail_ptr) & w_cq_irq_enabled;

always @ (posedge pcie_user_clk or negedge w_cq_rst_n)
begin
	if(w_cq_rst_n == 0) begin
		r_cq_tail_ptr <= 0;
		r_cq_legacy_irq_req <= 0;
	end
	else begin
		r_cq_tail_ptr <= cq_tail_ptr;
		r_cq_legacy_irq_req <= r_irq_armed & (cq_head_ptr != r_cq_tail_ptr) & (cq_valid & io_cq_irq_en);
	end
end

always @ (posedge pcie_user_clk or negedge w_cq_rst_n)
begin
	if(w_cq_rst_n == 0)
		cur_state <= S_IDLE;
	else
		cur_state <= next_state;
end

always @ (*)
begin
	case(cur_state)
		S_IDLE: begin
			if(w_cq_msi_pending == 1'b1)
				next_state <= S_CQ_MSI_IRQ_DELAY;
			else
				next_state <= S_IDLE;
		end
		S_CQ_MSI_IRQ_DELAY: begin
			if(r_irq_timer == 0)
				next_state <= S_CQ_MSI_IRQ_REQ;
			else
				next_state <= S_CQ_MSI_IRQ_DELAY;
		end
		S_CQ_MSI_IRQ_REQ: begin
			if(cq_msi_irq_ack == 1)
				next_state <= S_CQ_MSI_HEAD_SET;
			else
				next_state <= S_CQ_MSI_IRQ_REQ;
		end
		S_CQ_MSI_HEAD_SET: begin
			if(cq_head_update == 1 || (cq_head_ptr == r_cq_tail_ptr))
				next_state <= S_CQ_MSI_IRQ_TIMER;
			else if((r_irq_timer == 0) && (cq_irq_retry_cycles != 0))
				next_state <= S_CQ_MSI_IRQ_REQ;
			else
				next_state <= S_CQ_MSI_HEAD_SET;
		end
		S_CQ_MSI_IRQ_TIMER: begin
			if(r_irq_timer == 0)
				next_state <= S_IDLE;
			else
				next_state <= S_CQ_MSI_IRQ_TIMER;
		end
		default: begin
			next_state <= S_IDLE;
		end
	endcase
end


always @ (posedge pcie_user_clk)
begin
	case(cur_state)
		S_IDLE: begin
			if(w_cq_msi_pending == 1'b1)
				r_irq_timer <= LP_CQ_IRQ_PRE_DELAY_TIME;
		end
		S_CQ_MSI_IRQ_DELAY: begin
			r_irq_timer <= r_irq_timer - 1;
		end
		S_CQ_MSI_IRQ_REQ: begin
			if(cq_msi_irq_ack == 1'b1)
				r_irq_timer <= cq_irq_retry_cycles;
		end
		S_CQ_MSI_HEAD_SET: begin
			if(cq_head_update == 1'b1 || (cq_head_ptr == r_cq_tail_ptr))
				r_irq_timer <= LP_CQ_IRQ_DELAY_TIME;
			else if(r_irq_timer != 0)
				r_irq_timer <= r_irq_timer - 1'b1;
		end
		S_CQ_MSI_IRQ_TIMER: begin
			r_irq_timer <= r_irq_timer - 1;
		end
		default: begin

		end
	endcase
end

always @ (posedge pcie_user_clk or negedge w_cq_rst_n)
begin
	if(w_cq_rst_n == 0) begin
		r_cq_msi_irq_head_ptr <= 0;
		r_irq_armed <= 0;
	end
	else begin
		case(cur_state)
			S_IDLE: begin
				if(w_cq_irq_enabled == 1'b0) begin
					r_cq_msi_irq_head_ptr <= r_cq_tail_ptr;
					r_irq_armed <= 1'b0;
				end
				else if(r_irq_armed == 1'b0) begin
					r_cq_msi_irq_head_ptr <= r_cq_tail_ptr;
					r_irq_armed <= 1'b1;
				end
			end
			S_CQ_MSI_IRQ_REQ: begin
				if(cq_msi_irq_ack == 1'b1)
					r_cq_msi_irq_head_ptr <= r_cq_tail_ptr;
			end
			S_CQ_MSI_HEAD_SET: begin
				if(cq_head_update == 1'b1)
					r_cq_msi_irq_head_ptr <= cq_head_ptr;
				else if(cq_head_ptr == r_cq_tail_ptr)
					r_cq_msi_irq_head_ptr <= r_cq_tail_ptr;
			end
			S_CQ_MSI_IRQ_TIMER: begin

			end
			default: begin

			end
		endcase
	end


end

always @ (*)
begin
	case(cur_state)
		S_IDLE: begin
			r_cq_msi_irq_req <= 0;
		end
		S_CQ_MSI_IRQ_REQ: begin
			r_cq_msi_irq_req <= 1;
		end
		S_CQ_MSI_HEAD_SET: begin
			r_cq_msi_irq_req <= 0;
		end
		S_CQ_MSI_IRQ_TIMER: begin
			r_cq_msi_irq_req <= 0;
		end
		default: begin
			r_cq_msi_irq_req <= 0;
		end
	endcase
end


endmodule
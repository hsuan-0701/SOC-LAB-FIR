rtlsim:
	#vcs -R +v2k -full64 testfixture_a.v ../rtl/FIR.v -debug_acc +nospecify
	#vcs -R +v2k -full64 testfixture_b.v ../rtl/FIR.v -debug_acc +nospecify
	#vcs -R +v2k -full64 testfixture_c.v ../rtl/FIR.v -debug_acc +nospecify
	vcs tb.v  fir.v bram32.v -full64 -R -debug_access+all +v2k +nottimingcheck

gatesim:
	#vcs -R +v2k -full64 tb.v ../syn/netlist/FIR_syn.v ../bram/bram32.v -v /home/raid7_2/course/cvsd/CBDK_IC_Contest_v2.5/Verilog/tsmc13_neg.v +define+SDF -debug_acc +neg_tchk
	#vcs -R +v2k -full64 testfixture_b.v ../syn/netlist/FIR_syn.v -v /home/raid7_2/course/cvsd/CBDK_IC_Contest_v2.5/Verilog/tsmc13_neg.v +define+SDF -debug_acc +neg_tchk
	#vcs -R +v2k -full64 testfixture_c.v ../syn/netlist/FIR_syn.v -v /home/raid7_2/course/cvsd/CBDK_IC_Contest_v2.5/Verilog/tsmc13_neg.v +define+SDF -debug_acc +neg_tchk
	#vcs -R +v2k -full64 tb.v ../syn/netlist/fir_syn.v bram32.v -v ../syn/CBDK_TSMC018_Arm_f1.0/CIC/Verilog/tsmc18_neg.v  +define+SDF -debug_acc +neg_tchk  +no_specify
	vcs -R +v2k -full64 \
    ../hdl/tb.v \
    ../syn/netlist/fir_syn.v \
    ../hdl/bram32.v \
    -v ../syn/CBDK_TSMC018_Arm_f1.0/CIC/Verilog/tsmc18_neg.v \
    -sdf max:fir:../syn/netlist/fir_syn.sdf \
    -debug_acc +neg_tchk +no_specify
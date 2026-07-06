module dump();
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end
endmodule

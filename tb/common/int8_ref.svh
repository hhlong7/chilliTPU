// int8_ref.svh - SV reference functions that match sw/py/golden.py bit for bit.
// Included from tb_common_pkg.sv. All math is longint (64-bit), so nothing wraps:
// |acc + bias| < 2**33 and |(acc + bias) * scale| < 2**49.

// One output value through the frozen D1 rule (round half up, toward +inf).
// Same steps, same order as golden.requantize().
function automatic byte ref_requantize(longint acc, longint bias, longint scale,
                                       int unsigned shift, bit relu);
  longint s, p, q;
  s = acc + bias;
  if (relu && s < 0) s = 0;
  p = s * scale;
  if (shift == 0) q = p;
  else            q = (p + (longint'(1) << (shift - 1))) >>> shift;
  if (q > 127)  q = 127;
  if (q < -128) q = -128;
  return byte'(q);
endfunction

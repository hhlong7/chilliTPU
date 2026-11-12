// hex_vector_reader.svh - loads vectors/<case>/ (x.hex, w.hex, bias.hex, y_expected.hex, meta.json) into arrays.
// Status: SKELETON (included from tb_common_pkg.sv).
//
// TODO:
//   - $readmemh into dynamic arrays; sign-extend INT8 / INT32
//   - meta: parse a small key=value sidecar, or have vecgen.py also write meta.txt
//     (JSON parsing in SV is awkward; agree on this with the Python side)

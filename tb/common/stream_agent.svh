// stream_agent.svh - generic parameterized valid/ready agent (driver, monitor, sequencer, config).
// Status: SKELETON (included from tb_common_pkg.sv).
//
// TODO:
//   - parameterized by payload width; master (drive valid/data) and slave (drive ready) modes
//   - random backpressure knob (ready low probability) in the config object
//   - pairs with stream_if.sv

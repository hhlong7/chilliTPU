// D5 vector reader shared by UVM environments.
// Values are read as bit patterns; consumers cast INT8/INT32 words to signed
// types. Files contain one zero-padded two's-complement value per line.
class hex_vector_reader extends uvm_object;
  localparam int MAX_ELEMS = 65536;
  int M, K, N, scale, shift, relu, seed;
  int x_count, w_count, bias_count, acc_count, y_count;
  localparam int MAX_WORDS = (MAX_ELEMS + 3) / 4;
  int x_word_count, w_word_count, y_word_count;
  logic [31:0] x_words [MAX_WORDS];
  logic [31:0] w_words [MAX_WORDS];
  logic [31:0] y_words [MAX_WORDS];
  logic [7:0]  x [MAX_ELEMS];
  logic [7:0]  w [MAX_ELEMS];
  logic [31:0] bias [MAX_ELEMS];
  logic [31:0] acc_expected [MAX_ELEMS];
  logic [7:0]  y_expected [MAX_ELEMS];
  `uvm_object_utils(hex_vector_reader)

  function new(string name="hex_vector_reader"); super.new(name); endfunction

  // D5 has exactly two or eight hex digits per line, followed by LF or CRLF.
  function automatic bit parse_hex_line(string line, int digits,
                                        output logic [31:0] value);
    int length;
    byte unsigned ch;
    logic [3:0] nibble;
    length = line.len();
    value = '0;
    if (length > 0 && line.getc(length-1) == 8'h0a) length--;
    if (length > 0 && line.getc(length-1) == 8'h0d) length--;
    if (length != digits) return 0;
    for (int i = 0; i < digits; i++) begin
      ch = line.getc(i);
      if (ch >= "0" && ch <= "9") nibble = 4'(ch - "0");
      else if (ch >= "A" && ch <= "F") nibble = 4'(ch - "A" + 8'd10);
      else if (ch >= "a" && ch <= "f") nibble = 4'(ch - "a" + 8'd10);
      else return 0;
      value = {value[27:0], nibble};
    end
    return 1;
  endfunction

  function automatic int read_hex8(string path, ref logic [7:0] dst[MAX_ELEMS]);
    int fd, count;
    string line;
    logic [31:0] value;
    fd = $fopen(path, "r");
    if (!fd) return 0;
    count = 0;
    while ($fgets(line, fd)) begin
      if (count >= MAX_ELEMS || !parse_hex_line(line, 2, value)) begin
        $fclose(fd);
        `uvm_fatal("VEC", $sformatf("invalid or excess INT8 hex in %s at line %0d", path, count+1))
        return 0;
      end
      dst[count++] = value[7:0];
    end
    $fclose(fd);
    return count;
  endfunction

  function automatic int read_hex32(string path, ref logic [31:0] dst[MAX_ELEMS]);
    int fd, count;
    string line;
    logic [31:0] value;
    fd = $fopen(path, "r");
    if (!fd) return 0;
    count = 0;
    while ($fgets(line, fd)) begin
      if (count >= MAX_ELEMS || !parse_hex_line(line, 8, value)) begin
        $fclose(fd);
        `uvm_fatal("VEC", $sformatf("invalid or excess INT32 hex in %s at line %0d", path, count+1))
        return 0;
      end
      dst[count++] = value;
    end
    $fclose(fd);
    return count;
  endfunction

  function void load(string dir);
    string path, key; int value, fd, rc;
    // Files unused by a particular vector group are optional (for example,
    // out_stage cases provide acc.hex instead of X/W). Required fields are
    // checked by the consuming test against its metadata and use case.
    path={dir,"/x.hex"}; x_count=read_hex8(path,x);
    path={dir,"/w.hex"}; w_count=read_hex8(path,w);
    path={dir,"/bias.hex"}; bias_count=read_hex32(path,bias);
    path={dir,"/acc_expected.hex"}; acc_count=read_hex32(path,acc_expected);
    path={dir,"/y_expected.hex"}; y_count=read_hex8(path,y_expected);

    path={dir,"/meta.txt"}; fd=$fopen(path,"r");
    if(!fd) `uvm_fatal("VEC",$sformatf("cannot open %s",path))
    M=0; K=0; N=0; scale=0; shift=0; relu=0; seed=0;
    while(!$feof(fd)) begin
      rc=$fscanf(fd,"%s\n",key);
      if(rc==1 && $sscanf(key,"M=%d",value)==1) M=value;
      else if(rc==1 && $sscanf(key,"K=%d",value)==1) K=value;
      else if(rc==1 && $sscanf(key,"N=%d",value)==1) N=value;
      else if(rc==1 && $sscanf(key,"scale=%d",value)==1) scale=value;
      else if(rc==1 && $sscanf(key,"shift=%d",value)==1) shift=value;
      else if(rc==1 && $sscanf(key,"relu=%d",value)==1) relu=value;
      else if(rc==1 && $sscanf(key,"seed=%d",value)==1) seed=value;
    end
    $fclose(fd);
    if(M<0 || K<0 || N<0) `uvm_fatal("VEC","meta.txt dimensions cannot be negative")
    pack_loaded_int8();
  endfunction

  // Four consecutive INT8 elements per 32-bit BRAM word. Element 0 goes in
  // bits [7:0], then [15:8], [23:16], [31:24]. Partial final words are zeroed.
  function void pack_loaded_int8();
    x_word_count=(x_count+3)/4; w_word_count=(w_count+3)/4; y_word_count=(y_count+3)/4;
    for(int j=0;j<MAX_WORDS;j++) begin
      x_words[j]='0; w_words[j]='0; y_words[j]='0;
    end
    for(int i=0;i<x_count;i++) x_words[i/4][(i%4)*8+:8]=x[i];
    for(int i=0;i<w_count;i++) w_words[i/4][(i%4)*8+:8]=w[i];
    for(int i=0;i<y_count;i++) y_words[i/4][(i%4)*8+:8]=y_expected[i];
  endfunction

  // Bias and accumulator arrays are already INT32, so each value maps to one
  // 32-bit buffer word without byte packing.
  function automatic logic [31:0] bias_word(input int index);
    return bias[index];
  endfunction
  function automatic logic [31:0] acc_word(input int index);
    return acc_expected[index];
  endfunction
endclass

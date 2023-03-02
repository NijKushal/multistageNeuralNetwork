module MyDesign (
//---------------------------------------------------------------------------
//Control signals
  input   wire dut_run                    , 
  output  reg dut_busy                   ,
  input   wire reset_b                    ,  
  input   wire clk                        ,
 
//---------------------------------------------------------------------------
//Input SRAM interface
  output reg        input_sram_write_enable    ,
  output reg [11:0] input_sram_write_addresss  ,
  output reg [15:0] input_sram_write_data      ,
  output reg [11:0] input_sram_read_address    ,
  input wire [15:0] input_sram_read_data       ,

//---------------------------------------------------------------------------
//Output SRAM interface
  output reg        output_sram_write_enable    ,
  output reg [11:0] output_sram_write_addresss  ,
  output reg [15:0] output_sram_write_data      ,
  output reg [11:0] output_sram_read_address    ,
  input wire [15:0] output_sram_read_data       ,

//---------------------------------------------------------------------------
//Scratchpad SRAM interface
  output reg        scratchpad_sram_write_enable    ,
  output reg [11:0] scratchpad_sram_write_addresss  ,
  output reg [15:0] scratchpad_sram_write_data      ,
  output reg [11:0] scratchpad_sram_read_address    ,
  input wire [15:0] scratchpad_sram_read_data       ,

//---------------------------------------------------------------------------
//Weights SRAM interface                                                       
  output reg        weights_sram_write_enable    ,
  output reg [11:0] weights_sram_write_addresss  ,
  output reg [15:0] weights_sram_write_data      ,
  output reg [11:0] weights_sram_read_address    ,
  input wire [15:0] weights_sram_read_data       

);

  //YOUR CODE HERE
  reg enable_reading_N, kernel_matrix_read, alternate_reg_storage, enable_reading_input_matrix, enable_accumulating, enable_relu, max_pooling_output_flag, enable_maxpooling, write_to_sram_flag, accumulate_to_write_to_sram, write_to_higher_bits_flag, new_matrix_flag, append_zero_flag, output_sram_write_enable_flag, increment_address_flag, reset_flag_set;
  reg signed [7:0] kernel_matrix_0, kernel_matrix_1, kernel_matrix_2, kernel_matrix_3, kernel_matrix_4, kernel_matrix_5, kernel_matrix_6, kernel_matrix_7, kernel_matrix_8;
  reg signed [7:0] input_temp_reg_1, input_temp_reg_2, input_temp_reg_3, input_temp_reg_4, input_temp_reg_5, input_temp_reg_6;
  reg [5:0] current_state, next_state;
  reg [6:0] N_value, row_number, col_number_tracker;
  reg [1:0] traversal_row_number, row_number_tracker;
  reg signed [7:0] kernel_reg_1, kernel_reg_2, kernel_reg_3;
  reg signed [8:0] relu_output_2, relu_input_1, relu_output_1, relu_input_2, max_pooling_reg_1, max_pooling_reg_2;
  reg signed [19:0] accum1, accum2;
  reg [15:0] max_pooling_output, address_reference_for_right_shifting;
  reg [1:0] current_state_1, next_state_1;
  reg [19:0] write_to_higher_bits_counter;

  parameter [3:0]
    Idle = 4'b0000,
    read_N_state = 4'b0001,
    delay_state = 4'b0010,
    read_inputs_1 = 4'b0011,
    read_inputs_2 = 4'b0100,
    delay_state_1 = 4'b0101,
    delay_state_2 = 4'b0110,
    delay_state_3 = 4'b0111,
    delay_state_4 = 4'b1000,
    delay_state_5 = 4'b1001;

  parameter [1:0]
    start_relu = 2'b00,
    stop_relu = 2'b01,
    generate_output = 2'b10,
    write_to_sram = 2'b11;


  always @(*) begin
    alternate_reg_storage = 1;
    enable_accumulating = 0;  
    write_to_sram_flag = 0;
    enable_reading_N = 0;
    enable_reading_input_matrix = 0;
    dut_busy = 1;

    casex(current_state) 
      Idle: begin //Idle state
              dut_busy = 0;
              if(dut_run)
              begin     
                next_state = read_N_state;
              end
              else
                next_state = Idle;
            end

      read_N_state: begin //read N state
                      enable_reading_N = 1;
                      
                      if(new_matrix_flag) 
                        next_state = read_inputs_1;
                      else
                        next_state = delay_state;
                    end

      delay_state:  begin // delay state to handle clock pulse delay while reading input
                      enable_reading_N = 1;
                      next_state = read_inputs_1;
                    end

      read_inputs_1:  begin // to fill input_temp_reg_1,input_temp_reg_2, input_temp_reg_4 
                        if(N_value == 7'h7f)
                          begin
                            next_state = delay_state_1;
                            
                          end
                        else
                          begin
                            enable_reading_input_matrix = 1;
                            enable_accumulating = 1;
                            next_state = read_inputs_2;
                          end
                      end
      
      read_inputs_2:  begin // to fill input_temp_reg_3,input_temp_reg_5, input_temp_reg_6
                        alternate_reg_storage = 0;
                        if(new_matrix_flag)
                          next_state = read_N_state;
                        else
                          next_state = read_inputs_1;
                          enable_reading_input_matrix = 1;
                      end

      delay_state_1: begin //delay states to ensure the pipeline is clear before ending the execution on countering FFFF
                        next_state = delay_state_2;
                      end

      delay_state_2: begin
                        next_state = delay_state_3;
                      end
      
      delay_state_3: begin
                        next_state = delay_state_4;
                      end

      delay_state_4: begin
                      next_state = delay_state_5;
                    end

      delay_state_5: begin
                      next_state = Idle;
                    end

      default:  begin
                  next_state = Idle;
                end

    endcase
  end

  always @(posedge clk or negedge reset_b) begin
    if (!reset_b)
      current_state <= Idle;
    else
      current_state <= next_state;
  end

  always @(*) begin
    enable_relu = 0;    
    enable_maxpooling = 0; 
    casex(current_state_1) 
      start_relu:  // enable relu once we have convolution output ready
        begin
          if(traversal_row_number == 3 || reset_flag_set)
            begin
              next_state_1 = stop_relu;
              enable_relu = 1;
            end
          else if(traversal_row_number == 1)  // stay in the same state if convolution outputs are not ready
          begin
            next_state_1 = start_relu;
          end
          else 
            begin
              next_state_1 = start_relu;
            end
        end
            
      stop_relu: begin // disable relu controls and enable max_pooling output
        enable_maxpooling = 1;
        next_state_1 = generate_output;
      end

      generate_output: begin // max_pooling output ready and write to output SRAM
        next_state_1 = write_to_sram;
        write_to_sram_flag = 1;
      end

      write_to_sram: begin // write to output SRAM
        next_state_1 = start_relu;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!reset_b)
      current_state_1 <= start_relu;
    else
      current_state_1 <= next_state_1;
  end

  always @(posedge clk) begin
    if(current_state == Idle || current_state == delay_state_5)
      reset_flag_set <= 0;
    if(current_state == 0)
      begin
        input_sram_read_address <= 0;
        col_number_tracker <= 1;
        traversal_row_number <= 1;
        row_number_tracker <= 1;
        new_matrix_flag <= 0; 
        address_reference_for_right_shifting <= 1;
        row_number <= 1;
      end
    else if(enable_reading_N)
      begin
        N_value <= input_sram_read_data[7:0];
        input_sram_read_address <= input_sram_read_address + 1;
        if(input_sram_read_data[15:0] == 16'hffff)
          reset_flag_set <= 1;
        if(input_sram_read_data[7:0] != 7'h7f)
          new_matrix_flag <= 0;
      end
    else if(enable_reading_input_matrix)
      begin
        if (alternate_reg_storage) begin
          input_temp_reg_1 <= input_sram_read_data[15:8];
          input_temp_reg_2 <= input_sram_read_data[7:0];
          input_temp_reg_4 <= input_sram_read_data[7:0];
          traversal_row_number <= traversal_row_number + 1;
          if(traversal_row_number != 3)
            input_sram_read_address <= input_sram_read_address + (N_value/2 - 1);
          else 
            begin
              traversal_row_number <= 1;
               if(col_number_tracker == (N_value/2 - 1) && row_number_tracker % 2 == 0) // traversing below after reaching end of row
                begin
                  if(row_number + 1 == N_value/2) // traversing to new matrix after reaching end of matrix
                    begin
                      input_sram_read_address <= input_sram_read_address + 1;
                      new_matrix_flag <= 1;
                      col_number_tracker <= 1;
                      address_reference_for_right_shifting <= input_sram_read_address + 2;
                      row_number <= 1;
                      row_number_tracker <= 1;
                    end
                  else // traversing to the beginning of the new row if matrix is not ended
                    begin
                      address_reference_for_right_shifting <= input_sram_read_address - (N_value - 1);
                      col_number_tracker <= 1;
                      row_number <= row_number + 1;
                      input_sram_read_address <= input_sram_read_address - (N_value - 1);
                      row_number_tracker <= 1;
                    end
                end
              else if(row_number_tracker % 2 == 0) //traversing right shift upwards
                begin
                  col_number_tracker <= col_number_tracker + 1;
                  address_reference_for_right_shifting <= address_reference_for_right_shifting + 1;
                  input_sram_read_address <= address_reference_for_right_shifting + 1;
                  row_number_tracker <= 1;
                end
              else //after completing one 3*3 matrix traverse down
                begin
                  row_number_tracker <= row_number_tracker + 1;
                  input_sram_read_address <= input_sram_read_address - (N_value/2 + 1); 
                end
            end
        end
        else begin
          input_temp_reg_3 <= input_sram_read_data[15:8];
          input_temp_reg_5 <= input_sram_read_data[15:8];
          input_temp_reg_6 <= input_sram_read_data[7:0];
          input_sram_read_address <= input_sram_read_address + 1;
        end
      end
  end

  always @(posedge clk) begin
    if(current_state == Idle)
      begin
        accum1 <= 0;
        accum2 <= 0;
      end
    else if(enable_accumulating)
      begin
        accum1 <= accum1 + (input_temp_reg_1 * kernel_reg_1) + (input_temp_reg_2 * kernel_reg_2) + (input_temp_reg_3 * kernel_reg_3); //accumulate all 3 conv values
        accum2 <= accum2 + (input_temp_reg_4 * kernel_reg_1) + (input_temp_reg_5 * kernel_reg_2) + (input_temp_reg_6 * kernel_reg_3); //accumulate all 3 conv values
      end
    else
      begin
        if(traversal_row_number == 2)
          begin
            accum1 <= 0;
            accum2 <= 0;
            relu_input_1 <= accum1;
            relu_input_2 <= accum2;
            kernel_reg_1 <= kernel_matrix_0;
            kernel_reg_2 <= kernel_matrix_1;
            kernel_reg_3 <= kernel_matrix_2;
          end
        else if(traversal_row_number == 3)
          begin
            kernel_reg_1 <= kernel_matrix_3;
            kernel_reg_2 <= kernel_matrix_4;
            kernel_reg_3 <= kernel_matrix_5;
          end
        else
          begin
            kernel_reg_1 <= kernel_matrix_6;
            kernel_reg_2 <= kernel_matrix_7;
            kernel_reg_3 <= kernel_matrix_8;
          end
      end
  end

  always @(posedge clk) begin
    begin
      if(enable_relu) //perform relu 
        begin
          if(relu_input_1 < 0)
            relu_output_1 <= 0;
          else if(relu_input_1 > 127)
            relu_output_1 <= 127;
          else
            relu_output_1 <= relu_input_1;
        end
      else
        relu_output_1 <= relu_output_1;
    end
  end

  always @(posedge clk)
    begin
      if(enable_relu)
        begin
          if(relu_input_2 < 0)
            relu_output_2 <= 0;
          else if(relu_input_2 > 127)
            relu_output_2 <= 127;
          else
            relu_output_2 <= relu_input_2;
        end
      else  
        relu_output_2 <= relu_output_2;
    end

  always @(posedge clk) 
    begin
      if(current_state == Idle)
        begin
          max_pooling_output_flag <= 0;
          write_to_higher_bits_flag <= 1;
          max_pooling_output <= 0;
          accumulate_to_write_to_sram <= 0;
          write_to_higher_bits_counter <= 0;
        end
      else if(enable_maxpooling)
        begin
        if(max_pooling_output_flag)
          begin
            max_pooling_reg_1 <= (relu_output_1 > relu_output_2)? relu_output_1: relu_output_2; //store max pool output
            if(row_number == (N_value/2-1) && col_number_tracker == (N_value/2-1))
            begin
              append_zero_flag <= 1;
              if(reset_flag_set)
                begin
                  max_pooling_reg_2 <= 1'bx;
                  accumulate_to_write_to_sram <= 1;
                  max_pooling_output_flag <= 1;
                end
            end
          end
        else
          begin
            max_pooling_reg_2 <= (relu_output_1 > relu_output_2)? relu_output_1: relu_output_2;
            accumulate_to_write_to_sram <= 1;
          end
      end

      if(current_state_1 == generate_output)
        max_pooling_output_flag <= ~max_pooling_output_flag;
  
      if(accumulate_to_write_to_sram)
        begin
          accumulate_to_write_to_sram <= 0;
          if(write_to_higher_bits_flag)
            begin
              max_pooling_output[7:0] <= (max_pooling_reg_1 > max_pooling_reg_2)? max_pooling_reg_1: max_pooling_reg_2; //write to output_sram_reg output lower byte
              write_to_higher_bits_flag <= 0;
              if(write_to_higher_bits_counter > 1)
                output_sram_write_enable_flag <= 1;
            end
          else 
            begin
              write_to_higher_bits_flag <= 1;
              max_pooling_output[15:8] <= (max_pooling_reg_1 > max_pooling_reg_2)? max_pooling_reg_1: max_pooling_reg_2; //write to output_sram_reg output higher byte
              if(append_zero_flag)
                begin
                  max_pooling_output[7:0] <= 0;
                  append_zero_flag <= 0;
                  output_sram_write_enable_flag <= 1;
                  write_to_higher_bits_flag <= 0;
                end
            end
        end

      if(current_state_1 == write_to_sram)
        write_to_higher_bits_counter <= write_to_higher_bits_counter + 1; 
      
      if(current_state_1 == start_relu)
        output_sram_write_enable_flag <= 0;
  end

  
  always @(posedge clk)
    begin
      if(current_state_1 == start_relu && traversal_row_number == 1)
        output_sram_write_enable <= 0;

      if(output_sram_write_enable_flag) // writing to output SRAM
        begin
          output_sram_write_enable <= 1;
          output_sram_write_data <= max_pooling_output;
          increment_address_flag <= 1;
        end

      if(current_state == Idle && dut_run)
        output_sram_write_addresss <= 0;
      else if(increment_address_flag)
        begin
          increment_address_flag <= 0;
          output_sram_write_addresss <= output_sram_write_addresss + 1;
        end
    end

  always @(posedge clk) begin
    if(current_state == Idle)
      begin
        kernel_matrix_read <= 0;
        weights_sram_read_address <= 0;
      end
    else if(reset_b && kernel_matrix_read) //read kernel matrix data
      begin
        if(weights_sram_read_address == 1)
          begin
            kernel_matrix_0 <= weights_sram_read_data[15:8];
            kernel_matrix_1 <= weights_sram_read_data[7:0];
          end
        else if(weights_sram_read_address == 2)
          begin
            kernel_matrix_2 <= weights_sram_read_data[15:8];
            kernel_matrix_3 <= weights_sram_read_data[7:0];
          end
        else if(weights_sram_read_address == 3)
          begin
            kernel_matrix_4 <= weights_sram_read_data[15:8];
            kernel_matrix_5 <= weights_sram_read_data[7:0];
          end
        else if(weights_sram_read_address == 4)
          begin
            kernel_matrix_6 <= weights_sram_read_data[15:8];
            kernel_matrix_7 <= weights_sram_read_data[7:0];
          end
        else if(weights_sram_read_address == 5)
          begin
            kernel_matrix_8 <= weights_sram_read_data[15:8];
            kernel_matrix_read <= 0;
          end
        weights_sram_read_address <= weights_sram_read_address + 1;
      end  

    if(!new_matrix_flag)
      kernel_matrix_read <= 1;
    else
      kernel_matrix_read <= 0;
  end

endmodule
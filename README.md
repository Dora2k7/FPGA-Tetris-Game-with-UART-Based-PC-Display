# Tetris Game on FPGA with UART Display

A Verilog FPGA Tetris game that sends the game screen through UART for display on a computer.

## Project contents

- `src/`: FPGA/Verilog source files and timing/pin constraints
- `display_test/`: UART display test project and Python viewer
- `fpga_project_display.gprj`: Gowin project file

## Display viewer

Run the Python viewer from `display_test/` and select the UART COM port configured for the FPGA board.

## Hardware

- FPGA development board
- UART connection to the host computer
- Display controlled by the FPGA design

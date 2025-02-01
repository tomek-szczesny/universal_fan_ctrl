# universal_fan_ctrl

An autonomous, temperature dependent fan controller

This is WIP. 



The aim of the project is to develop a fan controller module that can be applied to fans in existing appliances that otherwise have no speed control. The module is intended to be connected as a pass-through between the fan and whatever it was originally plugged into.


![2025-02-02-003017_807x529_scrot](https://github.com/user-attachments/assets/88d7b9f9-6a8a-42d4-b452-c5b36f362c51)
![2025-02-02-003036_731x624_scrot](https://github.com/user-attachments/assets/22416faa-c719-4213-be94-a455bff83020)


Features:

- 5V - 24V input voltage range

- Low side PWM switch controls any DC fan, with of without PWM pin

- About 12x13mm 2-layer PCB, no bottom side components

- Cheap BOM

- BOM-configurable parameters

- On-board or remote temperature sensor (DS18B20)

- 2.54mm pitch input and output THT pads for wires or connectors



## Configuration

The microcontroller senses two ADC values on startup, which determine mode of operation. They can be easily changed by replacing two resistors on board.

### Maximum temperature

The temperature at which the fan works at the maximum speed. Resistor Rmt controls this parameter.

| Max Temperature | Rmt value  |
| --------------- | ---------- |
| 30C             | Open       |
| 35C             | 68k        |
| 40C             | 33k        |
| 45C             | 20k        |
| 50C             | 12k        |
| 55C             | 6k8        |
| 60C             | 3k6        |
| 65C             | 1k or less |

### Ramp length

The temperature range within which the PWM signal is generated proportionally. This parameter is controlled by resistor Rtr.

| Ramp Length | Rtr value   |
| ----------- | ----------- |
| 5C          | Open        |
| 10C         | 33k         |
| 15C         | 12k         |
| 20C         | 2k7 or less |

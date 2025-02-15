# universal_fan_ctrl

An autonomous, temperature dependent fan controller

This is WIP. 



The aim of the project is to develop a fan controller module that can be applied to fans in existing appliances that otherwise have no speed control. The module is intended to be connected as a pass-through between the fan and whatever it was originally plugged into.


![2025-02-02-003017_807x529_scrot](https://github.com/user-attachments/assets/88d7b9f9-6a8a-42d4-b452-c5b36f362c51)
![2025-02-02-003036_731x624_scrot](https://github.com/user-attachments/assets/22416faa-c719-4213-be94-a455bff83020)


## Features

- 4.5V - 30V input voltage range
- Low side PWM switch controls any DC fan, with of without PWM pin
- 1A PWM switch
- 11.6 x 13.6 mm 2-layer PCB, no bottom side components
- Cheap BOM
- BOM-configurable parameters
- 2.54mm pitch input and output THT pads for wires or connectors
- On-board or remote temperature sensor (DS18B20), or AVR internal temp sensor

## Operation

- PWM fixed at ~100Hz
- In absence of DS18B20 temperature sensor, falls back to the internal AVR sensor
- Temperature probed at ~5Hz
- Digital low pass filter enahnces temperature measurement quality
- Configurable Maximum temperature (MT) and Temperature ramp length (TR)
  -   Fan stays off at T < (MT - TR)
  -   Fan's PWM is mapped to (25% - 100%) range within (MT-TR) < T < MT range
  -   Fan stays fully on at T > MT


## Schematic
![obraz](https://github.com/user-attachments/assets/9a808cd9-04ca-48b6-adaf-94e8674297b2)


## Configuration

The microcontroller senses two ADC values on startup, which determine mode of operation. They can be easily changed by replacing two resistors on board.

### Maximum temperature (MT)

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

### Ramp length (TR)

The temperature range that is mapped linearly to 25% - 100% PWM output This parameter is controlled by resistor Rtr.

| Ramp Length | Rtr value   |
| ----------- | ----------- |
| 2.5C        | Open        |
| 5C          | 33k         |
| 10C         | 12k         |
| 20C         | 2k7 or less |

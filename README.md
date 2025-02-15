# universal_fan_ctrl

An autonomous, temperature dependent fan controller

The aim of the project is to develop a fan controller module that can be applied to fans in existing appliances that otherwise have no speed control. The module is intended to be connected as a pass-through between the fan and its original power source.

![2025-02-15-212940_507x466_scrot](https://github.com/user-attachments/assets/fdbef686-8e25-4c24-93b2-18126f05e1e9)
![2025-02-15-212955_443x396_scrot](https://github.com/user-attachments/assets/53955208-b904-4a1b-bdb2-2d52df2c16a6)


## Features

- 4.5V - 30V input voltage range
- Low side 1A PWM switch controls any DC fan, with of without PWM pin
- 11.6 x 13.6 mm 2-layer PCB, no bottom side components
- Cheap BOM with hand-solderable 0603 passives
- BOM-configurable parameters
- 2.54mm pitch input and output THT pads for wires or connectors
- On-board or remote temperature sensor (DS18B20), or AVR internal sensor

## Operation

- PWM fixed at 100Hz
- In absence of DS18B20 temperature sensor, falls back to the internal AVR sensor
- Temperature probed at 5Hz
- Digital low pass filters reduce measurement noise
- Configurable Maximum temperature (MT) and Temperature ramp length (TR)
  -   Fan stays off at T < (MT-TR)
  -   Fan's PWM is mapped to (23.2% - 100%) range within (MT-TR) < T < MT range
  -   Fan stays fully on at T > MT

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

The temperature range that is mapped linearly to 23.2% - 100% PWM output This parameter is controlled by resistor Rtr.

| Ramp Length | Rtr value   |
| ----------- | ----------- |
| 2.5C        | Open        |
| 5C          | 33k         |
| 10C         | 12k         |
| 20C         | 2k7 or less |

## Schematic
![2025-02-15-213155_895x945_scrot](https://github.com/user-attachments/assets/1c5f35a5-b682-40d6-8058-b1494befdc60)

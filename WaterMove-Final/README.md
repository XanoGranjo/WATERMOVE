
# WaterMotion

- **Arduino** lê joystick + botões (RGB) e controla 2 motores (vibração).
- **Processing** recebe os dados via Serial, faz smoothing do joystick, passa os estados RGB para o shader e desenha o vídeo (câmara iPhone/Continuity) com efeito.
- **Shader (GLSL)** calcula motion entre frames e aplica uma **onda** (displacement) centrada na posição do joystick, com **tints** RGB quando os botões estão ativos.

## Estrutura

```
WaterMotion.pde
CodigoArduino/
	CodigoArduino.ino
data/
	ShaderMotion.glsl
```

## Protocolo Serial (Arduino -> Processing)

O Arduino envia a cada ciclo uma linha CSV:

```
joyX,joyY,r,g,b\n
```

- `joyX`, `joyY`: 0..1023 (leituras analógicas do joystick)
- `r`, `g`, `b`: `0` ou `1` (estados toggle dos botões)

Exemplo:

```
512,512,1,0,0
```

## Documentação por ficheiro

### `CodigoArduino/CodigoArduino.ino`

#### O que faz

- Lê:
	- Joystick: `joyX = A1`, `joyY = A0`
	- Botões: `btnR = 11`, `btnG = 12`, `btnB = 2` (com `INPUT_PULLUP`)
- Controla:
	- LEDs RGB (um ânodo comum e um cátodo comum)
	- Motores: `motorESQ = 3`, `motorDIR = 4`
- Comunica com Processing:
	- Envia `joyX,joyY,r,g,b` por Serial a `9600`

#### LEDs

- LED1 (ânodo comum): lógica inversa (LOW liga / HIGH desliga)
- LED2 (cátodo comum): lógica direta (HIGH liga / LOW desliga)

#### Motores (lógica de vibração)

- Existe um estado `motoresArmados`:
	- Antes de armar: vibração mínima constante (`MOTOR_MIN_PWM`)
	- Arma ao clicar num botão (R/G/B) **ou** ao mexer o joystick acima de `JOY_ARM_THRESHOLD`
- Depois de armar:
	- No centro (≈ 512,512): ambos os motores vibram com intensidade igual (`MOTOR_MIN_PWM`)
	- A intensidade aumenta com a distância ao centro (magnitude do joystick)
	- Há compensação em marcha‑atrás para a geometria (motor direito mais atrás) via `REVERSE_SIDE_BOOST`
	- Em marcha‑atrás a direção esquerda/direita é invertida (troca qual motor responde)
- “Topo” (perto de 0,0): override para ambos vibrarem iguais mas mais fracos (`MOTOR_TOP_PWM`)

#### PWM por software

Para manter o controlo de intensidade mesmo em pinos sem PWM (ex.: pin 4 em UNO/Nano), o sketch usa PWM por software com período `SOFT_PWM_PERIOD_MS` para **ambos** os motores.

#### Parâmetros principais (tuning)

- `MOTOR_MIN_PWM`: intensidade base (centro e pré‑arming)
- `JOY_DEADZONE`: zona morta do joystick
- `JOY_ARM_THRESHOLD`: quanto é preciso mexer para armar
- `REVERSE_SIDE_BOOST`: boost extra quando está para trás e a virar
- `JOY_TOP_THRESHOLD` e `MOTOR_TOP_PWM`: comportamento no topo (0,0)

---

### `WaterMotion.pde` (Processing)

#### O que faz

- Inicializa captura de vídeo (`processing.video.Capture`) com resolução `camW x camH`
- Carrega o shader `data/ShaderMotion.glsl`
- Faz “double buffering” com `PGraphics pgA/pgB` para ter `u_curr` e `u_prev`
- Lê Serial do Arduino (se existir uma porta `usbmodem`/`usbserial`)
- Faz smoothing do joystick (`lerp`) para evitar tremor

#### Entrada do Arduino

- `serialEvent()` lê uma linha CSV e atualiza:
	- `joyX`, `joyY`
	- `r`, `g`, `b` (interpretados como 0/1)

#### Uniforms enviados ao shader

- `u_curr` / `u_prev`: texturas com frame atual e anterior
- `u_time`: tempo em segundos (`millis() * 0.001`)
- `u_resolution`: `width`, `height`
- `u_joyPos`: joystick normalizado para 0..1 (com deadzone)
- `u_red`, `u_green`, `u_blue`: flags 0/1 vindas do Arduino
- `u_saturation`: valor fixo (ex.: `3.0`)

#### Parâmetros principais (tuning)

- `JOY_DEADZONE`: deadzone no Processing (independente do Arduino)
- `JOY_SMOOTH`: smoothing do joystick (`0..1`, maior responde mais rápido)
- `JOY_INVERT_X`, `JOY_INVERT_Y`: inverte eixos (útil se “para a frente” estiver ao contrário)
- `camW`, `camH`: resolução da captura

---

### `data/ShaderMotion.glsl`

#### O que faz

1. **Motion**: compara `u_curr` e `u_prev` para estimar movimento (diferença de luminância) e cria uma máscara `motion`.
2. **Wave / displacement**: cria uma onda baseada na distância ao `u_joyPos`, com máscara mais forte perto do joystick.
3. **Cor**:
	 - Aumenta saturação (`u_saturation`)
	 - Aplica tint RGB quando `u_red/u_green/u_blue` estão ativos (faz média se houver mais do que um)

#### Uniforms

- `u_curr`, `u_prev` (sampler2D)
- `u_resolution` (vec2)
- `u_time` (float)
- `u_saturation` (float)
- `u_joyPos` (vec2)
- `u_red`, `u_green`, `u_blue` (int)

#### Onde afinar a onda

Os parâmetros de “onda” estão na secção `WAVE EFFECT`:

- `dist * ...`: frequência espacial (mais alto = mais ripples)
- `u_time * ...`: velocidade (mais alto = mexe mais rápido)
- amplitude `* 0.xxx`: intensidade do displacement
- `intensity = (1.0 + motion * ...) * mask`: quanto o motion amplifica a onda

#### Onde afinar os tints

- Cores base: `redTint`, `greenTint`, `blueTint`
- Força do tint: `tintStrength` (ex.: `0.30`)

## Troubleshooting rápido

- **Sem Serial**: o Processing só liga a portas com `usbmodem`/`usbserial` (para não apanhar Bluetooth). Confirma no console o nome da porta.
- **Tints não mudam**: verifica se a linha Serial chega como `...,0,1,0` (0/1). Se vier `true/false`, o parsing também aceita.
- **Câmara não aparece**: no macOS, concede permissões e liga o iPhone como “Câmara de Continuidade”. O sketch tenta reconectar automaticamente.


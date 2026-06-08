//Pinos LED 1
const int LED1_R = 10;
const int LED1_G = 9;
const int LED1_B = 8;

//Pinos LED 2 
const int LED2_R = 5;
const int LED2_G = 6;
const int LED2_B = 7;

// --- Pinos dos Botões ---
const int btnR = 11;
const int btnG = 12;
const int btnB = 2;

// --- Pinos dos Motores ---
const int motorESQ = 3;
const int motorDIR = 4;

const int LED_DEBUG = 13;

// --- Pinos do Joystick ---
const int joyX = A1; 
const int joyY = A0; 

// --- Motores: estado/controlo ---
bool motoresArmados = false; // só liga conforme joystick depois da 1ª interação

// Vibração mínima ao arrancar (0..255)
const uint8_t MOTOR_MIN_PWM = 25; 

// Joystick
const int JOY_CENTER = 512;
const int JOY_DEADZONE = 60;
const int JOY_ARM_THRESHOLD = 120;
const int JOY_TOP_THRESHOLD = 40;   
const uint8_t MOTOR_TOP_PWM = 80; 

// Orientação do joystick (ajusta conforme montagem)
// Se estiveres a ver esquerda/direita trocados, mantém JOY_INVERT_X = true.
const bool JOY_SWAP_XY = false;   // true se X/Y estiverem trocados fisicamente
const bool JOY_INVERT_X = true;   // true se esquerda/direita estiverem invertidos
const bool JOY_INVERT_Y = false;  // true se cima/baixo estiverem invertidos

const uint16_t SOFT_PWM_PERIOD_MS = 20;
uint8_t motorEsqTargetPwm = 0;
uint8_t motorDirTargetPwm = 0;

// Compensação: como o motor direito está mais atrás, quando estiveres a puxar
// para TRÁS e a virar, reforça o motor do lado da curva.
// (trás+direita => direito mais forte; trás+esquerda => esquerdo mais forte)
const float REVERSE_SIDE_BOOST = 0.25f; // até +25% no máximo da viragem

// --- Variáveis de Estado (false = desligado, true = ligado) ---
bool estadoR = false;
bool estadoG = false;
bool estadoB = false;

// --- Variáveis para Detetar o Clique ---
bool ultimoBtnR = HIGH;
bool ultimoBtnG = HIGH;
bool ultimoBtnB = HIGH;

bool pessoaDetectada = false;

char rxLine[16];
uint8_t rxPos = 0;

void setup() {
  Serial.begin(9600);
  

  pinMode(LED_DEBUG, OUTPUT);
  digitalWrite(LED_DEBUG, LOW);

  // Configuração dos LEDs
  pinMode(LED1_R, OUTPUT); pinMode(LED1_G, OUTPUT); pinMode(LED1_B, OUTPUT);
  pinMode(LED2_R, OUTPUT); pinMode(LED2_G, OUTPUT); pinMode(LED2_B, OUTPUT);
  
  // Configuração dos Motores
  pinMode(motorESQ, OUTPUT);
  pinMode(motorDIR, OUTPUT);
  
  // Configuração dos Botões
  pinMode(btnR, INPUT_PULLUP);
  pinMode(btnG, INPUT_PULLUP);
  pinMode(btnB, INPUT_PULLUP);

  // Configuração do Joystick
  pinMode(joyX, INPUT);
  pinMode(joyY, INPUT);
  
  // Inicialização: Tudo desligado
  digitalWrite(LED1_R, HIGH); digitalWrite(LED1_G, HIGH); digitalWrite(LED1_B, HIGH);
  digitalWrite(LED2_R, LOW);  digitalWrite(LED2_G, LOW);  digitalWrite(LED2_B, LOW);
}

void updateMotorEsqSoftPwm() {
  if (motorEsqTargetPwm == 0) {
    digitalWrite(motorESQ, LOW);
    return;
  }
  if (motorEsqTargetPwm >= 255) {
    digitalWrite(motorESQ, HIGH);
    return;
  }
  uint16_t phase = (uint16_t)(millis() % SOFT_PWM_PERIOD_MS);
  uint16_t onTime = (uint16_t)((uint32_t)SOFT_PWM_PERIOD_MS * (uint32_t)motorEsqTargetPwm / 255UL);
  digitalWrite(motorESQ, (phase < onTime) ? HIGH : LOW);
}

void updateMotorDirSoftPwm() {
  if (motorDirTargetPwm == 0) {
    digitalWrite(motorDIR, LOW);
    return;
  }
  if (motorDirTargetPwm >= 255) {
    digitalWrite(motorDIR, HIGH);
    return;
  }
  uint16_t phase = (uint16_t)(millis() % SOFT_PWM_PERIOD_MS);
  uint16_t onTime = (uint16_t)((uint32_t)SOFT_PWM_PERIOD_MS * (uint32_t)motorDirTargetPwm / 255UL);
  digitalWrite(motorDIR, (phase < onTime) ? HIGH : LOW);
}

void setMotors(uint8_t pwmEsq, uint8_t pwmDir) {
  motorEsqTargetPwm = pwmEsq;
  motorDirTargetPwm = pwmDir;
  updateMotorEsqSoftPwm();
  updateMotorDirSoftPwm();
}

void loop() {

  // ==========================
// RECEBER DADOS DO PROCESSING
// ==========================
while (Serial.available() > 0) {
  char c = (char)Serial.read();
  if (c == '\r') continue;
  if (c == '\n') {
    rxLine[rxPos] = '\0';
    if (rxPos > 0) {
      if (strcmp(rxLine, "1") == 0) pessoaDetectada = true;
      else if (strcmp(rxLine, "0") == 0) pessoaDetectada = false;
    }
    rxPos = 0;
  } else {
    if (rxPos < sizeof(rxLine) - 1) {
      rxLine[rxPos++] = c;
    }
  }
}

digitalWrite(LED_DEBUG, pessoaDetectada ? HIGH : LOW);
  
  // Verifica se o botão foi premido (passagem de HIGH para LOW)
  bool leituraR = digitalRead(btnR);
  if (leituraR == LOW && ultimoBtnR == HIGH) {
    estadoR = !estadoR;
    motoresArmados = true;
    delay(50);
  }
  ultimoBtnR = leituraR;

  bool leituraG = digitalRead(btnG);
  if (leituraG == LOW && ultimoBtnG == HIGH) {
    estadoG = !estadoG;
    motoresArmados = true;
    delay(50);
  }
  ultimoBtnG = leituraG;

  bool leituraB = digitalRead(btnB);
  if (leituraB == LOW && ultimoBtnB == HIGH) {
    estadoB = !estadoB;
    motoresArmados = true;
    delay(50);
  }
  ultimoBtnB = leituraB;

  // ATUALIZAR LED 1
  digitalWrite(LED1_R, estadoR ? LOW : HIGH);
  digitalWrite(LED1_G, estadoG ? LOW : HIGH);
  digitalWrite(LED1_B, estadoB ? LOW : HIGH);

  // ATUALIZAR LED 2
  digitalWrite(LED2_R, estadoR ? HIGH : LOW);
  digitalWrite(LED2_G, estadoG ? HIGH : LOW);
  digitalWrite(LED2_B, estadoB ? HIGH : LOW);

// ==========================
// CONTROLO DOS MOTORES
// ==========================
int xRaw = analogRead(joyX);
int yRaw = analogRead(joyY);

int xValue = JOY_SWAP_XY ? yRaw : xRaw;
int yValue = JOY_SWAP_XY ? xRaw : yRaw;

if (!motoresArmados) {
  if (abs(xValue - JOY_CENTER) > JOY_ARM_THRESHOLD || abs(yValue - JOY_CENTER) > JOY_ARM_THRESHOLD) {
    motoresArmados = true;
  }
}

// Atualizar motores
if (!motoresArmados) {
  setMotors(MOTOR_MIN_PWM, MOTOR_MIN_PWM);
} else {
  // Mapeamento por quadrantes/diagonais:
  // - cima+esquerda OU baixo+esquerda => liga SÓ o motor esquerdo
  // - cima+direita OU baixo+direita   => liga SÓ o motor direito
  // Fora das diagonais, mantém vibração mínima nos dois motores.
  int dx = xValue - JOY_CENTER;
  int dy = yValue - JOY_CENTER;
  if (abs(dx) < JOY_DEADZONE) dx = 0;
  if (abs(dy) < JOY_DEADZONE) dy = 0;

  if (JOY_INVERT_X) dx = -dx;
  if (JOY_INVERT_Y) dy = -dy;

  if (dx != 0 && dy != 0) {
    float fx = (float)dx / 511.0f;
    float fy = (float)dy / 511.0f;
    float mag = sqrt(fx * fx + fy * fy);
    if (mag > 1.0f) mag = 1.0f;

    float pwmF = (float)MOTOR_MIN_PWM + (255.0f - (float)MOTOR_MIN_PWM) * mag;
    if (pwmF < 0.0f) pwmF = 0.0f;
    if (pwmF > 255.0f) pwmF = 255.0f;
    uint8_t pwm = (uint8_t)(pwmF + 0.5f);

    if (dx < 0) setMotors(pwm, 0);
    else setMotors(0, pwm);
  } else {
    setMotors(MOTOR_MIN_PWM, MOTOR_MIN_PWM);
  }
}

updateMotorEsqSoftPwm();
updateMotorDirSoftPwm();

  // ENVIO DE DADOS PARA PROCESSING
  Serial.print(xValue); Serial.print(",");
  Serial.print(yValue); Serial.print(",");
  Serial.print(estadoR ? 1 : 0); Serial.print(",");
  Serial.print(estadoG ? 1 : 0); Serial.print(",");
  Serial.println(estadoB ? 1 : 0);

  delay(10);
}
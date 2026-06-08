import processing.video.*;
import processing.serial.*;

PShader sh;

Capture cam;  
boolean firstFrameReady = false;

PGraphics pgA, pgB;
boolean flip = false;

// Startup / permissions handling (macOS camera permission can make Capture.list() return empty)
boolean initialized = false;
String initStatus = "";
int nextInitRetryMillis = 0;

// Window controls (macOS JOGL can deadlock on setResizable)
boolean attemptedResizable = false;

// ==========================
// ARDUINO
// ==========================
Serial myPort;
int joyX = 512, joyY = 512;
int r, g, b;
int lastSerialUpdateMillis = 0;

// Parse one CSV line from Arduino: x,y,r,g,b
void parseArduinoLine(String data) {
  if (data == null) return;
  data = trim(data);
  if (data.length() == 0) return;

  String[] vals = split(data, ',');
  if (vals.length < 5) return;

  try {
    joyX = int(trim(vals[0]));
    joyY = int(trim(vals[1]));
    r = parseBool01(vals[2]);
    g = parseBool01(vals[3]);
    b = parseBool01(vals[4]);
    lastSerialUpdateMillis = millis();
  } catch (Exception ignored) {
    // Ignore malformed lines.
  }
}

void pollSerial() {
  if (myPort == null) return;
  // Read all complete lines available (keeps input responsive even if serialEvent doesn't fire)
  while (myPort.available() > 0) {
    String line = myPort.readStringUntil('\n');
    if (line == null) break;
    parseArduinoLine(line);
  }
}

int parseBool01(String s) {
  if (s == null) return 0;
  s = trim(s);
  if (s.equals("1") || s.equalsIgnoreCase("true")) return 1;
  return 0;
}

// Joystick -> shader control
final float JOY_MIN = 0.0;
final float JOY_MAX = 1023.0;
final float JOY_CENTER = 512.0;
final float JOY_DEADZONE = 40.0;
final float JOY_SMOOTH = 0.18; // 0..1 (maior = responde mais rápido)
final boolean JOY_SWAP_AXES = true; // se frente/trás estiver a mexer na onda para a esquerda/direita
final boolean JOY_INVERT_X = false;
final boolean JOY_INVERT_Y = false; // "para a frente" deve subir no ecrã
float joyXSmooth = JOY_CENTER;
float joyYSmooth = JOY_CENTER;

int camW = 3840;
int camH = 2160;

int findCameraIndex(String[] cams, String needle) {
  if (cams == null || needle == null) return -1;
  String n = needle.toLowerCase();
  for (int i = 0; i < cams.length; i++) {
    if (cams[i] != null && cams[i].toLowerCase().indexOf(n) >= 0) return i;
  }
  return -1;
}

void setup() {
  size(3840, 2160, P2D);

  // ==========================
  // SERIAL (Arduino)
  // ==========================
  try {
    String[] ports = Serial.list();
    printArray(ports);
    if (ports != null && ports.length > 0) {
      int portIdx = -1;
      for (int i = 0; i < ports.length; i++) {
        String p = ports[i].toLowerCase();
        // Be permissive: different USB-serial chipsets show different names on macOS.
        if (p.indexOf("usbmodem") >= 0 ||
            p.indexOf("usbserial") >= 0 ||
            p.indexOf("wchusbserial") >= 0 ||
            p.indexOf("slab_usbto") >= 0 ||
            p.indexOf("cp210") >= 0 ||
            p.indexOf("usb_to_uart") >= 0 ||
            p.indexOf("arduino") >= 0 ||
            p.indexOf("ttyacm") >= 0 ||
            p.indexOf("ttyusb") >= 0) {
          portIdx = i;
          break;
        }
      }

      // Fallback seguro: se só existir 1 porta, é muito provavelmente o Arduino.
      if (portIdx < 0 && ports.length == 1) {
        portIdx = 0;
        println("Nenhuma porta típica detetada; a usar a única porta disponível: " + ports[portIdx]);
      }

      // Se não houver Arduino, NÃO ligar a uma porta aleatória
      if (portIdx < 0) {
        println("Nenhuma porta Arduino encontrada. Serial desativada.");
        println("Dica: confirma em Tools > Port (Arduino IDE) qual é a porta, e garante que aparece em Serial.list().");
        myPort = null;
      } else {
        myPort = new Serial(this, ports[portIdx], 9600);
        myPort.bufferUntil('\n');
        println("Serial ligada em: " + ports[portIdx]);
      }
    } else {
      println("Nenhuma porta serial encontrada. Arduino desligado?");
    }
  } catch (Exception e) {
    println("Falha ao abrir Serial: " + e.getMessage());
    myPort = null;
  }

  tryInitVideoPipeline();
}

void tryInitVideoPipeline() {
  if (initialized) return;

  String[] cameras = null;
  try {
    cameras = Capture.list();
  } catch (Exception e) {
    cameras = null;
  }

  if (cameras == null || cameras.length == 0) {
    initStatus = "Nenhuma câmara encontrada (ou permissão não concedida ainda).";
    println(initStatus);
    nextInitRetryMillis = millis() + 1000;
    return;
  }

  printArray(cameras);

  try {
    // Apenas 1 câmara: usar iPhone/Continuity; NÃO fazer fallback para outra.
    int camIdx = findCameraIndex(cameras, "iPhone");
    if (camIdx < 0) camIdx = findCameraIndex(cameras, "Continuity");
    if (camIdx < 0) camIdx = findCameraIndex(cameras, "iOS");
    if (camIdx < 0) {
      initStatus = "iPhone/Continuity não encontrado. Liga o iPhone (Câmara de Continuidade) e tenta novamente.";
      println(initStatus);
      nextInitRetryMillis = millis() + 1000;
      return;
    }

    println("Cam (shader): " + cameras[camIdx]);

    cam = new Capture(this, camW, camH, cameras[camIdx]);
    cam.start();

    sh = loadShader("ShaderMotion.glsl");
    pgA = createGraphics(camW, camH, P2D);
    pgB = createGraphics(camW, camH, P2D);

    firstFrameReady = false;

    initialized = true;
    initStatus = "OK";
    println("Pipeline de vídeo inicializado.");
  } catch (Exception e) {
    initStatus = "Falha ao iniciar câmaras/shader: " + e.getMessage();
    println(initStatus);

    // Clean partial init so we can retry cleanly.
    try {
      if (cam != null) cam.stop();
    } catch (Exception ignored) {
    }
    cam = null;
    sh = null;
    pgA = null;
    pgB = null;

    nextInitRetryMillis = millis() + 1000;
  }
}

void draw() {

  // Keep joystick/colors updated from Arduino.
  pollSerial();

  if (!initialized) {
    if (millis() >= nextInitRetryMillis) {
      tryInitVideoPipeline();
    }
    background(0);
    fill(255);
    textAlign(CENTER, CENTER);
    text("A aguardar câmara / permissões…\n" + initStatus, width/2.0, height/2.0);
    return;
  }
  if (!attemptedResizable && frameCount > 10) {
    attemptedResizable = true;
    try {
      surface.setResizable(true);
    } catch (Exception e) {
      println("Aviso: não foi possível ativar janela redimensionável (JOGL): " + e.getMessage());
    }
  }

  joyXSmooth = lerp(joyXSmooth, joyX, JOY_SMOOTH);
  joyYSmooth = lerp(joyYSmooth, joyY, JOY_SMOOTH);

  // ==========================
  // PROCESSAMENTO DO SHADER
  // ==========================
  if (cam != null) {
    if (cam.available()) {
      try {
        cam.read();
      } catch (Exception e) {
        // Ignora frames corrompidos/desligar de câmara
      }
    }
    
    if (cam.width > 0) {
      flip = !flip;
      PGraphics currBuffer = flip ? pgA : pgB;
      currBuffer.beginDraw();
      currBuffer.image(cam, 0, 0, camW, camH);
      currBuffer.endDraw();

      // Na primeira frame, inicializar ambos os buffers para evitar "prev" vazio.
      if (!firstFrameReady) {
        PGraphics otherBuffer = flip ? pgB : pgA;
        otherBuffer.beginDraw();
        otherBuffer.image(cam, 0, 0, camW, camH);
        otherBuffer.endDraw();
        firstFrameReady = true;
      }
    }
  }

  PGraphics curr = flip ? pgA : pgB;
  PGraphics prev = flip ? pgB : pgA;

  sh.set("u_curr", curr);
  sh.set("u_prev", prev);
  sh.set("u_time", millis() * 0.001);
  sh.set("u_resolution", (float)width, (float)height);

  float jx = joyXSmooth;
  float jy = joyYSmooth;
  if (JOY_SWAP_AXES) {
    float tmp = jx;
    jx = jy;
    jy = tmp;
  }
  if (abs(jx - JOY_CENTER) < JOY_DEADZONE) jx = JOY_CENTER;
  if (abs(jy - JOY_CENTER) < JOY_DEADZONE) jy = JOY_CENTER;

  float joyXNorm = constrain(map(jx, JOY_MIN, JOY_MAX, 0, 1), 0, 1);
  float joyYNorm = constrain(map(jy, JOY_MIN, JOY_MAX, 0, 1), 0, 1);
  if (JOY_INVERT_X) joyXNorm = 1.0 - joyXNorm;
  if (JOY_INVERT_Y) joyYNorm = 1.0 - joyYNorm;

  // 0..1: distância ao centro (para controlar força da onda)
  float dx = abs(jx - JOY_CENTER) / (JOY_MAX - JOY_CENTER);
  float dy = abs(jy - JOY_CENTER) / (JOY_MAX - JOY_CENTER);
  float joyStrength = constrain(sqrt(dx*dx + dy*dy), 0, 1);

  sh.set("u_joyPos", joyXNorm, joyYNorm);
  sh.set("u_joyStrength", joyStrength);
  sh.set("u_red", r);
  sh.set("u_green", g);
  sh.set("u_blue", b);

  sh.set("u_saturation", 3.0);

  // Render direto no ecrã (evita recriar PGraphics durante resize, que pode bloquear no macOS/JOGL)
  background(0);
  shader(sh);
  noStroke();
  rect(0, 0, width, height);
  resetShader();
}

// ==========================
// ARDUINO
// ==========================
 void serialEvent(Serial myPort) {
   String data = myPort.readStringUntil('\n');
   parseArduinoLine(data);
 }

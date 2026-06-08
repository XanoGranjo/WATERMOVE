#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

varying vec4 vertTexCoord;

uniform sampler2D u_curr;
uniform sampler2D u_prev;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_saturation;
uniform vec2 u_joyPos; // Recebido do Processing
uniform float u_joyStrength; // 0..1: afastamento do centro

uniform int u_red;
uniform int u_green;
uniform int u_blue;

vec3 adjustSaturation(vec3 color, float saturation) {
    vec3 gray = vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
    return mix(gray, color, saturation);
}

void main() {
    vec2 uv = vertTexCoord.st;
    vec2 uvCam = vec2(uv.x, 1.0 - uv.y);
    float aspect = u_resolution.x / u_resolution.y;

    vec2 st = uvCam;
    st.x *= aspect;

    // --- MOTION ---
    vec3 currTex = texture2D(u_curr, uvCam).rgb;
    vec3 prevTex = texture2D(u_prev, uvCam).rgb;
    float motion = smoothstep(0.05, 0.25, abs(dot(currTex, vec3(0.299)) - dot(prevTex, vec3(0.299))));

    // --- WAVE EFFECT BASEADO NO JOYSTICK ---
    vec2 center = u_joyPos;
    center.x *= aspect;
    
    vec2 diff = st - center;
    float dist = length(diff);
    vec2 dir = normalize(diff + 0.0001);

    // Máscara: mais forte perto do joystick, mais fraco longe
    float mask = 1.0 - smoothstep(0.20, 0.95, dist);

    // Onda: sempre visível; joystick aumenta ainda mais a força
    float js = clamp(u_joyStrength, 0.0, 1.0);
    float amp = mix(0.045, 0.080, js);
    float wave = sin(dist * 30.0 - u_time * 4.5) * amp * mask;
    float intensity = (1.0 + motion * 3.2) * mask * mix(0.80, 1.00, js);

    vec2 displacedUV = uvCam + (dir / aspect) * wave * intensity;

    // --- CORES ---
        vec3 color = texture2D(u_curr, displacedUV).rgb;
        float satBoost = u_saturation;
        vec3 saturated = adjustSaturation(color, satBoost);
        vec3 redTint   = vec3(1.0, 0.2, 0.2);
        vec3 greenTint = vec3(0.2, 1.0, 0.2);
        vec3 blueTint  = vec3(0.2, 0.4, 1.0);

        vec3 mixTint = vec3(0.0);
        float count = 0.0;

        if (u_red == 1) {
            mixTint += redTint;
            count += 1.0;
        }

        if (u_green == 1) {
            mixTint += greenTint;
            count += 1.0;
        }

        if (u_blue == 1) {
            mixTint += blueTint;
            count += 1.0;
        }

        vec3 tint = vec3(1.0);

        if (count > 0.0) {
            tint = mixTint / count;
        }

        // intensidade do tint (leve e transparente)
        float tintStrength = 0.30;

        vec3 finalColor = mix(
            saturated,
            saturated * tint,
            tintStrength
        );

    gl_FragColor = vec4(finalColor, 1.0);
}

shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform sampler2D emis : source_color, filter_nearest;
uniform bool has_emis = false;
// Animated layer over the model, like Charizard's tail flame in Cobblemon: its frames side
// by side in one strip, played at flame_fps, glowing and drawn over the base (whose texture
// is empty there).
uniform sampler2D flame_tex : source_color, filter_nearest;
uniform bool has_flame = false;
uniform float flame_frames = 4.0;
uniform float flame_fps = 10.0;

// Material propio por Pokémon (no "instance uniform": así funciona igual en Compatibility/web).
uniform float flash = 0.0;   // destello blanco al recibir un golpe
uniform float glow = 0.0;    // brillo de la textura emisiva (mejillas)
uniform float fade = 1.0;    // 1 = entero, 0 = desaparecido (tramado)
uniform vec3 tint = vec3(0.0); // tinte aditivo (aviso de ataque)

void fragment() {
	vec4 c = texture(tex, UV);
	vec4 fl = vec4(0.0);
	if (has_flame) {
		float frame = floor(mod(TIME * flame_fps, flame_frames));
		fl = texture(flame_tex, vec2((UV.x + frame) / flame_frames, UV.y));
	}
	if (c.a < 0.5 && fl.a < 0.1) discard;
	if (fade < 1.0) {
		vec2 cel = floor(UV * vec2(128.0, 64.0));
		float n = fract(sin(dot(cel, vec2(12.9898, 78.233))) * 43758.5453);
		if (n > fade) discard;
	}
	ALBEDO = mix(c.rgb, vec3(1.0), flash);
	EMISSION = vec3(flash) * 0.8 + tint;
	if (fl.a >= 0.1) {
		ALBEDO = mix(ALBEDO, fl.rgb, fl.a);
		EMISSION += fl.rgb * 1.6;
	}
	if (has_emis) {
		vec4 e = texture(emis, UV);
		EMISSION += e.rgb * e.a * glow * 4.0;
	}
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}

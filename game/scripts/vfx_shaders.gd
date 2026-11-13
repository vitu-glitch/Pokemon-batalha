class_name VfxShaders
extends RefCounted
## Effect shaders (Forward+). They live in code so vfx.gd can build them with their
## parameters. All with HDR energy: the glow comes from there.

## Camera-facing particle with a frame strip (Cobblemon's textures).
## "add" adds light (sparks, fire); without it, normal blending (smoke, dust).
const PARTICLE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, %s;
uniform sampler2D tex : source_color, %s;
uniform float energy = 1.0;
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform float soft = 0.0;  // 1: soft edge even if the texture is hard
void vertex() {
	mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float r = INSTANCE_CUSTOM.x;
	m = m * mat4(vec4(cos(r), -sin(r), 0.0, 0.0), vec4(sin(r), cos(r), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float hf = float(h_frames);
	float vf = float(v_frames);
	float total = hf * vf;
	float f = mod(floor(INSTANCE_CUSTOM.z * total), total);
	UV /= vec2(hf, vf);
	UV += vec2(mod(f, hf) / hf, floor(f / hf) / vf);
}
void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	ALBEDO = c.rgb * energy;
	ALPHA = c.a;
}
"""

## Particle stretched in the direction it moves (sparks, drops, wind). %s: blend mode.
const STREAK := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, %s;
uniform float energy = 3.0;
void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
	vec3 side = normalize(cross(axis, to_cam));
	float stretch_len = length(MODEL_MATRIX[1].xyz);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 p = pos + side * VERTEX.x * width + axis * VERTEX.y * stretch_len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}
void fragment() {
	// Hard bands, no gradient: a light core, the color at the edge, and a tail one core wide.
	float d = abs(UV.x - 0.5) * 2.0;
	if (d > 0.85 || (UV.y > 0.7 && d > 0.4) || COLOR.a < 0.15) discard;
	ALBEDO = mix(COLOR.rgb, vec3(1.0), step(d, 0.4) * 0.45) * energy;
	ALPHA = COLOR.a > 0.55 ? 1.0 : 0.47;
}
"""

## Pixel impact flash: core, rays and ring in 24 × 24 cells, with two flat tones (white
## and the color) and hard edges, like Cobblemon's.
const FLASH := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 4.0;
uniform float t = 0.0;      // 0 to 1
uniform float bolts = 8.0;
uniform float seed = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = (floor(UV * 24.0) + 0.5) / 24.0 * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float tt = floor(t * 5.0) / 5.0;   // in steps, like a frame strip
	float core = step(r, 0.3 * (1.0 - tt));
	float ray = step(0.82, abs(sin(ang * bolts * 0.5 + seed))) * step(r, 0.95 - tt * 0.3) * step(tt, 0.7);
	float ring = step(abs(r - (0.25 + tt * 0.65)), 0.06) * step(tt, 0.85);
	float a = max(core, max(ray, ring));
	if (a < 0.5) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), max(core, ray * step(r, 0.45))) * 1.1;
}
"""

## Flat ring that spreads (shockwaves on the ground, Earthquake), in pixel cells
## ("cells" per side, 16 per meter): a two-tone ring with a hard edge that, at the
## end, breaks into gaps instead of fading out.
const RING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float thickness = 0.12;
uniform float t = 0.0;
uniform float cells = 24.0;
void fragment() {
	vec2 q = floor(UV * cells);
	vec2 p = (q + 0.5) / cells * 2.0 - 1.0;
	float r = length(p);
	float g = max(thickness, 2.0 / cells);
	float edge = step(abs(r - (1.0 - g)), g);
	float highlight = step(abs(r - (1.0 - g * 1.4)), g * 0.4);
	// As it fades it is eaten away in checkers (no soft transparency).
	float frame_img = fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
	if (edge < 0.5 || frame_img < t * color.a * 1.05 + (1.0 - color.a)) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), highlight * 0.7);
}
"""

## Beam (streams and rays) in bands: a light core and an edge in the color with no
## gradient, with stepped noise along it (you see the water or light advance in chunks).
const BEAM := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0);
uniform float energy = 3.0;
uniform float flow_speed = 4.0;
uniform float faded = 0.0;
uniform float stream_len = 5.0;   // meters, so long beams are not stretched
uniform sampler2D noise : repeat_enable, filter_nearest;
void fragment() {
	vec2 uv = vec2(floor(UV.x * 12.0) / 12.0, UV.y);
	float tt = floor(TIME * 14.0) / 14.0;
	float n = texture(noise, vec2(uv.x * 1.5, uv.y * stream_len * 0.6 - tt * flow_speed)).r;
	float center = abs(dot(NORMAL, VIEW));
	float band = step(0.72, center + (n - 0.5) * 0.35);
	float middle = step(0.4, center + (n - 0.5) * 0.35);
	vec3 c = mix(color.rgb * 0.82, color.rgb, middle);
	c = mix(c, core.rgb, band);
	float a = step(0.3 + faded * 0.7, n + center * 0.5);
	if (a < 0.5) discard;
	ALBEDO = c * 1.1;
}
"""

## Water stream (Hydro Pump), in 16 px per meter cells measured on the real beam (length and
## girth come in as parameters, so a long stream is not stretched). Water does not flow as a
## perfect cylinder: the mesh itself is lumpy (bulges that travel forward and an uneven
## cross-section that changes along it), thin at the mouth and wider and frothier toward the
## end. Pixel-art water on top: deep, mid and light bands with checkerboard dithering, white
## foam blobs riding the middle, darker at the silhouette, with a broken spray edge. All of
## it moves in steps (14 per second), never smoothly.
const WATER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 deep : source_color = vec4(0.11, 0.33, 0.68, 1.0);
uniform vec4 mid : source_color = vec4(0.2, 0.52, 0.86, 1.0);
uniform vec4 light : source_color = vec4(0.5, 0.78, 0.97, 1.0);
uniform vec4 foam : source_color = vec4(0.93, 0.98, 1.0, 1.0);
uniform float flow_speed = 9.0;
uniform float stream_len = 1.0;   // meters
uniform float girth = 2.0;        // circumference in meters
uniform float faded = 0.0;
varying float along;              // 0 at the mouth, 1 at the end
varying float lump;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	float tt = floor(TIME * 14.0) / 14.0;
	// place_beam() turns the mesh so its +Y end is at the target.
	along = VERTEX.y + 0.5;
	float a = atan(VERTEX.z, VERTEX.x);
	float s = along * stream_len - tt * flow_speed;
	// Lumps that travel forward (about a meter apart), and a cross-section that is never
	// round: some sides bulge while others pinch.
	lump = 0.17 * sin(s * 3.4 + 1.2 * sin(a * 3.0 + s * 0.9))
		+ 0.09 * sin(s * 7.3 + a * 2.0)
		+ 0.06 * sin(a * 5.0 - s * 5.1);
	float flare = mix(0.6, 1.35, smoothstep(0.0, 1.0, along));
	VERTEX.xz *= flare * (1.0 + lump * mix(0.5, 1.0, along));
}
void fragment() {
	float meters = along * stream_len;
	vec2 cell = floor(vec2(UV.x * girth, meters) * 16.0);
	float tt = floor(TIME * 14.0) / 14.0;
	float checker = mod(cell.x + cell.y, 2.0);
	// Wave fronts slanting around the stream, moving forward.
	float ahead = cell.y - tt * flow_speed * 16.0;
	float wobble = 3.0 * sin(cell.x * 0.55) + 2.0 * sin(cell.x * 0.23 + 1.7);
	float f = fract((ahead + wobble) / 14.0);
	float lvl = 0.0;
	if (f > 0.35) lvl = checker;
	if (f > 0.45) lvl = 1.0;
	if (f > 0.68) lvl = 1.0 + checker;
	if (f > 0.76) lvl = 2.0;
	if (f > 0.88) lvl = 3.0;
	float facing = abs(dot(NORMAL, VIEW));
	if (facing > 0.8) lvl = max(lvl, 1.0);
	// Foam blobs riding the middle: ovals of white that come and go, more toward the end.
	float slot = floor((meters - tt * flow_speed) / 1.4);
	float in_slot = fract((meters - tt * flow_speed) / 1.4);
	float blob = (1.0 - abs(in_slot - 0.5) * 2.0) * smoothstep(0.55, 0.85, facing);
	if (hash(vec2(slot, 7.0)) < 0.35 + 0.4 * along && blob > 0.45 - lump) lvl = 3.0;
	else if (blob > 0.3 && lvl < 2.0) lvl = 2.0 - checker;
	// Swollen parts and the end froth up.
	if (lump > 0.12 && facing > 0.5 && checker > 0.5) lvl = max(lvl, 2.0);
	if (along > 0.85 && hash(cell + floor(tt * 7.0)) < (along - 0.85) * 4.0) lvl = 3.0;
	if (facing < 0.3 && lvl < 3.0) lvl = checker > 0.5 ? 0.0 : min(lvl, 1.0);
	// Broken edge: cells at the silhouette drop out like spray, more where it bulges and at
	// the end; more as it fades.
	float ragged = 0.22 + 0.3 * max(lump, 0.0) + 0.1 * along;
	if (facing < ragged && hash(cell + floor(tt * 7.0)) < 0.5 + 0.3 * along) discard;
	// The mouth is not a clean cut either: the first cells come out broken.
	if (meters < 0.3 && hash(cell + floor(tt * 7.0) + 11.0) < 0.55 - meters) discard;
	if (hash(cell * 1.7 + 3.0) < faded) discard;
	vec3 c = lvl < 0.5 ? deep.rgb : (lvl < 1.5 ? mid.rgb : (lvl < 2.5 ? light.rgb : foam.rgb));
	ALBEDO = c;
}
"""

## Ice beam, in 16 px per meter cells like WATER: a thin white core, a light cyan band and
## a mid blue edge that breaks into dithered cells, with brighter chunks and glints
## running along it. Only the core glows (it is energy, unlike water).
const ICE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 edge : source_color = vec4(0.25, 0.58, 0.93, 1.0);
uniform vec4 light : source_color = vec4(0.62, 0.9, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform float flow_speed = 14.0;
uniform float stream_len = 1.0;
uniform float girth = 1.2;
uniform float faded = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 cell = floor(vec2(UV.x * girth, UV.y * stream_len) * 16.0);
	float tt = floor(TIME * 14.0) / 14.0;
	float checker = mod(cell.x + cell.y, 2.0);
	float facing = abs(dot(NORMAL, VIEW));
	// Level by distance to the beam's axis: 0 edge, 1 light, 2 core.
	float lvl = facing > 0.72 ? 2.0 : (facing > 0.45 ? 1.0 : 0.0);
	if (facing > 0.32 && facing <= 0.45) lvl = checker;
	// Brighter chunks travelling along the beam, six cells long.
	float seg = floor((cell.y - tt * flow_speed * 16.0) / 6.0);
	if (hash(vec2(seg, 7.0)) > 0.7) lvl = min(lvl + 1.0, 2.0);
	// Outer edge: dithered and broken, more as it fades.
	if (lvl < 0.5 && (checker < 0.5 || hash(cell + floor(tt * 9.0)) < 0.3)) discard;
	if (hash(cell * 1.3 + 5.0) < faded) discard;
	vec3 c = lvl < 0.5 ? edge.rgb : (lvl < 1.5 ? light.rgb : core.rgb * 1.3);
	// Glints: a few white pixels in the light band.
	if (lvl > 0.5 && lvl < 1.5 && hash(cell + vec2(0.0, floor(tt * 14.0))) > 0.93) c = core.rgb;
	ALBEDO = c;
}
"""

## Lightning: a ribbon of two hard bands (white center, colored edge), no halo.
const LIGHTNING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform vec4 outline : source_color = vec4(0.0);
uniform float energy = 5.0;
void fragment() {
	float d = abs(UV.y - 0.5) * 2.0;
	if (d > 0.9 || COLOR.a < 0.35) discard;
	// Vertices with red at 0 are the outline drawn under the bolt (flat, darker).
	if (COLOR.r < 0.5) {
		ALBEDO = outline.rgb;
	} else {
		ALBEDO = mix(color.rgb, vec3(1.0, 1.0, 0.94), step(d, 0.38)) * 1.15;
	}
}
"""

## Hit trail (a ribbon following a claw or tail): three flat bands (colored edge, lighter
## body, white edge) that shorten in steps.
const RIBBON := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.5;
void fragment() {
	float a = floor(COLOR.a * 3.0) / 3.0;
	float y = UV.y;
	if (a <= 0.0 || y < 0.2 + (1.0 - a) * 0.5 || y > 0.97) discard;
	vec3 c = mix(color.rgb * 0.85, mix(color.rgb, vec3(1.0), 0.45), step(0.55, y));
	ALBEDO = mix(c, vec3(1.0), step(0.86, y)) * 1.1;
}
"""

## Dodge afterimage: a flat silhouette in the color with a lighter outline, which
## disappears in checkered steps (no glow or soft transparency).
const GHOST := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;
uniform vec4 color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float t = 0.0;
void fragment() {
	float fres = 1.0 - abs(dot(NORMAL, VIEW));
	vec2 q = floor(FRAGCOORD.xy / 3.0);
	float pattern = mod(q.x + q.y, 2.0) * 0.5 + mod(q.x, 2.0) * 0.25 + mod(q.y, 2.0) * 0.125;
	if (pattern < 0.3 + t * 0.7 || t > 0.9) discard;
	ALBEDO = mix(color.rgb * 0.75, mix(color.rgb, vec3(1.0), 0.5), step(0.55, fres));
}
"""

## Loose pixel animation (Cobblemon's impacts): the frame comes in as a parameter.
const SPRITE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_add;
uniform sampler2D tex : source_color, filter_nearest;
uniform float energy = 2.0;
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform int frame = 0;
uniform vec4 color : source_color = vec4(1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	float hf = float(h_frames);
	float vf = float(v_frames);
	float f = float(frame);
	UV /= vec2(hf, vf);
	UV += vec2(mod(f, hf) / hf, floor(f / hf) / vf);
}
void fragment() {
	vec4 c = texture(tex, UV) * color;
	ALBEDO = c.rgb * energy;
	ALPHA = c.a;
}
"""

## Ground warning: an edge and fill that grow until the moment of the hit, in pixel
## cells and two tones.
const WARNING := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.45, 0.2, 1.0);
uniform float k = 0.0;
uniform float energy = 1.6;
uniform float cells = 32.0;   // across the diameter: 16 per meter
void fragment() {
	vec2 p = (floor(UV * cells) + 0.5) / cells * 2.0 - 1.0;
	float r = length(p);
	float edge = step(abs(r - 0.93), 0.05);
	float front = step(abs(r - k), 0.045);
	float fill = step(r, k) * step(0.5, mod(floor(UV.x * cells) + floor(UV.y * cells), 2.0));
	float a = max(edge, max(front, fill * 0.5));
	if (a < 0.25 || r > 1.0) discard;
	ALBEDO = mix(color.rgb, vec3(1.0), front * 0.5);
	ALPHA = a < 0.75 ? 0.45 : 1.0;
}
"""


## Animated pixel sprite that always faces the camera (energy balls): a horizontal
## strip of "frames" cells, nearest-neighbor filtered. Half-opaque parts (stepped alpha)
## blend; only the opaque ones glow.
## Pixel strip on a flat quad turned in the world (not toward the camera): Fire Blast's
## character facing whoever threw it, the flat spinning shuriken, Hypnosis's rings across
## their way. "tint" colors it; its alpha is the stepped fade.
const PIXEL_FLAT := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 1.0;
uniform float frame = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(strip, vec2((UV.x + frame) / frames, UV.y));
	if (c.a < 0.04) discard;
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a;
}
"""

## One frame of a pixel strip (frames across or down), facing the camera and tinted: the
## fists of Close Combat popping in and out (Vfx.pop scales it).
const PIXEL_POP := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 1.0;
uniform float frame = 0.0;
uniform bool down = false;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 uv = down ? vec2(UV.x, (UV.y + frame) / frames) : vec2((UV.x + frame) / frames, UV.y);
	vec4 c = texture(strip, uv);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * tint.rgb;
}
"""

## Surf's wave: water in pixel cells over a curved mesh (UV.x across, UV.y from the foot at
## the back up to the curling lip): blue bands, lighter streaks running up, a band of foam
## and a ragged lip that changes as it moves. Back faces (the curl's underside) darker.
const WAVE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_always;
uniform float t = 0.0;
uniform float cells_u = 96.0;
uniform float cells_v = 30.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 c = floor(vec2(UV.x * cells_u, UV.y * cells_v));
	float v = (c.y + 0.5) / cells_v;
	float step_t = floor(t * 10.0);
	if (v > 0.95 - 0.08 * hash(vec2(c.x, step_t))) discard;
	// The foam starts at the crest, so it shows from behind too.
	float lip = 0.56 + 0.07 * hash(vec2(c.x + 7.0, floor(t * 6.0)));
	vec3 col;
	if (v > lip) col = vec3(0.95, 0.99, 1.0);
	else if (v > lip - 0.07) col = vec3(0.62, 0.85, 1.0);
	else if (v > 0.45) col = vec3(0.31, 0.64, 0.92);
	else if (v > 0.2) col = vec3(0.19, 0.5, 0.82);
	else col = vec3(0.12, 0.37, 0.68);
	// Short streaks running up the face, and a little foam at the foot.
	float s = hash(vec2(c.x, floor(c.y * 0.5 - t * 7.0)));
	if (v < lip - 0.07 && v > 0.1 && s > 0.95) col = vec3(0.52, 0.8, 1.0);
	if (v < 0.07 && hash(vec2(c.x, floor(t * 10.0))) > 0.75) col = vec3(0.85, 0.95, 1.0);
	if (!FRONT_FACING) col *= 0.75;
	// The colors are picked as on screen (sRGB); unshaded output wants them linear.
	ALBEDO = pow(col, vec3(2.2));
	// Water a little see-through (one fixed step), the foam solid: the rival shows behind it.
	ALPHA = v > lip - 0.07 ? 1.0 : 0.78;
}
"""

## Dark Pulse's dome, in pixel cells measured in meters on the dome itself (they keep
## their size as it grows). A see-through dark body, ripples of violet running down from
## the top to the ground, dark veins that crawl, and a bright rim where it turns away from
## the camera, so its round shape reads. From inside (the camera caught in it) it is
## fainter. It wobbles in steps and breaks up into cells as it fades.
const DOME := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
uniform vec4 body : source_color = vec4(0.12, 0.04, 0.18, 1.0);
uniform vec4 band : source_color = vec4(0.36, 0.15, 0.55, 1.0);
uniform vec4 rim : source_color = vec4(0.74, 0.5, 1.0, 1.0);
uniform float radius = 1.0;
uniform float faded = 0.0;
uniform float t = 0.0;
varying vec3 local;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	local = VERTEX;
	float tt = floor(t * 14.0) / 14.0;
	float az = atan(VERTEX.z, VERTEX.x);
	VERTEX *= 1.0 + 0.035 * sin(az * 7.0 + tt * 9.0) * (1.0 - VERTEX.y);
}
void fragment() {
	float tt = floor(t * 14.0) / 14.0;
	float az = atan(local.z, local.x);
	float up = asin(clamp(local.y, 0.0, 1.0));            // 0 at the ground, PI/2 at the top
	vec2 cell = floor(vec2(az, up) * radius * 9.0);
	float down = (1.57 - up) * radius;                    // meters from the top
	float facing = abs(dot(NORMAL, VIEW));
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 c = body.rgb;
	float a = 0.4;
	// Ripples running from the top down to the ground.
	float f = fract((down - tt * 9.0) / 1.6);
	if (f > 0.7) { c = band.rgb; a = 0.6; }
	else if (f > 0.6 && checker > 0.5) { c = band.rgb; a = 0.5; }
	// Dark veins crawling over it.
	float vein = hash(vec2(floor(cell.x / 3.0), floor((cell.y - tt * 20.0) / 4.0)));
	if (vein > 0.86) { c = body.rgb * 0.4; a = 0.75; }
	// The rim, where it turns away: bright, with a dithered band inside it.
	if (facing < 0.28) { c = rim.rgb; a = 0.85; }
	else if (facing < 0.42 && checker > 0.5) { c = mix(band.rgb, rim.rgb, 0.5); a = 0.7; }
	// The foot breaks up on the ground, and the whole of it breaks up as it fades (from
	// inside it just fades: big cells right in front of the camera would look like blocks).
	if (local.y < 0.08 && hash(cell + tt) < 0.5) discard;
	if (FRONT_FACING && hash(cell * 1.7 + 3.0) < faded) discard;
	// Seen from inside (the camera caught in it) only the ripples and the rim show, faint;
	// and it clears away right in front of the camera, where its cells would be big blocks.
	if (!FRONT_FACING) {
		if (c == body.rgb) discard;
		a *= 0.35;
	}
	float near = clamp((length(VERTEX) - 2.5) / 4.0, 0.0, 1.0);
	a *= floor(near * 4.0) / 4.0;
	if (a < 0.05) discard;
	ALBEDO = c;
	ALPHA = a * (1.0 - 0.4 * faded);
}
"""

## Dragon Pulse's beam, like a kamehameha that is not a tube. The mesh itself is lumpy
## (bulges that run forward and a cross-section that is never round) and a little wider
## at the end. The core ("shell" 0) is solid: white in the middle, then cyan, violet and a
## dark edge, dithered between bands. The sheath ("shell" 1) wraps it, see-through, with two
## strands of light coiling round it as it flows, pulses of light running along and a
## broken edge. In 12 px per meter cells measured on the real beam, moving in steps.
const DRAGON_BEAM := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform vec4 edge : source_color = vec4(0.22, 0.1, 0.55, 1.0);
uniform vec4 mid : source_color = vec4(0.47, 0.3, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.42, 0.86, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.82, 0.95, 1.0, 1.0);
uniform float flow_speed = 18.0;
uniform float stream_len = 1.0;   // meters
uniform float girth = 2.0;        // circumference in meters
uniform float faded = 0.0;
uniform float shell = 0.0;
varying float along;
varying float lump;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	float tt = floor(TIME * 14.0) / 14.0;
	along = VERTEX.y + 0.5;
	float a = atan(VERTEX.z, VERTEX.x);
	float s = along * stream_len - tt * flow_speed;
	lump = 0.13 * sin(s * 1.9 + 1.3 * sin(a * 3.0 + s * 0.7))
		+ 0.07 * sin(s * 4.7 - a * 2.0)
		+ 0.05 * sin(a * 4.0 + s * 3.1);
	float flare = mix(0.8, 1.2, along);
	VERTEX.xz *= flare * (1.0 + lump * (1.0 + shell));
}
void fragment() {
	float meters = along * stream_len;
	vec2 cell = floor(vec2(UV.x * girth, meters) * 12.0);
	float tt = floor(TIME * 14.0) / 14.0;
	float facing = abs(dot(NORMAL, VIEW));
	float checker = mod(cell.x + cell.y, 2.0);
	float flick = hash(cell + floor(tt * 10.0));
	vec3 c;
	float a = 1.0;
	if (shell > 0.5) {
		float pulse = fract((meters - tt * flow_speed) / 2.4);
		c = pulse > 0.78 ? glow.rgb : mid.rgb;
		a = facing < 0.4 ? 0.7 : 0.3;
		// Two strands coiling round it.
		float coil = fract(UV.x * 2.0 + (meters - tt * flow_speed) * 0.3);
		if (abs(coil - 0.5) < 0.08) { c = mix(glow.rgb, core.rgb, 0.4); a = 0.95; }
		if (facing < 0.3 + 0.3 * max(lump, 0.0) && flick < 0.55) discard;
	} else {
		float f = facing + (flick - 0.5) * 0.14 + lump * 0.4;
		c = f > 0.86 ? core.rgb : (f > 0.6 ? glow.rgb : (f > 0.36 ? mid.rgb : edge.rgb));
		if (f > 0.8 && f < 0.86 && checker > 0.5) c = core.rgb;
		if (f > 0.55 && f < 0.6 && checker > 0.5) c = glow.rgb;
		if (f > 0.31 && f < 0.36 && checker > 0.5) c = mid.rgb;
		if (facing < 0.18 && flick < 0.4) discard;
	}
	// Where it leaves the ball the cells come out broken; the end too.
	if (meters < 0.4 && hash(cell + floor(tt * 7.0) + 11.0) < 0.6 - meters) discard;
	if (along > 0.92 && flick < (along - 0.92) * 8.0) discard;
	if (hash(cell * 1.7 + 3.0) < faded) discard;
	ALBEDO = c;
	ALPHA = a;
}
"""

## Telekinesis outline (Psychic), put on a fighter's meshes as their overlay: the mesh
## pushed out along its normals and drawn from the inside (an inverted hull), so a band of
## light wraps the body and follows its animation. "width" in meters whatever the model's
## scale; it breathes in steps, with lighter bands running up it in screen pixels.
const OUTLINE := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.45, 0.85, 1.0);
uniform float width = 0.06;
uniform float t = 0.0;
void vertex() {
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	float tt = floor(t * 12.0) / 12.0;
	VERTEX += NORMAL * width * (1.0 + 0.3 * sin(tt * 18.0)) / s;
}
void fragment() {
	vec2 q = floor(FRAGCOORD.xy / 3.0);
	float band = mod(q.y + floor(t * 12.0) * 2.0, 7.0);
	ALBEDO = band < 1.5 ? mix(color.rgb, vec3(1.0), 0.7) : color.rgb;
}
"""

const PIXEL_BALL := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;
uniform sampler2D strip : source_color, filter_nearest;
uniform float frames = 1.0;
uniform float frame = 0.0;
uniform float brightness = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	// Stepped alpha (the strip's translucent halos, flames and fields).
	vec4 c = texture(strip, vec2((UV.x + frame) / frames, UV.y));
	if (c.a < 0.04) discard;
	ALBEDO = c.rgb * mix(1.0, brightness, step(0.7, c.a));
	ALPHA = c.a;
}
"""

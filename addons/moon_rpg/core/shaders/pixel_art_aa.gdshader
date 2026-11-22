shader_type canvas_item;
// Sharp-Bilinear Pixel-Art Anti-Aliasing Shader (Cole Cecil / Inigo Quilez method).
// Keeps every art texel razor-sharp while smoothly anti-aliasing ONLY the 1-screen-pixel
// boundary between adjacent texels, completely eliminating pixel shimmer / mixel crawl
// during smooth camera scrolling at ANY resolution (720p / 810p / 1080p / 2K / 4K).

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 pixel = UV * tex_size;
	vec2 seam = floor(pixel + 0.5);
	vec2 dudv = max(fwidth(pixel), vec2(0.0001));
	vec2 uv = (seam + clamp((pixel - seam) / dudv, vec2(-0.5), vec2(0.5))) / tex_size;
	COLOR = texture(TEXTURE, uv) * COLOR;
}

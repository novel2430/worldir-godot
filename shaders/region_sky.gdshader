shader_type sky;

uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform vec3 top_color : source_color = vec3(0.18, 0.38, 0.58);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.79, 0.76);
uniform vec3 ground_color : source_color = vec3(0.28, 0.31, 0.28);
uniform vec3 cloud_color : source_color = vec3(0.92, 0.94, 0.91);
uniform vec3 cloud_shadow_color : source_color = vec3(0.50, 0.55, 0.56);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.28;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_scale : hint_range(0.5, 3.0) = 1.10;
uniform float cloud_speed : hint_range(0.0, 0.03) = 0.0025;
uniform float sun_strength : hint_range(0.0, 2.0) = 0.85;

vec4 render_clouds(vec3 eye_direction) {
    float upper_sky = smoothstep(0.015, 0.16, eye_direction.y);
    if (upper_sky <= 0.0) {
        return vec4(0.0);
    }

    vec2 wind = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.31);
    // Project a high, mostly horizontal cloud sheet onto the sky dome. This
    // keeps cloud shapes broad overhead and naturally compresses them toward
    // the horizon instead of vertically stretching an equirectangular mask.
    vec2 cloud_plane = eye_direction.xz / max(eye_direction.y + 0.24, 0.28);
    vec2 broad_uv = cloud_plane * 0.18 * cloud_scale + wind;
    vec2 detail_uv = cloud_plane * 0.47 * cloud_scale - wind * 1.7;
    float broad = texture(cloud_noise, broad_uv).r;
    float detail = texture(cloud_noise, detail_uv).r;
    float shape = mix(broad, detail, 0.27);
    float threshold = mix(0.76, 0.34, cloud_amount);
    float mask = smoothstep(threshold - 0.10, threshold + 0.12, shape);
    mask *= upper_sky * cloud_opacity;

    float soft_light = smoothstep(threshold - 0.04, threshold + 0.20, shape);
    vec3 color = mix(cloud_shadow_color, cloud_color, 0.42 + soft_light * 0.48);
    return vec4(color, mask);
}

vec3 render_gradient(vec3 eye_direction) {
    float elevation = clamp(eye_direction.y, -1.0, 1.0);
    float sky_height = pow(clamp(elevation, 0.0, 1.0), 0.46);
    vec3 upper = mix(horizon_color, top_color, sky_height);
    vec3 lower = mix(ground_color, horizon_color, smoothstep(-0.32, 0.0, elevation));
    vec3 color = mix(lower, upper, smoothstep(-0.015, 0.055, elevation));

    if (LIGHT0_ENABLED) {
        float sun_alignment = max(dot(eye_direction, -LIGHT0_DIRECTION), 0.0);
        float halo = pow(sun_alignment, 18.0) * 0.075;
        float disk = pow(sun_alignment, 520.0) * 0.9;
        color += LIGHT0_COLOR * LIGHT0_ENERGY * (halo + disk) * sun_strength;
    }
    return color;
}

void sky() {
    vec3 gradient = render_gradient(EYEDIR);
    vec4 clouds = render_clouds(EYEDIR);
    COLOR = mix(gradient, clouds.rgb, clouds.a);
}

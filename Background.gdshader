shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.02, 0.02, 0.1, 1.0);
uniform vec4 beam_color : source_color = vec4(0.1, 0.4, 0.9, 1.0);

void fragment() {
    vec2 uv = UV;
    
    // Ciemne tÅ‚o
    vec4 color = bg_color;
    
    // Animowane beli Å›wietlne (efekt studja TV)
    float t = TIME * 0.2;
    
    // Generujemy 3 fale Å›wietlne
    for(float i = 1.0; i <= 3.0; i++) {
        // Sinusoidalny ksztaÅ‚t wiÄ…zki pionowej
        float offset = sin(uv.y * (3.0 + i) + t * i) * 0.15;
        float d = abs(uv.x - 0.5 + offset);
        
        // Funkcja 1/x dla poÅ›wiaty (glow)
        float beam = 0.015 / (d + 0.05); 
        
        // Dodajemy do koloru
        color += beam_color * beam * 0.2;
    }
    
    // Subtelny szum/ziarno dla tekstury
    float noise = fract(sin(dot(uv * TIME, vec2(12.9898, 78.233))) * 43758.5453);
    color.rgb += noise * 0.02;

    // Winieta (przyciemnienie rogÃ³w)
    float vig = 1.0 - distance(uv, vec2(0.5));
    color.rgb *= smoothstep(0.0, 1.2, vig);
    
    COLOR = color;
}
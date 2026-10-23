// A lightning strike's shock, on the picture (Scene.effects): a ring of ripples spreading from where it struck,
// values[0] and values[1] in the view's pixels, values[2] seconds after, weakening as it goes.
half4 ripple(float2 position, Layer layer, Values values) {
    float2 way = position - float2(values[0], values[1]);
    float distance = length(way);
    float ring = distance - values[2] * 220; // the front moves 220 pixels a second
    if (abs(ring) > 24) return layer.sample(position); // most of the picture, far from the ring, as it is
    float strength = exp(-ring * ring / 120) * saturate(1 - values[2] / 0.7) * 4;
    return layer.sample(position + way / max(distance, 1.0) * sin(ring * 0.5) * strength);
}

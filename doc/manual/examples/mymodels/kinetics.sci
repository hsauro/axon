## Rate laws for enzyme kinetics.

## The Michaelis-Menten rate for substrate s.
export function mm(s; vmax = 1.0, km = 0.5)
  return vmax * s / (km + s)
end

## The Hill rate for substrate s with coefficient h.
export function hill(s, h; vmax = 1.0, k = 0.5)
  return vmax * s^h / (k^h + s^h)
end

# Not exported: only this module can use it.
function check(s)
  if s < 0
    error("DomainError", "negative concentration")
  end
end

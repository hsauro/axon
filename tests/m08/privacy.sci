secret = 42
export function get_secret() return secret end
export function set_secret(v)
  global secret
  secret = v
end

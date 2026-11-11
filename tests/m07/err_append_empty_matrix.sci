#! error: TypeError
# zeros(0, 1) is a 0x1 matrix, not an empty vector: the message says what to use.
ts = zeros(0, 1)
ts = append(ts, 1.5)

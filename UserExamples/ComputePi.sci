## From Rosetta Code, BASIC256 converted to Axon
## https://rosettacode.org/wiki/Pi

n = 1000
len = div(10*n, 4)
a = zeros(len)          # a[1] .. a[len] correspond to BASIC256's a(0) .. a(len-1)
nines = 0
predigit = 0.0            # first predigit is a 0

perline = 80            # digits per row

# needdecimal: no "." printed yet; digitcount: digits after the "." (for line wrapping).
state = {needdecimal: true, digitcount: 0}

function outputd(d, s, perline)
  if s.needdecimal
    if d == 0
      return s
    end
    print(string(int(d)) + ".")
    s.needdecimal = false
  else
    print(string(int(d)))
    s.digitcount = s.digitcount + 1
    if mod(s.digitcount, perline) == 0
      println()
    end
  end
  return s
end

for j in 1:len
  a[j] = 2               # start with 2s
end

for j in 1:n
  # Change q = 0 to q = 0.0 to see a significant speed change. 
  q = 0
  for i in len:-1:1       # work backwards
    x = 10*a[i] + q*i
    a[i] = mod(x, 2*i - 1)
    q = div(x, 2*i - 1)
  end
  a[1] = mod(q, 10)
  q = div(q, 10)
  if q == 9
    nines = nines + 1
  elseif q == 10
    state = outputd(predigit + 1, state, perline)
    if nines > 0
      for k in 1:nines
        state = outputd(0, state, perline)
      end
    end
    predigit = 0.0
    nines = 0
  else
    state = outputd(predigit, state, perline)
    predigit = q
    if nines != 0
      for k in 1:nines
        state = outputd(9, state, perline)
      end
      nines = 0
    end
  end
end

outputd(predigit, state, perline)
println()

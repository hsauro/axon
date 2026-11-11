## From Rosetta Code, BASIC256 converted to Axon
## https://rosettacode.org/wiki/Pi

n = 1000
len = div(10*n, 4)
needdecimal = true
a = zeros(len)          # a[1] .. a[len] correspond to BASIC256's a(0) .. a(len-1)
nines = 0
predigit = 0            # first predigit is a 0

digitcount = 0          # digits printed after the decimal point, for line wrapping
perline = 80            # digits per row

function outputd(d)
  global needdecimal
  global digitcount
  if needdecimal
    if d == 0
      return
    end
    print(string(int(d)) + ".")
    needdecimal = false
  else
    print(string(int(d)))
    digitcount = digitcount + 1
    if mod(digitcount, perline) == 0
      println()
    end
  end
end

for j in 1:len
  a[j] = 2               # start with 2s
end

for j in 1:n
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
    outputd(predigit + 1)
    if nines > 0
      for k in 1:nines
        outputd(0)
      end
    end
    predigit = 0
    nines = 0
  else
    outputd(predigit)
    predigit = q
    if nines != 0
      for k in 1:nines
        outputd(9)
      end
      nines = 0
    end
  end
end

outputd(predigit)
println()

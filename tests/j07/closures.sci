# Closures and values read from outside (J7c). The JIT is on; results must
# be the interpreter's.
__jit_mode("on")

# A captured value is read at each call: changes are seen; a change of type
# makes that call run interpreted.
k = 2
mul = function(x) return x * k end
print(mul(5), __jit_compiled(mul))
k = 3
print(mul(5))
k = 1.5
print(mul(5))

# A field path on a captured record.
p = {a: 2.0}
fa = function(x) return x * p.a end
print(fa(3))
p.a = 4.0
print(fa(3))
p = {a: 1, b: 2}
print(fa(3))

# A closure that assigns a variable outside stays interpreted.
count = 0
tick = function() count = count + 1 end
tick()
tick()
print(count, __jit_compiled(tick), __jit_reason(tick))

# A closure's own variable, until the enclosing function defines the name:
# then rule 5 makes the closure assign the enclosing one.
function maker()
  g = function(x)
    y = x * 2
    return y
  end
  r1 = g(1)
  y = 100
  r2 = g(5)
  return r1 * 1000 + r2 * 10 + y
end
print(maker())

# Vector and matrix literals.
v = function(a, b) return [a; b; a + b] end
print(isequal(v(1, 2), [1; 2; 3]), isequal(v(0.5, 1), [0.5; 1.0; 1.5]), __jit_compiled(v))
m = function(a) return [a, 2.0; 3.0, a] end
print(isequal(m(1.0), [1.0, 2.0; 3.0, 1.0]))

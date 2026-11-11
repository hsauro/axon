# Rosetta Code: Gamma function
# https://rosettacode.org/wiki/Gamma_function
#
# Computes Gamma(x) for real x using the Lanczos approximation
# (g=7, 9-term series, coefficients from the GNU Scientific Library —
# the same constants used by many other language solutions on the task page).
# Uses the reflection formula for x < 0.5 so the function also works
# for negative, non-integer arguments.

function gamma(x: real)
    g = 7
    p = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
         771.32342877765313, -176.61502916214059, 12.507343278686905,
         -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]

    if x < 0.5
        return pi / (sin(pi * x) * gamma(1.0 - x))
    end

    x = x - 1.0
    a = p[1]
    for i in 1:8
        a = a + p[i + 1] / (x + i)
    end
    t = x + g + 0.5
    return sqrt(2.0 * pi) * t ^ (x + 0.5) * exp(-t) * a
end

# --- Demonstration: compare against (n-1)! for integer arguments,
#     and show a range of fractional arguments ---

println("x", "gamma(x)")
for i in 1:20
    x = i / 10.0
    println(format(x, 1), format(gamma(x), 12))
end

println()
println("Check against factorial: gamma(n) == (n-1)!")
for n in 1:10
    g = gamma(n)
    f = factorial(n - 1)
    println(n, format(g, 6), f)
end

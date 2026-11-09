## Basic statistics: the mean, variance and standard deviation of a sample,
## and a least-squares straight line through data points.

# ------------------------------------------------------------ helpers

# The data as a real vector: a vector or range of numbers with at least
# `least` elements. Not exported: only this module uses it.
function sample(x, least, where)
  if not (isa(x, "vector") or isa(x, "range"))
    error("TypeError", where + ": data must be a vector, got " + typeof(x))
  end
  if length(x) < least
    error("ArgumentError", where + ": needs at least " + string(least) +
          " values, got " + string(length(x)))
  end
  return [x] + 0.0
end

# ------------------------------------------------------------ public API

## The arithmetic mean of the values in x.
export function mean(x)
  v = sample(x, 1, "stats.mean")
  return sum(v) / length(v)
end

## The variance of x. By default the sample variance, which divides by
## n - 1; with population = true, the population variance (divides by n).
export function variance(x; population = false)
  v = sample(x, 2, "stats.variance")
  m = sum(v) / length(v)
  d = v - m
  n = length(v)
  if population
    return sum(d .* d) / n
  end
  return sum(d .* d) / (n - 1)
end

## The standard deviation of x, the square root of its variance; the same
## population keyword as variance.
export function std(x; population = false)
  return sqrt(variance(x, population = population))
end

## The least-squares straight line y = slope * x + intercept through the
## points (x[k], y[k]). Returns a record with slope, intercept and r2, the
## fraction of the variance of y that the line explains.
export function linfit(x, y)
  xs = sample(x, 2, "stats.linfit")
  ys = sample(y, 2, "stats.linfit")
  if length(xs) != length(ys)
    error("DimensionError", "stats.linfit: x has " + string(length(xs)) +
          " values but y has " + string(length(ys)))
  end
  mx = sum(xs) / length(xs)
  my = sum(ys) / length(ys)
  sxx = sum((xs - mx) .* (xs - mx))
  sxy = sum((xs - mx) .* (ys - my))
  if sxx == 0
    error("ArgumentError", "stats.linfit: all x values are equal")
  end
  slope = sxy / sxx
  intercept = my - slope * mx
  resid = ys - (slope * xs + intercept)
  syy = sum((ys - my) .* (ys - my))
  r2 = 1.0
  if syy > 0
    r2 = 1.0 - sum(resid .* resid) / syy
  end
  return {slope: slope, intercept: intercept, r2: r2}
end

## The values of a fitted line, as linfit returns it, at x.
export function predict(fit, x)
  return fit.slope * x + fit.intercept
end

#! error: DimensionError
import linalg
x = linalg.lstsq([1, 2; 3, 4], [1; 2; 3])

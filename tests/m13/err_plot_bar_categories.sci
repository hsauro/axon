#! error: ArgumentError
import plot
plot.bar({"a", "b"}, [1.0; 2.0])
plot.bar({"a", "c"}, [1.0; 2.0])

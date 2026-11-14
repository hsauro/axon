#! error: ArgumentError
# kernel takes a model or a stoichiometry matrix, not the model's text.
import antimony
k = antimony.kernel("A -> B; k*A; k = 1")

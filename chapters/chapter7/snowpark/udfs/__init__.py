"""Section 3: Snowpark User-Defined Functions (scalar and vectorized)."""

from .scalar_risk_tier import classify_risk_tier_logic, register as register_scalar
from .vectorized_risk_tier import (
    classify_risk_tier_vec_logic,
    register as register_vectorized,
)

__all__ = [
    "classify_risk_tier_logic",
    "classify_risk_tier_vec_logic",
    "register_scalar",
    "register_vectorized",
]

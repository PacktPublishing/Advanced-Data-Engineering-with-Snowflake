"""Section 4.1: User-Defined Table Functions for per-group processing."""

from .velocity_flagger import TransactionVelocityFlagger, register

__all__ = ["TransactionVelocityFlagger", "register"]

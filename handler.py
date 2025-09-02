#!/usr/bin/env python3
"""
RunPod Hub handler entry point - delegates to rp_handler.py
"""

from rp_handler import handler

# Export the handler function for RunPod Hub
__all__ = ['handler']
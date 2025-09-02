#!/usr/bin/env python3
"""
RunPod Serverless Handler wrapper
This file acts as the entry point that RunPod looks for
"""

import sys
import os

# Add workspace to path
sys.path.insert(0, '/workspace')

# Import the actual handler module
import rp_handler

# Re-export handler function for RunPod
__all__ = ['handler']

def handler(job):
    """RunPod serverless handler entry point"""
    return rp_handler.handler(job)
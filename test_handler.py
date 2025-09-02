#!/usr/bin/env python3
"""
Test script to validate handler can be imported
"""

import sys
import os

# Test handler import
try:
    sys.path.insert(0, '/workspace')
    import handler
    print("✓ handler.py imported successfully")
    
    # Check handler function exists
    if hasattr(handler, 'handler'):
        print("✓ handler function found")
    else:
        print("✗ handler function missing")
        sys.exit(1)
        
except ImportError as e:
    print(f"✗ Failed to import handler: {e}")
    sys.exit(1)

# Test rp_handler import
try:
    import rp_handler
    print("✓ rp_handler.py imported successfully")
    
    if hasattr(rp_handler, 'handler'):
        print("✓ rp_handler.handler function found")
    else:
        print("✗ rp_handler.handler function missing")
        sys.exit(1)
        
except ImportError as e:
    print(f"✗ Failed to import rp_handler: {e}")
    sys.exit(1)

print("\n✅ All handler tests passed!")
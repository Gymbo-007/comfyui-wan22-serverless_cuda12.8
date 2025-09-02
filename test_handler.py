#!/usr/bin/env python3
"""
Test script to validate handler can be imported
"""

import sys
import os

# Test handler import
try:
    import handler
    print("✓ handler.py imported successfully")
    
    # Check handler function exists
    if hasattr(handler, 'handler'):
        print("✓ handler.handler function found")
        print(f"✓ handler.handler callable: {callable(handler.handler)}")
    else:
        print("✗ handler.handler function missing")
        sys.exit(1)
        
except Exception as e:
    print(f"✗ Failed to import handler: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test rp_handler import
try:
    import rp_handler
    print("✓ rp_handler.py imported successfully")
    
    if hasattr(rp_handler, 'handler'):
        print("✓ rp_handler.handler function found")
        print(f"✓ rp_handler.handler callable: {callable(rp_handler.handler)}")
    else:
        print("✗ rp_handler.handler function missing")
        sys.exit(1)
        
except Exception as e:
    print(f"✗ Failed to import rp_handler: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n✅ All handler tests passed!")
print("✓ RunPod should be able to find handler.handler")
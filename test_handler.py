#!/usr/bin/env python3
"""Test script to validate handler can be imported"""

import sys

print("🧪 Testing minimal handler...")

# Test handler import and function
try:
    import handler
    print("✓ handler.py imported successfully")
    
    if hasattr(handler, 'handler') and callable(handler.handler):
        print("✓ handler.handler function found and callable")
        
        # Test handler execution
        test_job = {"input": {"test": "validation"}}
        result = handler.handler(test_job)
        print(f"✓ handler.handler executed: {result}")
        
        if result.get('status') == 'success':
            print("✅ Handler validation PASSED")
        else:
            print("✗ Handler returned error")
            sys.exit(1)
    else:
        print("✗ handler.handler function missing or not callable")
        sys.exit(1)
        
except Exception as e:
    print(f"✗ Handler test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("🚀 Ready for RunPod deployment!")
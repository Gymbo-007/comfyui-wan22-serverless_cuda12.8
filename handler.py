#!/usr/bin/env python3
"""RunPod Serverless Handler Entry Point"""

def handler(job):
    """Minimal RunPod handler for testing"""
    try:
        input_data = job.get('input', {})
        return {
            "status": "success",
            "message": "Handler working correctly",
            "received_input": input_data
        }
    except Exception as e:
        return {
            "status": "error", 
            "message": f"Handler error: {str(e)}"
        }

# For direct testing
if __name__ == "__main__":
    print("✓ Handler module can be imported and executed")
    test_job = {"input": {"test": "data"}}
    result = handler(test_job)
    print(f"✓ Handler test result: {result}")
#!/usr/bin/env python3
"""
RunPod Serverless Handler for Wan 2.2 Image-to-Video
Processes ComfyUI workflows via RunPod serverless API
"""

import os
import json
import base64
import time
from io import BytesIO
from PIL import Image
import requests
import runpod

# ComfyUI API endpoints
COMFYUI_URL = "http://127.0.0.1:8188"
API_QUEUE = f"{COMFYUI_URL}/prompt"
API_HISTORY = f"{COMFYUI_URL}/history"
API_VIEW = f"{COMFYUI_URL}/view"

def load_workflow():
    """Load the default Wan 2.2 workflow"""
    workflow_path = "/workspace/ComfyUI/workflows/Wan22_I2V_Native_3_stage.json"
    if os.path.exists(workflow_path):
        with open(workflow_path, 'r') as f:
            return json.load(f)
    else:
        raise FileNotFoundError(f"Workflow not found: {workflow_path}")

def encode_image_to_base64(image_path):
    """Convert image to base64 string"""
    with open(image_path, 'rb') as img_file:
        return base64.b64encode(img_file.read()).decode('utf-8')

def decode_base64_to_image(base64_str, output_path):
    """Save base64 string as image file"""
    image_data = base64.b64decode(base64_str)
    with open(output_path, 'wb') as f:
        f.write(image_data)
    return output_path

def update_workflow_parameters(workflow, params):
    """Update workflow with user parameters"""
    # Find key nodes by their types
    text_positive_node = None
    text_negative_node = None
    image_load_node = None
    resolution_node = None
    length_node = None
    
    for node_id, node_data in workflow.items():
        if isinstance(node_data, dict) and 'class_type' in node_data:
            if node_data['class_type'] == 'CLIPTextEncode':
                if 'positive' in node_data.get('_meta', {}).get('title', '').lower():
                    text_positive_node = node_id
                elif 'negative' in node_data.get('_meta', {}).get('title', '').lower():
                    text_negative_node = node_id
            elif node_data['class_type'] == 'LoadImage':
                image_load_node = node_id
            elif node_data['class_type'] == 'INTConstant' and 'Resolution' in node_data.get('_meta', {}).get('title', ''):
                resolution_node = node_id
            elif node_data['class_type'] == 'INTConstant' and 'Length' in node_data.get('_meta', {}).get('title', ''):
                length_node = node_id
    
    # Update parameters
    if params.get('prompt') and text_positive_node:
        workflow[text_positive_node]['inputs']['text'] = params['prompt']
    
    if params.get('negative_prompt') and text_negative_node:
        workflow[text_negative_node]['inputs']['text'] = params['negative_prompt']
    
    if params.get('image') and image_load_node:
        # Save input image to ComfyUI input folder
        input_path = f"/workspace/ComfyUI/input/input_image_{int(time.time())}.png"
        decode_base64_to_image(params['image'], input_path)
        workflow[image_load_node]['inputs']['image'] = os.path.basename(input_path)
    
    if params.get('resolution') and resolution_node:
        workflow[resolution_node]['inputs']['value'] = int(params['resolution'])
    
    if params.get('length') and length_node:
        workflow[length_node]['inputs']['value'] = int(params['length'])
    
    return workflow

def queue_workflow(workflow):
    """Queue workflow to ComfyUI and return prompt_id"""
    payload = {"prompt": workflow}
    response = requests.post(API_QUEUE, json=payload)
    
    if response.status_code != 200:
        raise Exception(f"Failed to queue workflow: {response.status_code}")
    
    result = response.json()
    return result['prompt_id']

def wait_for_completion(prompt_id, timeout=600):
    """Wait for workflow completion and return results"""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        response = requests.get(f"{API_HISTORY}/{prompt_id}")
        
        if response.status_code == 200:
            history = response.json()
            
            if prompt_id in history:
                result = history[prompt_id]
                if result.get('status', {}).get('completed', False):
                    return result
                elif result.get('status', {}).get('status_str') == 'error':
                    raise Exception(f"Workflow failed: {result['status']}")
        
        time.sleep(2)
    
    raise TimeoutError(f"Workflow timeout after {timeout}s")

def get_output_videos(result):
    """Extract output video paths from workflow result"""
    videos = []
    
    for node_id, node_result in result.get('outputs', {}).items():
        for output_type, output_data in node_result.items():
            if isinstance(output_data, list):
                for item in output_data:
                    if isinstance(item, dict) and 'filename' in item:
                        filename = item['filename']
                        if filename.endswith('.mp4'):
                            video_path = f"/workspace/ComfyUI/output/{filename}"
                            if os.path.exists(video_path):
                                videos.append(video_path)
    
    return videos

def handler(job):
    """Main handler function for RunPod serverless"""
    try:
        print("Starting Wan 2.2 I2V processing...")
        
        # Extract input parameters - RunPod format
        input_data = job.get('input', {})
        
        # Required parameters
        if 'image' not in input_data:
            return {"error": "Missing required parameter: image (base64)"}
        
        # Default parameters
        params = {
            'image': input_data.get('image'),
            'prompt': input_data.get('prompt', 'high quality video, smooth motion'),
            'negative_prompt': input_data.get('negative_prompt', 'static, blurry, low quality'),
            'resolution': input_data.get('resolution', 832),
            'length': input_data.get('length', 25),
        }
        
        print(f"Processing with parameters: {json.dumps({k: v if k != 'image' else 'base64_image' for k, v in params.items()})}")
        
        # Load and update workflow
        workflow = load_workflow()
        workflow = update_workflow_parameters(workflow, params)
        
        print("Queueing workflow to ComfyUI...")
        prompt_id = queue_workflow(workflow)
        
        print(f"Waiting for completion (prompt_id: {prompt_id})...")
        result = wait_for_completion(prompt_id)
        
        print("Processing completed, extracting outputs...")
        video_paths = get_output_videos(result)
        
        if not video_paths:
            return {"error": "No output videos generated"}
        
        # Encode videos to base64
        outputs = []
        for video_path in video_paths:
            try:
                video_b64 = encode_image_to_base64(video_path)
                outputs.append({
                    'filename': os.path.basename(video_path),
                    'video_base64': video_b64
                })
                print(f"Encoded output: {os.path.basename(video_path)}")
            except Exception as e:
                print(f"Failed to encode {video_path}: {e}")
        
        return {
            'videos': outputs,
            'prompt_id': prompt_id,
            'processing_time': time.time() - job.get('start_time', time.time())
        }
        
    except Exception as e:
        print(f"Handler error: {str(e)}")
        return {"error": str(e)}

if __name__ == '__main__':
    runpod.serverless.start({'handler': handler})
docker buildx build \
  --platform linux/amd64 \
  -t gymbo007/kylee-comfy:torch2.8-cuda12.8-amd64 \
  --push .

# WorthIt.AI Backend Service v2.0 - Deployment Guide

## Overview
This is the new, clean, and streamlined version of the WorthIt.AI backend service. It maintains 100% compatibility with the Swift app while being dramatically simpler and more maintainable.

## Key Improvements
- **Reduced complexity**: From 2,800+ lines to ~500 lines
- **Clean architecture**: Separated concerns into service classes
- **Simplified fallbacks**: 3-layer transcript strategy instead of 5
- **Better caching**: TTL-based memory cache for transcripts and comments
- **Maintained compatibility**: Exact same API contracts as before
- **Production-ready**: Proper logging, rate limiting, and error handling

## Environment Variables Required

```bash
# OpenAI API Key (required)
OPENAI_API_KEY=your_openai_api_key_here

# Webshare Proxy Credentials (required for YouTube access)
WEBSHARE_USER=lnoyshsr
WEBSHARE_PASS=your_webshare_password_here

# Optional
DEBUG=false
PORT=8080
```

## Deployment Steps

### 1. Replace Files
```bash
# Backup current app.py
cp app.py app_old.py

# Replace with new version
cp app_new.py app.py

# Update requirements
cp requirements_new.txt requirements.txt
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Test Locally
```bash
# Set environment variables
export OPENAI_API_KEY="your_key"
export WEBSHARE_USER="lnoyshsr"
export WEBSHARE_PASS="your_password"

# Run the application
python app.py
```

### 4. Test Endpoints
```bash
# Test transcript endpoint
curl "http://localhost:8080/transcript?videoId=LfIonsHpKZc&languages=en"

# Test comments endpoint
curl "http://localhost:8080/comments?videoId=LfIonsHpKZc"

# Test OpenAI proxy
curl -X POST "http://localhost:8080/openai/responses" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-3.5-turbo","input":"Hello world","max_output_tokens":100}'
```

### 5. Deploy to Google Cloud Run
```bash
# Build and deploy
gcloud run deploy worthit-backend \
  --source . \
  --platform managed \
  --region europe-west1 \
  --allow-unauthenticated \
  --set-env-vars OPENAI_API_KEY="your_key",WEBSHARE_USER="lnoyshsr",WEBSHARE_PASS="your_password"
```

## API Endpoints

### GET /transcript
- **Purpose**: Fetch video transcript
- **Parameters**: 
  - `videoId`: YouTube video ID or URL
  - `languages`: Comma-separated language codes (optional)
- **Response**: `{"text": "transcript content"}`
- **Fallback Strategy**: 
  1. youtube-transcript-api with webshare proxy
  2. Direct youtube-transcript-api
  3. Basic timedtext fetch

### GET /comments
- **Purpose**: Fetch video comments
- **Parameters**: 
  - `videoId`: YouTube video ID or URL
- **Response**: `{"comments": ["comment1", "comment2", ...]}`
- **Fallback Strategy**: 
  1. youtube-comment-downloader with proxy
  2. Direct youtube-comment-downloader
  3. Return empty array (gracefully handled by Swift app)

### POST /openai/responses
- **Purpose**: Proxy OpenAI API requests
- **Request**: OpenAI-compatible JSON payload
- **Response**: OpenAI Responses API format
- **Features**: Maintains exact compatibility with existing Swift integration

### GET /openai/responses/<id>
- **Purpose**: Retrieve stored OpenAI responses
- **Response**: OpenAI Responses API format

### Static Routes
- `/privacy` → Redirects to Google Cloud hosted privacy page
- `/terms` → Redirects to Google Cloud hosted terms page  
- `/support` → Redirects to Google Cloud hosted support page
- `/` → Service uptime and status
- `/_health` → Health check endpoint

## Caching Strategy
- **Transcript Cache**: 1 hour TTL, 200 items max
- **Comments Cache**: 30 minutes TTL, 100 items max
- **Memory-based**: Fast access, automatically expires

## Rate Limiting
- **Transcript**: 1000/hour, 200/minute
- **Comments**: 120/hour, 20/minute
- **OpenAI**: 200/hour, 50/minute
- **General**: 1000/hour default

## Logging
- **Structured JSON logs**: Compatible with existing log analysis
- **Request tracking**: Unique request IDs for debugging
- **Performance metrics**: Duration tracking for all operations
- **Event-based**: Easy to filter and analyze

## Monitoring
The service logs the same events as the previous version:
- `transcript_fetch_workflow_start`
- `transcript_cache_hit`
- `transcript_response_summary`
- `comments_fetch_workflow_start`
- `comments_cache_hit`
- `comments_result`
- `openai_proxy_request`
- `openai_proxy_response`

## Rollback Plan
If issues occur:
```bash
# Restore previous version
cp app_old.py app.py
cp requirements.txt requirements_old.txt
# Redeploy
```

## Testing Checklist
- [ ] Transcript endpoint returns correct format
- [ ] Comments endpoint returns correct format  
- [ ] OpenAI proxy maintains Responses API compatibility
- [ ] Caching works correctly
- [ ] Rate limiting functions properly
- [ ] Static routes redirect correctly
- [ ] Health check returns uptime
- [ ] Logging produces expected events
- [ ] Swift app integration works seamlessly

## Performance Expectations
- **Transcript**: ~2-30 seconds (depending on video length)
- **Comments**: ~0.5-2 seconds
- **OpenAI**: ~1-10 seconds (depending on model and prompt)
- **Cache hits**: <10ms
- **Memory usage**: ~50-100MB typical

This new version should provide the same functionality with significantly better maintainability and performance.

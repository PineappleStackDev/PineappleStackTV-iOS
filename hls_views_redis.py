import json
import logging
from django.http import StreamingHttpResponse, JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from .server import ProxyServer

logger = logging.getLogger(__name__)
proxy_server = ProxyServer()


@csrf_exempt
@require_http_methods(["GET"])
def stream_endpoint(request, channel_id):
    """Handle HLS manifest requests."""
    client_ip = request.META.get("REMOTE_ADDR", "unknown")
    content, status = proxy_server.stream_endpoint(channel_id, client_ip=client_ip)
    if status == 200:
        return HttpResponse(content, content_type="application/vnd.apple.mpegurl", status=200)
    return JsonResponse({"error": content}, status=status)


@csrf_exempt
@require_http_methods(["GET"])
def get_segment(request, channel_id, segment_name):
    """Serve MPEG-TS segments from Redis."""
    client_ip = request.META.get("REMOTE_ADDR", "unknown")
    data, status = proxy_server.get_segment(channel_id, segment_name, client_ip=client_ip)
    if status == 200:
        return HttpResponse(data, content_type="video/MP2T", status=200)
    return JsonResponse({"error": "Segment not found"}, status=status)


@csrf_exempt
@require_http_methods(["POST"])
def change_stream(request, channel_id):
    """Change stream URL for existing channel."""
    try:
        body = json.loads(request.body)
        new_url = body.get("url")
        if not new_url:
            return JsonResponse({"error": "No URL provided"}, status=400)
        result, status = proxy_server.change_stream(channel_id, new_url)
        return JsonResponse(result, status=status)
    except json.JSONDecodeError:
        return JsonResponse({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Failed to change stream: {e}")
        return JsonResponse({"error": str(e)}, status=500)


@csrf_exempt
@require_http_methods(["POST"])
def initialize_stream(request, channel_id):
    """Initialize a new HLS stream channel."""
    try:
        body = json.loads(request.body)
        url = body.get("url")
        if not url:
            return JsonResponse({"error": "No URL provided"}, status=400)

        proxy_server.initialize_channel(url, channel_id)
        return JsonResponse({
            "message": "Stream initialized",
            "channel": channel_id,
            "url": url,
        })
    except json.JSONDecodeError:
        return JsonResponse({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Failed to initialize stream: {e}")
        return JsonResponse({"error": str(e)}, status=500)

"""
HLS Proxy Server - ffmpeg-based with disk storage.

Each active channel runs a single ffmpeg process that:
- Reads the source HLS/TS stream
- Copies video, transcodes audio to AAC
- Outputs HLS segments to disk
- Maintains the m3u8 playlist automatically

Client tracking via Redis for multi-worker coordination.
Segments served as static files from /tmp/hls/{channel_id}/.
"""

import os
import shutil
import subprocess
import threading
import logging
import time
from typing import Optional, Dict
from core.utils import RedisClient

logger = logging.getLogger(__name__)

HLS_ROOT = "/data/hls"
CLIENT_INACTIVITY_TIMEOUT = 120  # Stop ffmpeg after 2 min of no clients
INITIAL_GRACE_PERIOD = 30  # Wait for first client
CLEANUP_INTERVAL = 5


def _key(channel_id: str, *parts: str) -> str:
    return "hls:" + channel_id + ":" + ":".join(parts)


def _channel_dir(channel_id: str) -> str:
    return os.path.join(HLS_ROOT, channel_id)


def _playlist_path(channel_id: str) -> str:
    return os.path.join(_channel_dir(channel_id), "stream.m3u8")


class ChannelProcess:
    """Manages a single ffmpeg process for one channel."""

    def __init__(self, channel_id: str, source_url: str):
        self.channel_id = channel_id
        self.source_url = source_url
        self.process: Optional[subprocess.Popen] = None
        self.started_at = time.time()
        self._redis = RedisClient.get_client()

    def start(self):
        """Start the ffmpeg HLS segmenter."""
        out_dir = _channel_dir(self.channel_id)
        os.makedirs(out_dir, exist_ok=True)

        playlist = _playlist_path(self.channel_id)

        is_local_file = self.source_url.startswith("/")

        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning"]

        if not is_local_file:
            cmd += ["-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5"]

        cmd += ["-i", self.source_url, "-c:v", "copy"]

        # Only transcode audio for live streams (recordings already have AAC from the recording ffmpeg)
        if is_local_file:
            cmd += ["-c:a", "copy"]
        else:
            cmd += ["-c:a", "aac", "-b:a", "192k", "-ac", "2"]

        cmd += [
            "-f", "hls",
            "-hls_time", "6",
            "-hls_list_size", "0",
            "-hls_playlist_type", "vod" if is_local_file else "event",
        ]

        if is_local_file:
            # For recordings: generate complete playlist immediately
            cmd += ["-hls_flags", "temp_file"]
        else:
            cmd += ["-hls_flags", "append_list+omit_endlist+temp_file"]

        cmd += [
            "-hls_segment_filename", os.path.join(out_dir, "seg_%05d.ts"),
            playlist,
        ]

        logger.info(f"[{self.channel_id}] Starting ffmpeg: {' '.join(cmd[:8])}...")
        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        self.started_at = time.time()

        # Store metadata in Redis
        self._redis.hset(_key(self.channel_id, "meta"), mapping={
            "url": self.source_url,
            "active": "1",
            "created": str(time.time()),
            "pid": str(self.process.pid),
        })
        self._redis.expire(_key(self.channel_id, "meta"), 86400)

        logger.info(f"[{self.channel_id}] ffmpeg started (PID {self.process.pid})")

    def stop(self):
        """Stop ffmpeg and clean up files."""
        if self.process and self.process.poll() is None:
            logger.info(f"[{self.channel_id}] Stopping ffmpeg (PID {self.process.pid})")
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()

        # Clean up files
        out_dir = _channel_dir(self.channel_id)
        if os.path.exists(out_dir):
            shutil.rmtree(out_dir, ignore_errors=True)
            logger.info(f"[{self.channel_id}] Cleaned up {out_dir}")

        # Clean up Redis
        self._redis.delete(_key(self.channel_id, "meta"))
        self._redis.delete(_key(self.channel_id, "clients"))

    def is_running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def has_playlist(self) -> bool:
        return os.path.exists(_playlist_path(self.channel_id))


class ProxyServer:
    """
    HLS proxy using ffmpeg for segmentation and audio transcode.
    Multi-worker safe: only one worker runs ffmpeg per channel,
    coordinated via Redis. All workers can serve files from disk.
    """

    def __init__(self, user_agent: Optional[str] = None):
        self._redis = RedisClient.get_client()
        self._processes: Dict[str, ChannelProcess] = {}
        self._cleanup_threads: Dict[str, threading.Thread] = {}
        os.makedirs(HLS_ROOT, exist_ok=True)

    def initialize_channel(self, url: str, channel_id: str) -> None:
        """Start ffmpeg for a channel if not already running."""
        # Stop existing process if any
        if channel_id in self._processes:
            self._processes[channel_id].stop()

        # Check if another worker already has this channel
        meta = self._redis.hgetall(_key(channel_id, "meta"))
        if meta and meta.get(b"active", b"0") == b"1":
            pid = int(meta.get(b"pid", b"0"))
            # Check if the PID is still alive
            try:
                os.kill(pid, 0)
                logger.info(f"[{channel_id}] ffmpeg already running (PID {pid})")
                return
            except (OSError, ProcessLookupError):
                pass  # Process is dead, start a new one

        proc = ChannelProcess(channel_id, url)
        proc.start()
        self._processes[channel_id] = proc

        # Start client monitoring thread
        self._start_cleanup_thread(channel_id)

    def stream_endpoint(self, channel_id: str, client_ip: str = "unknown") -> tuple:
        """
        Return the HLS playlist content.
        Returns (content: str, status_code: int).
        """
        # Record client activity
        self._redis.hset(_key(channel_id, "clients"), client_ip, str(time.time()))

        # Check if ffmpeg is running; re-activate if needed
        meta = self._redis.hgetall(_key(channel_id, "meta"))
        if not meta:
            return "Channel not found", 404

        url = (meta.get(b"url") or b"").decode()

        # Ensure ffmpeg is running
        self._ensure_running(channel_id, url)

        # Wait for playlist to appear
        playlist = _playlist_path(channel_id)
        deadline = time.time() + 15
        while time.time() < deadline:
            if os.path.exists(playlist) and os.path.getsize(playlist) > 20:
                break
            time.sleep(0.5)

        if not os.path.exists(playlist):
            return "Stream not ready", 503

        try:
            with open(playlist, "r") as f:
                content = f.read()

            # Rewrite segment paths to be served via our endpoint
            lines = []
            for line in content.splitlines():
                if line.endswith(".ts") and not line.startswith("#"):
                    seg_name = os.path.basename(line)
                    lines.append(f"/proxy/hls/segments/{channel_id}/{seg_name}")
                else:
                    lines.append(line)

            return "\n".join(lines), 200
        except Exception as e:
            logger.error(f"[{channel_id}] Error reading playlist: {e}")
            return "Error reading playlist", 500

    def get_segment(self, channel_id: str, segment_name: str,
                    client_ip: str = "unknown") -> tuple:
        """
        Serve a TS segment file from disk.
        Returns (data: bytes, status_code: int).
        """
        # Record client activity
        self._redis.hset(_key(channel_id, "clients"), client_ip, str(time.time()))

        seg_path = os.path.join(_channel_dir(channel_id), segment_name)
        if not os.path.exists(seg_path):
            return b"", 404

        try:
            with open(seg_path, "rb") as f:
                return f.read(), 200
        except Exception as e:
            logger.error(f"[{channel_id}] Error reading segment {segment_name}: {e}")
            return b"", 500

    def change_stream(self, channel_id: str, new_url: str) -> tuple:
        """Change source URL. Restarts ffmpeg with new source."""
        if channel_id in self._processes:
            self._processes[channel_id].stop()

        proc = ChannelProcess(channel_id, new_url)
        proc.start()
        self._processes[channel_id] = proc

        return {"message": "Stream URL updated", "channel": channel_id, "url": new_url}, 200

    def stop_channel(self, channel_id: str) -> None:
        """Stop ffmpeg and clean up."""
        proc = self._processes.pop(channel_id, None)
        if proc:
            proc.stop()
        else:
            # Clean up files even if we don't own the process
            out_dir = _channel_dir(channel_id)
            if os.path.exists(out_dir):
                shutil.rmtree(out_dir, ignore_errors=True)
            self._redis.delete(_key(channel_id, "meta"))
            self._redis.delete(_key(channel_id, "clients"))

    def shutdown(self) -> None:
        """Stop all channels."""
        for channel_id in list(self._processes.keys()):
            self.stop_channel(channel_id)

    # -- Internal --

    def _ensure_running(self, channel_id: str, source_url: str):
        """Make sure ffmpeg is running for this channel."""
        proc = self._processes.get(channel_id)
        if proc and proc.is_running():
            return

        # Check if another worker owns it
        meta = self._redis.hgetall(_key(channel_id, "meta"))
        if meta and meta.get(b"active") == b"1":
            pid = int(meta.get(b"pid", b"0"))
            try:
                os.kill(pid, 0)
                return  # Another worker's ffmpeg is running
            except (OSError, ProcessLookupError):
                pass

        # Start ffmpeg
        if source_url:
            new_proc = ChannelProcess(channel_id, source_url)
            new_proc.start()
            self._processes[channel_id] = new_proc
            self._start_cleanup_thread(channel_id)

    def _start_cleanup_thread(self, channel_id: str):
        """Monitor client activity and stop ffmpeg when no clients remain."""
        if channel_id in self._cleanup_threads:
            return

        def monitor():
            grace_end = time.time() + INITIAL_GRACE_PERIOD
            while True:
                time.sleep(CLEANUP_INTERVAL)

                proc = self._processes.get(channel_id)
                if not proc or not proc.is_running():
                    break

                # Check clients
                clients = self._redis.hgetall(_key(channel_id, "clients"))
                now = time.time()

                if not clients:
                    if now < grace_end:
                        continue
                    logger.info(f"[{channel_id}] No clients after grace period, stopping")
                    self.stop_channel(channel_id)
                    break

                # Clean up stale clients
                active = False
                for ip, ts in clients.items():
                    if now - float(ts.decode()) < CLIENT_INACTIVITY_TIMEOUT:
                        active = True
                    else:
                        self._redis.hdel(_key(channel_id, "clients"), ip)

                if not active:
                    logger.info(f"[{channel_id}] All clients inactive, stopping")
                    self.stop_channel(channel_id)
                    break

            self._cleanup_threads.pop(channel_id, None)

        t = threading.Thread(target=monitor, name=f"Cleanup-{channel_id}", daemon=True)
        t.start()
        self._cleanup_threads[channel_id] = t

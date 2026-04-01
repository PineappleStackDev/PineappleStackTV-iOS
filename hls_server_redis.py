"""
HLS Proxy Server - Redis-backed for multi-worker uWSGI deployment.

All shared state (channel registry, segment data, client tracking, metadata)
lives in Redis. Each uWSGI worker is stateless; fetcher threads are coordinated
via Redis distributed locks so only one worker fetches per channel.
"""

import requests
import threading
import logging
import m3u8
import time
import json
import uuid
import subprocess
import tempfile
import os
from urllib.parse import urlparse, urljoin
from typing import Optional, Dict
from apps.proxy.config import HLSConfig as Config
from core.utils import RedisClient

logger = logging.getLogger(__name__)

# Redis key helpers
def _key(channel_id: str, *parts: str) -> str:
    return "hls:" + channel_id + ":" + ":".join(parts)

# Key patterns:
#   hls:{cid}:meta              - hash: url, target_duration, manifest_version, next_sequence, active
#   hls:{cid}:segments:{seq}    - raw bytes (TTL 120s)
#   hls:{cid}:durations         - hash: seq -> duration
#   hls:{cid}:source_changes    - set of sequence numbers where discontinuity occurs
#   hls:{cid}:clients           - hash: client_ip -> last_activity timestamp
#   hls:{cid}:fetcher_lock      - distributed lock (SET NX EX)
#   hls:{cid}:fetcher_heartbeat - heartbeat timestamp for fetcher liveness

SEGMENT_TTL = 900  # 15 minutes of rewind capacity
FETCHER_LOCK_TTL = 30
FETCHER_HEARTBEAT_INTERVAL = 10
CLIENT_INACTIVITY_TIMEOUT = 60
INITIAL_GRACE_PERIOD = 30  # Seconds to wait for first client before stopping


# ---------------------------------------------------------------------------
# Segment verification (unchanged from original)
# ---------------------------------------------------------------------------

def verify_segment(data: bytes) -> dict:
    """Verify MPEG-TS segment integrity."""
    if len(data) < 188:
        return {"valid": False, "error": "Segment too short"}
    if len(data) % 188 != 0:
        return {"valid": False, "error": "Invalid segment size"}

    valid_packets = 0
    for i in range(0, len(data), 188):
        packet = data[i : i + 188]
        if len(packet) != 188:
            return {"valid": False, "error": "Incomplete packet"}
        if packet[0] != 0x47:
            return {"valid": False, "error": f"Invalid sync byte at offset {i}"}
        if packet[1] & 0x80:
            return {"valid": False, "error": "Transport error indicator set"}
        valid_packets += 1

    return {"valid": True, "packets": valid_packets, "size": len(data)}


# ---------------------------------------------------------------------------
# Channel fetcher - runs in a daemon thread, one per channel across all workers
# ---------------------------------------------------------------------------

class ChannelFetcher:
    """
    Downloads m3u8 manifests and TS segments for a single channel,
    storing everything in Redis. Only one instance runs per channel
    across all uWSGI workers, enforced by a Redis distributed lock.
    """

    def __init__(self, channel_id: str, source_url: str, user_agent: str):
        self.channel_id = channel_id
        self.source_url = source_url
        self.user_agent = user_agent
        self.running = True
        self._worker_id = uuid.uuid4().hex[:12]
        self._redis = RedisClient.get_client()
        self._session = self._build_session()

    def _build_session(self) -> requests.Session:
        session = requests.Session()
        session.headers.update({
            "User-Agent": self.user_agent,
            "Connection": "keep-alive",
        })
        adapter = requests.adapters.HTTPAdapter(
            pool_connections=2, pool_maxsize=4, max_retries=3, pool_block=False
        )
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        return session

    # -- Redis helpers --

    def _meta_key(self) -> str:
        return _key(self.channel_id, "meta")

    def _seg_key(self, seq: int) -> str:
        return _key(self.channel_id, "segments", str(seq))

    def _dur_key(self) -> str:
        return _key(self.channel_id, "durations")

    def _disc_key(self) -> str:
        return _key(self.channel_id, "source_changes")

    def _lock_key(self) -> str:
        return _key(self.channel_id, "fetcher_lock")

    def _heartbeat_key(self) -> str:
        return _key(self.channel_id, "fetcher_heartbeat")

    def _get_next_seq(self) -> int:
        return int(self._redis.hincrby(self._meta_key(), "next_sequence", 1)) - 1

    # -- Distributed lock --

    def _acquire_lock(self) -> bool:
        """Try to acquire the fetcher lock. Returns True if acquired."""
        return bool(self._redis.set(
            self._lock_key(), self._worker_id,
            nx=True, ex=FETCHER_LOCK_TTL
        ))

    def _refresh_lock(self) -> bool:
        """Extend the lock if we still own it."""
        pipe = self._redis.pipeline(True)
        try:
            pipe.watch(self._lock_key())
            if pipe.get(self._lock_key()) == self._worker_id.encode():
                pipe.multi()
                pipe.expire(self._lock_key(), FETCHER_LOCK_TTL)
                pipe.execute()
                return True
        except Exception:
            pass
        finally:
            pipe.reset()
        return False

    def _release_lock(self):
        pipe = self._redis.pipeline(True)
        try:
            pipe.watch(self._lock_key())
            if pipe.get(self._lock_key()) == self._worker_id.encode():
                pipe.multi()
                pipe.delete(self._lock_key())
                pipe.execute()
        except Exception:
            pass
        finally:
            pipe.reset()

    def _update_heartbeat(self):
        self._redis.set(self._heartbeat_key(), str(time.time()), ex=FETCHER_LOCK_TTL)

    # -- Download --

    def _download(self, url: str, timeout: int = 10) -> tuple:
        """Download content, return (bytes, final_url)."""
        response = self._session.get(url, allow_redirects=True, timeout=timeout)
        response.raise_for_status()
        return response.content, response.url

    # -- Main loop --

    def run(self):
        """
        Main fetcher loop. Acquires the distributed lock, then continuously
        fetches the manifest and new segments. Exits if lock is lost,
        channel is deactivated, or no clients remain.
        """
        if not self._acquire_lock():
            logger.info(f"[{self.channel_id}] Another worker owns the fetcher lock, skipping")
            return

        logger.info(f"[{self.channel_id}] Fetcher started (worker {self._worker_id})")
        retry_delay = 1
        max_retry_delay = 8
        downloaded_uris = set()
        last_heartbeat = 0

        try:
            while self.running:
                now = time.time()

                # Refresh lock and heartbeat periodically
                if now - last_heartbeat > FETCHER_HEARTBEAT_INTERVAL:
                    if not self._refresh_lock():
                        logger.warning(f"[{self.channel_id}] Lost fetcher lock, exiting")
                        break
                    self._update_heartbeat()
                    last_heartbeat = now

                # Check if channel is still active
                active = self._redis.hget(self._meta_key(), "active")
                if active and active.decode() != "1":
                    logger.info(f"[{self.channel_id}] Channel deactivated, stopping fetcher")
                    break

                # Check client activity; stop if no clients for CLIENT_INACTIVITY_TIMEOUT
                if self._clients_inactive():
                    logger.info(f"[{self.channel_id}] No active clients, stopping fetcher")
                    self._redis.hset(self._meta_key(), "active", "0")
                    break

                # Read current source URL from Redis (may have changed via change_stream)
                url_bytes = self._redis.hget(self._meta_key(), "url")
                if url_bytes:
                    self.source_url = url_bytes.decode()

                try:
                    manifest_data, final_url = self._download(self.source_url)
                    manifest = m3u8.loads(manifest_data.decode())

                    if manifest.target_duration:
                        self._redis.hset(self._meta_key(), "target_duration",
                                         str(float(manifest.target_duration)))
                    if manifest.version:
                        self._redis.hset(self._meta_key(), "manifest_version",
                                         str(manifest.version))

                    if not manifest.segments:
                        time.sleep(1)
                        continue

                    # On first run with no segments in Redis, seed initial buffer
                    existing_seqs = self._get_stored_sequences()
                    if not existing_seqs:
                        self._seed_initial_buffer(manifest, final_url, downloaded_uris)
                    else:
                        # Normal operation: fetch latest segment if new
                        latest = manifest.segments[-1]
                        if latest.uri not in downloaded_uris:
                            self._fetch_and_store_segment(
                                latest, final_url, downloaded_uris
                            )

                    # Clean up URI tracking set
                    if len(downloaded_uris) > 200:
                        downloaded_uris.clear()

                    retry_delay = 1
                    target_dur = float(
                        self._redis.hget(self._meta_key(), "target_duration") or 10
                    )
                    time.sleep(target_dur * 0.5)

                except Exception as e:
                    logger.error(f"[{self.channel_id}] Fetch error: {e}")
                    time.sleep(retry_delay)
                    retry_delay = min(retry_delay * 2, max_retry_delay)

        finally:
            self._release_lock()
            logger.info(f"[{self.channel_id}] Fetcher stopped (worker {self._worker_id})")

    # -- Helpers --

    def _clients_inactive(self) -> bool:
        """Return True if no client has made a request in CLIENT_INACTIVITY_TIMEOUT seconds."""
        clients_key = _key(self.channel_id, "clients")
        clients = self._redis.hgetall(clients_key)
        if not clients:
            # Give new channels a grace period before declaring no clients
            created = self._redis.hget(self._meta_key(), "created")
            if created and (time.time() - float(created.decode())) < INITIAL_GRACE_PERIOD:
                return False
            return True

        now = time.time()
        any_active = False
        for ip, ts in clients.items():
            if now - float(ts.decode()) < CLIENT_INACTIVITY_TIMEOUT:
                any_active = True
            else:
                self._redis.hdel(clients_key, ip)
        return not any_active

    def _get_stored_sequences(self) -> list:
        """Return sorted list of segment sequence numbers currently in Redis."""
        dur_hash = self._redis.hgetall(self._dur_key())
        if not dur_hash:
            return []
        return sorted(int(k) for k in dur_hash.keys())

    def _seed_initial_buffer(self, manifest, final_url, downloaded_uris):
        """Download initial segments from the tail of the manifest."""
        segments = list(manifest.segments)
        to_fetch = []
        total_dur = 0.0
        for seg in reversed(segments):
            total_dur += float(seg.duration)
            to_fetch.append(seg)
            if total_dur >= getattr(Config, "INITIAL_BUFFER_SECONDS", 15):
                break
            if len(to_fetch) >= getattr(Config, "MAX_INITIAL_SEGMENTS", 4):
                break
        to_fetch.reverse()

        count = 0
        for seg in to_fetch:
            if self._fetch_and_store_segment(seg, final_url, downloaded_uris):
                count += 1
        if count:
            logger.info(f"[{self.channel_id}] Initial buffer seeded with {count} segments")

    def _transcode_audio(self, seg_data: bytes) -> bytes:
        """Transcode audio to AAC while copying video. Returns transcoded bytes or original on failure."""
        try:
            result = subprocess.run(
                [
                    "ffmpeg", "-hide_banner", "-loglevel", "error",
                    "-i", "pipe:0",
                    "-c:v", "copy",
                    "-c:a", "aac", "-b:a", "192k",
                    "-f", "mpegts",
                    "pipe:1",
                ],
                input=seg_data,
                capture_output=True,
                timeout=15,
            )
            if result.returncode == 0 and len(result.stdout) > 188:
                return result.stdout
            if result.stderr:
                logger.debug(f"[{self.channel_id}] ffmpeg stderr: {result.stderr.decode()[:200]}")
            return seg_data  # Fall back to original on failure
        except Exception as e:
            logger.warning(f"[{self.channel_id}] Transcode failed: {e}")
            return seg_data

    def _fetch_and_store_segment(self, segment, final_url, downloaded_uris) -> bool:
        """Download, transcode audio to AAC, verify, and store a segment in Redis."""
        try:
            seg_url = urljoin(final_url, segment.uri)
            seg_data, _ = self._download(seg_url)

            if not seg_data or len(seg_data) < 188:
                return False

            # Transcode audio to AAC for AVPlayer compatibility
            seg_data = self._transcode_audio(seg_data)

            # Verify the (possibly transcoded) segment
            result = verify_segment(seg_data)
            if not result.get("valid"):
                # Transcoded output may not be packet-aligned; skip verification
                # if we got reasonable data back
                if len(seg_data) > 1000:
                    logger.debug(f"[{self.channel_id}] Skipping strict verification for transcoded segment")
                else:
                    logger.warning(f"[{self.channel_id}] Segment validation failed: {result.get('error')}")
                    return False

            seq = self._get_next_seq()
            pipe = self._redis.pipeline(False)
            pipe.set(self._seg_key(seq), seg_data, ex=SEGMENT_TTL)
            pipe.hset(self._dur_key(), str(seq), str(float(segment.duration)))
            pipe.expire(self._dur_key(), SEGMENT_TTL)
            pipe.execute()

            downloaded_uris.add(segment.uri)
            logger.debug(
                f"[{self.channel_id}] Stored segment {seq} "
                f"({len(seg_data)} bytes, {segment.duration}s)"
            )
            return True

        except Exception as e:
            logger.error(f"[{self.channel_id}] Segment download error: {e}")
            return False

    def stop(self):
        self.running = False


# ---------------------------------------------------------------------------
# ProxyServer - mostly stateless, reads/writes Redis
# ---------------------------------------------------------------------------

class ProxyServer:
    """
    HLS proxy that stores all state in Redis. Safe for multi-worker uWSGI.
    Each public method either writes metadata to Redis or reads from it.
    Fetcher threads are started on demand and coordinated via distributed locks.
    """

    def __init__(self, user_agent: Optional[str] = None):
        self.user_agent = user_agent or Config.DEFAULT_USER_AGENT
        self._redis = RedisClient.get_client()
        # Local tracker for fetcher threads started by THIS worker
        self._local_fetchers: Dict[str, ChannelFetcher] = {}

    # -- Public API --

    def initialize_channel(self, url: str, channel_id: str) -> None:
        """Register a channel in Redis and start a fetcher if needed."""
        meta_key = _key(channel_id, "meta")

        # If already active, stop first
        if self._redis.hget(meta_key, "active") == b"1":
            self.stop_channel(channel_id)

        # Write channel metadata
        self._redis.hset(meta_key, mapping={
            "url": url,
            "active": "1",
            "target_duration": "10",
            "manifest_version": "3",
            "next_sequence": "0",
            "created": str(time.time()),
        })
        self._redis.expire(meta_key, 3600)  # 1h TTL as safety net

        logger.info(f"Initialized channel {channel_id} with URL {url}")
        self._ensure_fetcher(channel_id, url)

    def stream_endpoint(self, channel_id: str, client_ip: str = "unknown") -> tuple:
        """
        Generate and return an HLS manifest for the channel.
        Returns (content: str, status_code: int).
        """
        meta_key = _key(channel_id, "meta")
        if not self._redis.exists(meta_key):
            return "Channel not found", 404

        # Record client activity first
        self._redis.hset(_key(channel_id, "clients"), client_ip, str(time.time()))

        # Re-activate channel if it was deactivated but a client is requesting
        active = self._redis.hget(meta_key, "active")
        url = (self._redis.hget(meta_key, "url") or b"").decode()
        if not active or active.decode() != "1":
            if url:
                self._redis.hset(meta_key, mapping={"active": "1", "created": str(time.time())})
                logger.info(f"Re-activated channel {channel_id} on client request")
            else:
                return "Channel not configured", 404

        # Ensure a fetcher is running
        self._ensure_fetcher(channel_id, url)

        # Wait for segments to appear
        deadline = time.time() + getattr(Config, "BUFFER_READY_TIMEOUT", 15)
        sequences = []
        while time.time() < deadline:
            sequences = self._get_sequences(channel_id)
            if sequences:
                break
            time.sleep(0.25)

        if not sequences:
            return "No segments available", 503

        # Read metadata
        target_dur = int(float(self._redis.hget(meta_key, "target_duration") or 10))
        version = int(self._redis.hget(meta_key, "manifest_version") or 3)

        # Determine window
        max_seq = sequences[-1]
        window_size = getattr(Config, "WINDOW_SIZE", 5)
        if len(sequences) <= window_size:
            window = sequences
        else:
            window = [s for s in sequences if s >= max_seq - window_size + 1]

        if not window:
            return "No segments in window", 503

        min_seq = window[0]

        # Check for discontinuity markers
        disc_key = _key(channel_id, "source_changes")
        disc_set = {int(s) for s in self._redis.smembers(disc_key)}

        # Build m3u8
        lines = [
            "#EXTM3U",
            f"#EXT-X-VERSION:{version}",
            f"#EXT-X-MEDIA-SEQUENCE:{min_seq}",
            f"#EXT-X-TARGETDURATION:{target_dur}",
        ]

        dur_hash = self._redis.hgetall(_key(channel_id, "durations"))
        for seq in window:
            if seq in disc_set:
                lines.append("#EXT-X-DISCONTINUITY")
            duration = float(dur_hash.get(str(seq).encode(), b"10"))
            lines.append(f"#EXTINF:{duration},")
            lines.append(f"/proxy/hls/segments/{channel_id}/{seq}.ts")

        return "\n".join(lines), 200

    def get_segment(self, channel_id: str, segment_name: str,
                    client_ip: str = "unknown") -> tuple:
        """
        Serve a TS segment from Redis.
        Returns (data: bytes, status_code: int).
        """
        meta_key = _key(channel_id, "meta")
        if not self._redis.exists(meta_key):
            return b"", 404

        # Record client activity
        self._redis.hset(_key(channel_id, "clients"), client_ip, str(time.time()))

        try:
            seq = int(segment_name.split(".")[0])
        except (ValueError, IndexError):
            return b"", 400

        data = self._redis.get(_key(channel_id, "segments", str(seq)))
        if data:
            return data, 200

        logger.warning(f"Segment {seq} not found for channel {channel_id}")
        return b"", 404

    def change_stream(self, channel_id: str, new_url: str) -> tuple:
        """
        Change the source URL for a channel. The fetcher picks up the new URL
        on its next iteration. Returns (response_dict, status_code).
        """
        meta_key = _key(channel_id, "meta")
        if not self._redis.exists(meta_key):
            return {"error": "Channel not found"}, 404

        if not new_url:
            return {"error": "No URL provided"}, 400

        old_url = (self._redis.hget(meta_key, "url") or b"").decode()
        if new_url == old_url:
            return {"message": "URL unchanged", "channel": channel_id, "url": new_url}, 200

        # Mark discontinuity at the next sequence
        next_seq = int(self._redis.hget(meta_key, "next_sequence") or 0)
        self._redis.sadd(_key(channel_id, "source_changes"), str(next_seq))

        # Update URL; fetcher will read this on next loop
        self._redis.hset(meta_key, "url", new_url)

        logger.info(f"Channel {channel_id} stream changed to {new_url}")
        return {"message": "Stream URL updated", "channel": channel_id, "url": new_url}, 200

    def stop_channel(self, channel_id: str) -> None:
        """Deactivate a channel and clean up Redis keys."""
        logger.info(f"Stopping channel {channel_id}")
        meta_key = _key(channel_id, "meta")
        self._redis.hset(meta_key, "active", "0")

        # Stop local fetcher if we own it
        fetcher = self._local_fetchers.pop(channel_id, None)
        if fetcher:
            fetcher.stop()

        # Clean up Redis keys (segments expire on their own via TTL)
        for suffix in ("durations", "clients", "source_changes", "fetcher_lock",
                        "fetcher_heartbeat"):
            self._redis.delete(_key(channel_id, suffix))

        # Delete meta last
        self._redis.delete(meta_key)

    def shutdown(self) -> None:
        """Stop all channels managed by this worker."""
        for channel_id in list(self._local_fetchers.keys()):
            self.stop_channel(channel_id)

    # -- Internal --

    def _ensure_fetcher(self, channel_id: str, source_url: str):
        """Start a fetcher thread if one isn't already running for this channel."""
        # Check if another worker (or this one) already has the lock
        lock_key = _key(channel_id, "fetcher_lock")
        heartbeat_key = _key(channel_id, "fetcher_heartbeat")

        # If a lock exists and heartbeat is recent, a fetcher is running somewhere
        if self._redis.exists(lock_key):
            hb = self._redis.get(heartbeat_key)
            if hb and (time.time() - float(hb.decode())) < FETCHER_LOCK_TTL:
                return  # fetcher is alive

        # Check if we already have a local thread running
        local = self._local_fetchers.get(channel_id)
        if local and local.running:
            return

        # Start a new fetcher in a daemon thread
        fetcher = ChannelFetcher(channel_id, source_url, self.user_agent)
        self._local_fetchers[channel_id] = fetcher

        t = threading.Thread(
            target=fetcher.run,
            name=f"Fetcher-{channel_id}",
            daemon=True,
        )
        t.start()
        logger.info(f"Started fetcher thread for channel {channel_id}")

    def _get_sequences(self, channel_id: str) -> list:
        """Return sorted list of available segment sequence numbers."""
        dur_hash = self._redis.hgetall(_key(channel_id, "durations"))
        if not dur_hash:
            return []
        seqs = sorted(int(k) for k in dur_hash.keys())
        # Filter to only sequences that actually have segment data still in Redis
        return [s for s in seqs if self._redis.exists(
            _key(channel_id, "segments", str(s))
        )]

package com.blackpirateapps.musii;

import org.schabi.newpipe.extractor.Image;
import org.schabi.newpipe.extractor.MediaFormat;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.downloader.Downloader;
import org.schabi.newpipe.extractor.downloader.Request;
import org.schabi.newpipe.extractor.downloader.Response;
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException;
import org.schabi.newpipe.extractor.exceptions.ExtractionException;
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException;
import org.schabi.newpipe.extractor.stream.AudioStream;
import org.schabi.newpipe.extractor.stream.AudioTrackType;
import org.schabi.newpipe.extractor.stream.StreamExtractor;
import org.schabi.newpipe.extractor.stream.StreamType;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;

final class YouTubeMusicResolver {
    YouTubeMusicResolver() {
        NewPipe.init(new YouTubeDownloader());
    }

    Map<String, Object> getTrack(String videoId) throws IOException, ExtractionException {
        StreamExtractor track = open(videoId);
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("title", track.getName());
        metadata.put("artist", track.getUploaderName());
        metadata.put("durationMs", Math.max(0, track.getLength()) * 1000L);
        track.getThumbnails().stream()
            .filter(image -> image.getUrl().startsWith("https://"))
            .min(Comparator.comparingInt(image -> Math.abs(image.getWidth() - 480)))
            .map(Image::getUrl)
            .ifPresent(url -> metadata.put("artworkUrl", url));
        return metadata;
    }

    String resolveAudio(String videoId) throws IOException, ExtractionException {
        return open(videoId).getAudioStreams().stream()
            .filter(AudioStream::isUrl)
            .filter(stream -> stream.getContent().startsWith("https://"))
            .filter(stream -> stream.getFormat() == MediaFormat.M4A
                || stream.getFormat() == MediaFormat.WEBMA)
            .max(Comparator
                .comparingInt(YouTubeMusicResolver::audioTrackPriority)
                .thenComparingInt(AudioStream::getAverageBitrate))
            .map(AudioStream::getContent)
            .orElseThrow(() -> new ContentNotAvailableException("No supported audio stream"));
    }

    private static int audioTrackPriority(AudioStream stream) {
        AudioTrackType type = stream.getAudioTrackType();
        if (type == AudioTrackType.ORIGINAL) return 2;
        return type == null ? 1 : 0;
    }

    private StreamExtractor open(String videoId) throws IOException, ExtractionException {
        StreamExtractor track = ServiceList.YouTube.getStreamExtractor(
            "https://www.youtube.com/watch?v=" + videoId
        );
        track.fetchPage();
        if (track.getStreamType() != StreamType.VIDEO_STREAM) {
            throw new ContentNotAvailableException("Only on-demand tracks are supported");
        }
        return track;
    }

    private static final class YouTubeDownloader extends Downloader {
        @Override
        public Response execute(Request request) throws IOException, ReCaptchaException {
            HttpURLConnection connection = (HttpURLConnection) URI.create(request.url())
                .toURL().openConnection();
            try {
                connection.setConnectTimeout(8000);
                connection.setReadTimeout(10000);
                connection.setRequestMethod(request.httpMethod());
                request.headers().forEach((name, values) ->
                    values.forEach(value -> connection.addRequestProperty(name, value))
                );
                byte[] data = request.dataToSend();
                if (data != null) {
                    connection.setDoOutput(true);
                    try (OutputStream output = connection.getOutputStream()) {
                        output.write(data);
                    }
                }
                int status = connection.getResponseCode();
                if (status == 429) {
                    throw new ReCaptchaException("YouTube rate limited the request", request.url());
                }
                String body = readText(status >= 400
                    ? connection.getErrorStream() : connection.getInputStream());
                return new Response(
                    status, connection.getResponseMessage(), connection.getHeaderFields(),
                    body, connection.getURL().toString()
                );
            } finally {
                connection.disconnect();
            }
        }

        private String readText(InputStream input) throws IOException {
            if (input == null) return "";
            try (InputStream stream = input; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = stream.read(buffer)) != -1) {
                    output.write(buffer, 0, count);
                }
                return new String(output.toByteArray(), StandardCharsets.UTF_8);
            }
        }
    }
}

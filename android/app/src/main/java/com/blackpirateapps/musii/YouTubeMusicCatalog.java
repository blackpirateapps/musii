package com.blackpirateapps.musii;

import com.grack.nanojson.JsonArray;
import com.grack.nanojson.JsonObject;
import com.grack.nanojson.JsonParser;
import com.grack.nanojson.JsonParserException;
import com.grack.nanojson.JsonWriter;
import org.schabi.newpipe.extractor.InfoItem;
import org.schabi.newpipe.extractor.ListExtractor.InfoItemsPage;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.Page;
import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.exceptions.ExtractionException;
import org.schabi.newpipe.extractor.exceptions.ParsingException;
import org.schabi.newpipe.extractor.localization.ContentCountry;
import org.schabi.newpipe.extractor.search.SearchExtractor;
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper;
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory;
import org.schabi.newpipe.extractor.stream.StreamInfoItem;
import org.schabi.newpipe.extractor.stream.StreamType;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

final class YouTubeMusicCatalog {
    private static final Pattern VIDEO_ID = Pattern.compile("[A-Za-z0-9_-]{11}");

    Map<String, Object> searchSongs(String query, String nextPage)
            throws IOException, ExtractionException {
        if (query.trim().isEmpty()) {
            return Collections.singletonMap("tracks", Collections.emptyList());
        }

        SearchExtractor search = ServiceList.YouTube.getSearchExtractor(
            query, Collections.singletonList(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS), ""
        );
        search.forceContentCountry(new ContentCountry(country()));
        InfoItemsPage<InfoItem> page;
        if (nextPage == null) {
            search.fetchPage();
            page = search.getInitialPage();
        } else {
            URI uri = URI.create(nextPage);
            if (!"https".equals(uri.getScheme()) || !"music.youtube.com".equals(uri.getAuthority())
                    || !"/youtubei/v1/search".equals(uri.getPath())) {
                throw new IllegalArgumentException("Invalid search continuation");
            }
            page = search.getPage(new Page(nextPage));
        }

        List<Map<String, Object>> tracks = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (InfoItem item : page.getItems()) {
            if (!(item instanceof StreamInfoItem)) continue;
            StreamInfoItem song = (StreamInfoItem) item;
            if (song.getStreamType() != StreamType.VIDEO_STREAM) continue;
            String id = ServiceList.YouTube.getStreamLHFactory().getId(song.getUrl());
            if (!VIDEO_ID.matcher(id).matches() || !seen.add(id)) continue;
            tracks.add(song(id, song.getName(), song.getUploaderName(),
                YouTubeMusicResolver.artworkUrl(song.getThumbnails()), song.getDuration()));
        }

        Map<String, Object> result = new HashMap<>();
        result.put("tracks", tracks);
        if (page.hasNextPage()) result.put("nextPage", page.getNextPage().getUrl());
        return result;
    }

    Map<String, Object> getHome() throws IOException, ExtractionException {
        List<Map<String, Object>> sections = loadShelves("FEmusic_home");
        if (sections.isEmpty()) {
            // Some regions show only playlists on the signed-out home page.
            sections = loadShelves("FEmusic_explore");
        }
        return Collections.singletonMap("sections", sections);
    }

    private List<Map<String, Object>> loadShelves(String browseId)
            throws IOException, ExtractionException {
        String body = JsonWriter.string()
            .object()
                .object("context")
                    .object("client")
                        .value("clientName", "WEB_REMIX")
                        .value("clientVersion", YoutubeParsingHelper.getYoutubeMusicClientVersion())
                        .value("hl", Locale.getDefault().getLanguage())
                        .value("gl", country())
                        .value("platform", "DESKTOP")
                    .end()
                .end()
                .value("browseId", browseId)
            .end().done();
        String response = YoutubeParsingHelper.getValidJsonResponseBody(
            NewPipe.getDownloader().postWithContentTypeJson(
                "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                YoutubeParsingHelper.getYoutubeMusicHeaders(),
                body.getBytes(StandardCharsets.UTF_8)
            )
        );
        try {
            JsonObject browse = JsonParser.object().from(response).getObject("contents");
            List<Map<String, Object>> sections = new ArrayList<>();
            for (String layout : new String[] {
                "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer"
            }) {
                for (Object tab : browse.getObject(layout).getArray("tabs")) {
                    if (!(tab instanceof JsonObject)) continue;
                    JsonObject sectionList = ((JsonObject) tab).getObject("tabRenderer")
                        .getObject("content").getObject("sectionListRenderer");
                    collectShelves(sectionList.getArray("contents"), sections);
                }
            }
            collectShelves(browse.getObject("twoColumnBrowseResultsRenderer")
                .getObject("secondaryContents").getObject("sectionListRenderer")
                .getArray("contents"), sections);
            return sections;
        } catch (JsonParserException error) {
            throw new ParsingException("Could not read YouTube Music home", error);
        }
    }

    private void collectShelves(JsonArray contents, List<Map<String, Object>> sections) {
        for (Object entry : contents) {
            if (!(entry instanceof JsonObject)) continue;
            JsonObject section = (JsonObject) entry;
            JsonObject shelf = section.getObject("musicCarouselShelfRenderer");
            JsonObject title = shelf.getObject("header")
                .getObject("musicCarouselShelfBasicHeaderRenderer").getObject("title");
            if (shelf.isEmpty()) {
                shelf = section.getObject("musicShelfRenderer");
                title = shelf.getObject("title");
            }
            List<Map<String, Object>> tracks = new ArrayList<>();
            Set<String> seen = new HashSet<>();
            for (Object item : shelf.getArray("contents")) {
                if (!(item instanceof JsonObject)) continue;
                Map<String, Object> track = shelfSong((JsonObject) item);
                if (track != null && seen.add((String) track.get("videoId"))) tracks.add(track);
            }
            if (!tracks.isEmpty()) {
                Map<String, Object> result = new HashMap<>();
                result.put("title", text(title));
                result.put("tracks", tracks);
                sections.add(result);
            }
        }
    }

    private Map<String, Object> shelfSong(JsonObject item) {
        JsonObject row = item.getObject("musicResponsiveListItemRenderer");
        String id;
        JsonObject title;
        JsonObject subtitle;
        JsonObject thumbnail;
        if (!row.isEmpty()) {
            id = row.getObject("playlistItemData").getString("videoId", "");
            JsonArray columns = row.getArray("flexColumns");
            title = column(columns, 0);
            subtitle = column(columns, 1);
            thumbnail = row.getObject("thumbnail");
        } else {
            row = item.getObject("musicTwoRowItemRenderer");
            id = row.getObject("navigationEndpoint").getObject("watchEndpoint")
                .getString("videoId", "");
            title = row.getObject("title");
            subtitle = row.getObject("subtitle");
            thumbnail = row.getObject("thumbnailRenderer");
        }
        if (id.isEmpty()) {
            for (Object run : title.getArray("runs")) {
                if (!(run instanceof JsonObject)) continue;
                id = ((JsonObject) run).getObject("navigationEndpoint")
                    .getObject("watchEndpoint").getString("videoId", "");
                if (!id.isEmpty()) break;
            }
        }
        String name = text(title);
        if (!VIDEO_ID.matcher(id).matches() || name.trim().isEmpty()) return null;
        JsonArray images = thumbnail.getObject("musicThumbnailRenderer")
            .getObject("thumbnail").getArray("thumbnails");
        String artwork = images.isEmpty() ? null
            : images.getObject(images.size() - 1).getString("url", null);
        String[] subtitleParts = text(subtitle).split(" • ", -1);
        long duration = 0;
        JsonArray fixed = row.getArray("fixedColumns");
        if (!fixed.isEmpty()) {
            duration = durationSeconds(text(fixed.getObject(0)
                .getObject("musicResponsiveListItemFixedColumnRenderer").getObject("text")));
        }
        if (duration == 0) duration = durationSeconds(subtitleParts[subtitleParts.length - 1]);
        return song(id, name, subtitleParts[0], artwork, duration);
    }

    private static JsonObject column(JsonArray columns, int index) {
        return index < columns.size() ? columns.getObject(index)
            .getObject("musicResponsiveListItemFlexColumnRenderer").getObject("text")
            : new JsonObject();
    }

    private static String text(JsonObject text) {
        StringBuilder result = new StringBuilder();
        for (Object run : text.getArray("runs")) {
            if (run instanceof JsonObject) result.append(((JsonObject) run).getString("text", ""));
        }
        return result.length() == 0 ? text.getString("simpleText", "") : result.toString();
    }

    private static long durationSeconds(String text) {
        if (!text.matches("[0-9]{1,3}(?::[0-9]{2}){1,2}")) return 0;
        long seconds = 0;
        for (String part : text.split(":")) seconds = seconds * 60 + Integer.parseInt(part);
        return seconds;
    }

    private static Map<String, Object> song(String id, String title, String artist,
                                            String artwork, long seconds) {
        Map<String, Object> item = new HashMap<>();
        item.put("videoId", id);
        item.put("title", title);
        item.put("artist", artist);
        item.put("artworkUrl", artwork);
        item.put("durationMs", Math.max(0, seconds) * 1000L);
        return item;
    }

    private static String country() {
        String country = Locale.getDefault().getCountry();
        return country.isEmpty() ? "US" : country;
    }
}

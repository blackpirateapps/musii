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
import org.schabi.newpipe.extractor.channel.ChannelInfoItem;
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem;
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
    private static final Pattern BROWSE_ID = Pattern.compile("(?:UC|VL|MPRE)[A-Za-z0-9_-]{8,180}");
    private static final String[] CATEGORIES = {"songs", "albums", "artists", "playlists"};

    Map<String, Object> searchSongs(String query, String nextPage)
            throws IOException, ExtractionException {
        return search(query, "songs", nextPage);
    }

    Map<String, Object> search(String query, String kind, String nextPage)
            throws IOException, ExtractionException {
        if (query.trim().isEmpty()) {
            return Collections.singletonMap("tracks", Collections.emptyList());
        }

        String filter = switch (kind) {
            case "songs" -> YoutubeSearchQueryHandlerFactory.MUSIC_SONGS;
            case "albums" -> YoutubeSearchQueryHandlerFactory.MUSIC_ALBUMS;
            case "artists" -> YoutubeSearchQueryHandlerFactory.MUSIC_ARTISTS;
            case "playlists" -> YoutubeSearchQueryHandlerFactory.MUSIC_PLAYLISTS;
            default -> throw new IllegalArgumentException("Invalid music filter");
        };
        SearchExtractor search = ServiceList.YouTube.getSearchExtractor(
            query, Collections.singletonList(filter), ""
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
        List<Map<String, Object>> collections = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (InfoItem item : page.getItems()) {
            if (item instanceof StreamInfoItem song && song.getStreamType() == StreamType.VIDEO_STREAM) {
                String id = ServiceList.YouTube.getStreamLHFactory().getId(song.getUrl());
                if (!VIDEO_ID.matcher(id).matches() || !seen.add(id)) continue;
                tracks.add(song(id, song.getName(), song.getUploaderName(),
                    YouTubeMusicResolver.artworkUrl(song.getThumbnails()), song.getDuration()));
            } else {
                Map<String, Object> collection = searchCollection(item, kind);
                if (collection != null && seen.add((String) collection.get("browseId"))) {
                    collections.add(collection);
                }
            }
        }

        Map<String, Object> result = new HashMap<>();
        result.put("tracks", tracks);
        result.put("collections", collections);
        if (page.hasNextPage()) result.put("nextPage", page.getNextPage().getUrl());
        return result;
    }

    private Map<String, Object> searchCollection(InfoItem item, String kind) {
        URI uri = URI.create(item.getUrl());
        String id;
        String subtitle = null;
        if (item instanceof ChannelInfoItem && "artists".equals(kind)) {
            String path = uri.getPath();
            id = path == null ? "" : path.substring(path.lastIndexOf('/') + 1);
        } else if (item instanceof PlaylistInfoItem playlist) {
            String query = uri.getQuery();
            if (query == null || !query.startsWith("list=")) return null;
            id = "VL" + query.substring(5);
            subtitle = playlist.getUploaderName();
        } else {
            return null;
        }
        return collection(kind, id, item.getName(), subtitle,
            YouTubeMusicResolver.artworkUrl(item.getThumbnails()));
    }

    Map<String, Object> getHome() throws IOException, ExtractionException {
        List<Map<String, Object>> sections = readShelves(browse("FEmusic_home", null));
        Set<String> missing = missingCategories(sections);
        if (!missing.isEmpty()) addHomeShelves(sections, "FEmusic_explore", missing);
        missing = missingCategories(sections);
        if (!missing.isEmpty()) addHomeShelves(sections, "FEmusic_charts", missing);
        return Collections.singletonMap("sections", sections);
    }

    // Later feeds supplement Home when a country gets no recommendations for a category.
    private void addHomeShelves(List<Map<String, Object>> sections, String id, Set<String> missing)
            throws IOException, ExtractionException {
        try {
            for (Map<String, Object> shelf : readShelves(browse(id, null))) {
                if (missing.stream().anyMatch(kind -> hasCategory(shelf, kind))) sections.add(shelf);
            }
        } catch (IOException | ExtractionException error) {
            if (sections.isEmpty()) throw error;
        }
    }

    private static Set<String> missingCategories(List<Map<String, Object>> sections) {
        Set<String> missing = new HashSet<>();
        for (String kind : CATEGORIES) {
            if (sections.stream().noneMatch(shelf -> hasCategory(shelf, kind))) missing.add(kind);
        }
        return missing;
    }

    private static boolean hasCategory(Map<String, Object> shelf, String kind) {
        if ("songs".equals(kind)) return !((List<?>) shelf.get("tracks")).isEmpty();
        return ((List<?>) shelf.get("collections")).stream().anyMatch(
            item -> kind.equals(((Map<?, ?>) item).get("kind"))
        );
    }

    Map<String, Object> getCollection(String browseId, String continuation)
            throws IOException, ExtractionException {
        if (!BROWSE_ID.matcher(browseId).matches()) {
            throw new IllegalArgumentException("Invalid music browse ID");
        }
        JsonObject response = browse(browseId, continuation);
        List<Map<String, Object>> sections = readShelves(response);
        Map<String, Object> result = new HashMap<>();
        result.put("sections", sections);
        String next = continuation(response);
        if (!next.isEmpty()) result.put("nextPage", next);
        return result;
    }

    Map<String, Object> getLyrics(String videoId) throws IOException, ExtractionException {
        JsonObject next = request("next", "videoId", videoId, null);
        JsonArray tabs = next.getObject("contents")
            .getObject("singleColumnMusicWatchNextResultsRenderer")
            .getObject("tabbedRenderer").getObject("watchNextTabbedResultsRenderer")
            .getArray("tabs");
        if (tabs.size() < 2) return Collections.emptyMap();
        JsonObject endpoint = tabs.getObject(1).getObject("tabRenderer")
            .getObject("endpoint").getObject("browseEndpoint");
        String lyricsId = endpoint.getString("browseId", "");
        if (lyricsId.isEmpty()) return Collections.emptyMap();
        JsonArray sections = request("browse", "browseId", lyricsId, null,
            endpoint.getString("params", null)).getObject("contents")
            .getObject("sectionListRenderer").getArray("contents");
        for (Object value : sections) {
            if (!(value instanceof JsonObject section)) continue;
            String lyrics = text(section.getObject("musicDescriptionShelfRenderer").getObject("description"));
            if (!lyrics.trim().isEmpty()) return Collections.singletonMap("lyrics", lyrics);
        }
        return Collections.emptyMap();
    }

    private JsonObject browse(String browseId, String continuation)
            throws IOException, ExtractionException {
        return continuation == null ? request("browse", "browseId", browseId, null)
            : request("browse", "continuation", continuation, continuation);
    }

    private JsonObject request(String endpoint, String key, String value, String continuation)
            throws IOException, ExtractionException {
        return request(endpoint, key, value, continuation, null);
    }

    private JsonObject request(String endpoint, String key, String value, String continuation,
                               String params) throws IOException, ExtractionException {
        var body = JsonWriter.string()
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
            .value(key, value);
        if (params != null) body.value("params", params);
        String url = "https://music.youtube.com/youtubei/v1/" + endpoint + "?prettyPrint=false";
        if (continuation != null) {
            String encoded = java.net.URLEncoder.encode(continuation, "UTF-8");
            url += "&ctoken=" + encoded + "&continuation=" + encoded;
        }
        String response = YoutubeParsingHelper.getValidJsonResponseBody(
            NewPipe.getDownloader().postWithContentTypeJson(
                url, YoutubeParsingHelper.getYoutubeMusicHeaders(),
                body.end().done().getBytes(StandardCharsets.UTF_8)
            )
        );
        try {
            return JsonParser.object().from(response);
        } catch (JsonParserException error) {
            throw new ParsingException("Could not read YouTube Music " + endpoint, error);
        }
    }

    private List<Map<String, Object>> readShelves(JsonObject response) {
        JsonObject contents = response.getObject("contents");
        List<Map<String, Object>> sections = new ArrayList<>();
        collectShelves(contents.getObject("sectionListRenderer").getArray("contents"), sections);
        for (String layout : new String[] {
            "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer"
        }) {
            for (Object tab : contents.getObject(layout).getArray("tabs")) {
                if (!(tab instanceof JsonObject object)) continue;
                collectShelves(object.getObject("tabRenderer").getObject("content")
                    .getObject("sectionListRenderer").getArray("contents"), sections);
            }
        }
        collectShelves(contents.getObject("twoColumnBrowseResultsRenderer")
            .getObject("secondaryContents").getObject("sectionListRenderer")
            .getArray("contents"), sections);
        JsonObject continuation = response.getObject("continuationContents");
        collectShelves(continuation.getObject("sectionListContinuation")
            .getArray("contents"), sections);
        for (String type : new String[] {"musicPlaylistShelfContinuation", "musicShelfContinuation"}) {
            addShelf("", continuation.getObject(type).getArray("contents"), sections);
        }
        for (Object action : response.getArray("onResponseReceivedActions")) {
            if (action instanceof JsonObject object) {
                addShelf("", object.getObject("appendContinuationItemsAction")
                    .getArray("continuationItems"), sections);
            }
        }
        return sections;
    }

    private String continuation(Object item) {
        if (item instanceof JsonObject object) {
            String token = object.getObject("nextContinuationData").getString("continuation", "");
            if (token.isEmpty()) token = object.getObject("continuationItemRenderer")
                .getObject("continuationEndpoint").getObject("continuationCommand")
                .getString("token", "");
            if (!token.isEmpty()) return token;
            for (Object value : object.values()) {
                token = continuation(value);
                if (!token.isEmpty()) return token;
            }
        } else if (item instanceof JsonArray array) {
            for (Object value : array) {
                String token = continuation(value);
                if (!token.isEmpty()) return token;
            }
        }
        return "";
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
            if (shelf.isEmpty()) shelf = section.getObject("musicPlaylistShelfRenderer");
            addShelf(text(title), shelf.getArray("contents"), sections);
        }
    }

    private void addShelf(String title, JsonArray items, List<Map<String, Object>> sections) {
        List<Map<String, Object>> tracks = new ArrayList<>();
        List<Map<String, Object>> collections = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (Object value : items) {
            if (!(value instanceof JsonObject item)) continue;
            Map<String, Object> track = shelfSong(item);
            if (track != null && seen.add((String) track.get("videoId"))) tracks.add(track);
            Map<String, Object> collection = shelfCollection(item);
            if (collection != null && seen.add((String) collection.get("browseId"))) {
                collections.add(collection);
            }
        }
        if (tracks.isEmpty() && collections.isEmpty()) return;
        Map<String, Object> result = new HashMap<>();
        result.put("title", title);
        result.put("tracks", tracks);
        result.put("collections", collections);
        sections.add(result);
    }

    private Map<String, Object> shelfCollection(JsonObject item) {
        JsonObject row = item.getObject("musicResponsiveListItemRenderer");
        boolean responsive = !row.isEmpty();
        if (!responsive) row = item.getObject("musicTwoRowItemRenderer");
        JsonObject endpoint = row.getObject("navigationEndpoint").getObject("browseEndpoint");
        JsonObject title = responsive ? column(row.getArray("flexColumns"), 0) : row.getObject("title");
        if (endpoint.isEmpty() && !title.getArray("runs").isEmpty()) {
            endpoint = title.getArray("runs").getObject(0)
                .getObject("navigationEndpoint").getObject("browseEndpoint");
        }
        String id = endpoint.getString("browseId", "");
        String pageType = endpoint.getObject("browseEndpointContextSupportedConfigs")
            .getObject("browseEndpointContextMusicConfig").getString("pageType", "");
        String kind = switch (pageType) {
            case "MUSIC_PAGE_TYPE_ALBUM" -> "albums";
            case "MUSIC_PAGE_TYPE_ARTIST" -> "artists";
            case "MUSIC_PAGE_TYPE_PLAYLIST" -> id.startsWith("MPRE") ? "albums" : "playlists";
            default -> "";
        };
        if (kind.isEmpty()) return null;
        JsonObject subtitle = responsive ? column(row.getArray("flexColumns"), 1)
            : row.getObject("subtitle");
        return collection(kind, id, text(title), text(subtitle),
            thumbnail(row.getObject(responsive ? "thumbnail" : "thumbnailRenderer")));
    }

    private static Map<String, Object> collection(String kind, String id, String name,
                                                  String subtitle, String artwork) {
        if (!BROWSE_ID.matcher(id).matches() || name.trim().isEmpty()) return null;
        Map<String, Object> item = new HashMap<>();
        item.put("kind", kind);
        item.put("browseId", id);
        item.put("title", name);
        item.put("subtitle", subtitle);
        item.put("artworkUrl", artwork);
        return item;
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
        String artwork = thumbnail(thumbnail);
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

    private static String thumbnail(JsonObject thumbnail) {
        JsonArray images = thumbnail.getObject("musicThumbnailRenderer")
            .getObject("thumbnail").getArray("thumbnails");
        return images.isEmpty() ? null
            : images.getObject(images.size() - 1).getString("url", null);
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

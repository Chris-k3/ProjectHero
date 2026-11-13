package hunk.zombband.media;

import me.zed_0xff.zombie_buddy.Exposer;
import javax.sound.sampled.*;
import java.io.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.*;

/** Original Zomb-Band media preparation/audio bridge. Author: HUNK.
 * Supports YouTube URLs (when yt-dlp & ffmpeg are available) AND local audio files/folders
 * placed in Zomboid/ZombBand/songs/ (.wav works in pure Java; .mp3/.ogg/.m4a/.flac use ffmpeg).
 */
@Exposer.LuaClass
public final class ZombBandMedia {
    private static final int RATE = 44100, MAX_MS = 480000;
    private static final Path ROOT = Path.of(System.getProperty("user.home"), "Zomboid", "ZombBand");
    private static final Path SONGS_DIR = ROOT.resolve("songs");
    private static final Set<String> AUDIO_EXT = Set.of(".wav", ".mp3", ".ogg", ".m4a", ".flac", ".aac", ".opus", ".wma");
    private static final ExecutorService WORK = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "ZombBand-Prepare");
        t.setDaemon(true);
        return t;
    });
    private static final ScheduledExecutorService AUDIO = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "ZombBand-Audio");
        t.setDaemon(true);
        return t;
    });

    private record Track(String id, String title, String artist, int bpm, int duration,
                         String hash, String chartHash, String chart, String sourceUrl, Path wav) {}

    private record LocalSource(Path path, String portableRef, String displayTitle) {}

    private static final Map<String, Track> tracks = new ConcurrentHashMap<>();
    private static final Map<String, LocalSource> localSources = new ConcurrentHashMap<>();
    private static volatile String state = "idle", error = "", request = "", result = "";
    private static volatile long generation, leaseAt;
    private static volatile Process process;
    private static Clip clip;
    private static String clipID = "", playToken = "", armingID = "";
    private static long audioGeneration, armRetry, playAt, seekAt;
    private static double seekMs, volume, pan;
    private static boolean started;

    static {
        ensureSongsDir();
        AUDIO.scheduleAtFixedRate(() -> {
            try { audioTick(); } catch (Throwable e) { audioFailure(e); }
        }, 0, 4, TimeUnit.MILLISECONDS);
    }

    private static void ensureSongsDir() {
        try {
            Files.createDirectories(SONGS_DIR);
            Path readme = SONGS_DIR.resolve("LEEME_CANCIONES.txt");
            if (!Files.exists(readme)) {
                Files.writeString(readme,
                    "Coloca aqui tus canciones personalizadas para Zomb-Band!\n"
                    + "- Formatos soportados: .wav (sin herramientas extra), .mp3, .ogg, .m4a, .flac\n"
                    + "- Tambien puedes pegar carpetas de Clone Hero (con song.ini, notes.chart y audio)\n"
                    + "Luego abre el juego -> Instrumento -> CUSTOM SONG -> LOCAL SONGS.\n",
                    StandardCharsets.UTF_8);
            }
        } catch (Exception ignored) {}
    }

    public static String version() { return "0.11.0"; }
    public static String status() { return state; }
    public static String error() { return error; }
    public static String requestedID() { return request; }
    public static String resultID() { return result; }
    public static String songsFolder() { ensureSongsDir(); return SONGS_DIR.toString(); }

    public static String listLocalSongs() {
        ensureSongsDir();
        List<String> names = new ArrayList<>();
        try (var stream = Files.list(SONGS_DIR)) {
            for (Path p : stream.toList()) {
                String fn = p.getFileName().toString();
                if (Files.isDirectory(p)) {
                    if (findChartAudio(p) != null) names.add(fn);
                } else if (Files.isRegularFile(p) && hasAudioExt(fn)) {
                    names.add(fn);
                }
            }
        } catch (Exception ignored) {}
        names.sort(String.CASE_INSENSITIVE_ORDER);
        return String.join("\n", names);
    }

    private static boolean hasAudioExt(String name) {
        String low = name.toLowerCase(Locale.ROOT);
        int dot = low.lastIndexOf('.');
        return dot >= 0 && AUDIO_EXT.contains(low.substring(dot));
    }

    private static Path findChartAudio(Path dir) {
        for (String pref : List.of("guitar.ogg", "song.ogg", "guitar.wav", "song.wav", "audio.wav", "guitar.mp3", "song.mp3")) {
            Path p = dir.resolve(pref);
            if (Files.isRegularFile(p)) return p;
        }
        try (var s = Files.list(dir)) {
            return s.filter(p -> Files.isRegularFile(p) && hasAudioExt(p.getFileName().toString())).findFirst().orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    private static Path tool(String name) {
        boolean windows = System.getProperty("os.name").toLowerCase(Locale.ROOT).contains("win");
        String file = name + (windows ? ".exe" : "");
        List<Path> candidates = new ArrayList<>();
        candidates.add(ROOT.resolve("bin").resolve(file));
        candidates.add(ROOT.getParent().resolve("ViewpointTV/bin/" + (windows ? "win-x64" : "linux-x64")).resolve(file));

        String sysPath = System.getenv("PATH");
        if (sysPath != null) {
            for (String entry : sysPath.split(File.pathSeparator)) {
                if (!entry.isBlank()) candidates.add(Path.of(entry.trim()).resolve(file));
            }
        }
        if (windows) {
            for (String extra : List.of("C:\\ffmpeg\\bin", "C:\\Program Files\\ffmpeg\\bin", "C:\\ProgramData\\chocolatey\\bin")) {
                candidates.add(Path.of(extra).resolve(file));
            }
            String localApp = System.getenv("LOCALAPPDATA");
            if (localApp != null) {
                Path pyRoot = Path.of(localApp, "Programs", "Python");
                if (Files.isDirectory(pyRoot)) {
                    try (var dirs = Files.list(pyRoot)) {
                        for (Path py : dirs.toList()) {
                            candidates.add(py.resolve("Scripts").resolve(file));
                            if ("ffmpeg".equals(name)) {
                                Path bins = py.resolve("Lib").resolve("site-packages").resolve("imageio_ffmpeg").resolve("binaries");
                                if (Files.isDirectory(bins)) {
                                    try (var ffs = Files.list(bins)) {
                                        ffs.filter(p -> p.getFileName().toString().startsWith("ffmpeg") && p.getFileName().toString().endsWith(".exe"))
                                           .forEach(candidates::add);
                                    } catch (Exception ignored) {}
                                }
                            }
                        }
                    } catch (Exception ignored) {}
                }
            }
        }
        for (Path p : candidates) {
            if (p != null && Files.isRegularFile(p) && !Files.isSymbolicLink(p)) return p;
        }
        return null;
    }

    public static String toolsStatus() {
        boolean hasYt = tool("yt-dlp") != null;
        boolean hasFf = tool("ffmpeg") != null;
        if (hasYt && hasFf) return "READY: YouTube + Local MP3/OGG/WAV/CloneHero supported.";
        if (hasFf) return "LOCAL READY (MP3/OGG/WAV supported). Put .wav/.mp3 in Zomboid/ZombBand/songs or install yt-dlp for YouTube.";
        return "WAV READY in Zomboid/ZombBand/songs. Put yt-dlp / ffmpeg on PATH or in Zomboid/ZombBand/bin for YouTube & MP3/OGG.";
    }

    public static String normalize(String input) {
        if (input == null) return "";
        String trimmed = input.trim();
        if (trimmed.isEmpty() || trimmed.length() > 2048) return "";

        // 1) Strict HTTPS YouTube URL check
        if (trimmed.regionMatches(true, 0, "https://", 0, 8)) {
            try {
                URI u = URI.create(trimmed);
                String host = u.getHost();
                if (!"https".equalsIgnoreCase(u.getScheme()) || host == null || u.getUserInfo() != null || (u.getPort() != -1 && u.getPort() != 443)) return "";
                host = host.toLowerCase(Locale.ROOT);
                String id = "";
                if (host.equals("youtu.be")) id = u.getPath().substring(1);
                else if (Set.of("youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com").contains(host)) {
                    if ("/watch".equals(u.getPath())) {
                        for (String part : Objects.toString(u.getRawQuery(), "").split("&")) {
                            if (part.startsWith("v=")) id = part.substring(2);
                        }
                    }
                    if (u.getPath().startsWith("/shorts/") || u.getPath().startsWith("/embed/")) {
                        id = u.getPath().substring(u.getPath().lastIndexOf('/') + 1);
                    }
                }
                return id.matches("[A-Za-z0-9_-]{11}") ? id : "";
            } catch (Exception e) {
                return "";
            }
        }

        // 2) Local song reference ("local:name", bare filename in Zomboid/ZombBand/songs, or safe local audio file/folder path)
        ensureSongsDir();
        boolean explicitLocal = trimmed.regionMatches(true, 0, "local:", 0, 6);
        String rawPath = explicitLocal ? trimmed.substring(6).trim() : trimmed;
        if (rawPath.startsWith("\"") && rawPath.endsWith("\"") && rawPath.length() >= 2) {
            rawPath = rawPath.substring(1, rawPath.length() - 1).trim();
        }
        if (rawPath.contains("..")) return "";
        try {
            Path resolved = null;
            String portableRef;
            Path inSongs = SONGS_DIR.resolve(rawPath).normalize();
            if (inSongs.startsWith(SONGS_DIR) && Files.exists(inSongs)) {
                resolved = inSongs;
                portableRef = "local:" + SONGS_DIR.relativize(resolved).toString().replace('\\', '/');
            } else if (!explicitLocal) {
                Path candidate = Path.of(rawPath).toAbsolutePath().normalize();
                if (Files.exists(candidate)) {
                    resolved = candidate;
                    if (resolved.startsWith(SONGS_DIR)) {
                        portableRef = "local:" + SONGS_DIR.relativize(resolved).toString().replace('\\', '/');
                    } else {
                        portableRef = "local:" + resolved.getFileName().toString();
                    }
                } else {
                    return "";
                }
            } else {
                return "";
            }
            if (Files.isSymbolicLink(resolved)) return "";
            if (Files.isDirectory(resolved)) {
                if (findChartAudio(resolved) == null) return "";
            } else if (!Files.isRegularFile(resolved) || !hasAudioExt(resolved.getFileName().toString())) {
                return "";
            }
            String keySeed = resolved.toString().toLowerCase(Locale.ROOT);
            String hex = sha(keySeed.getBytes(StandardCharsets.UTF_8)).substring(0, 12);
            String id = "loc-" + hex;
            String baseTitle = resolved.getFileName().toString();
            int dot = baseTitle.lastIndexOf('.');
            if (Files.isRegularFile(resolved) && dot > 0) baseTitle = baseTitle.substring(0, dot);
            localSources.put(id, new LocalSource(resolved, portableRef, baseTitle));
            return id;
        } catch (Exception e) {
            return "";
        }
    }

    public static synchronized boolean begin(String urlOrPath) {
        String id = normalize(urlOrPath);
        if (id.isEmpty()) {
            error = "Use an HTTPS YouTube URL, select from LOCAL SONGS, or drop .wav/.mp3/.ogg in Zomboid/ZombBand/songs.";
            return false;
        }
        if ((state.equals("downloading") || state.equals("analyzing") || state.equals("decoding")) && id.equals(request)) return true;
        cancel();
        final long token = generation;
        request = id;
        result = "";
        error = "";
        state = id.startsWith("loc-") ? "decoding" : "downloading";
        WORK.submit(() -> prepare(id, token));
        return true;
    }

    public static synchronized void cancel() {
        generation++;
        Process p = process;
        if (p != null) {
            p.descendants().forEach(ProcessHandle::destroyForcibly);
            p.destroyForcibly();
        }
        state = "idle";
        request = "";
        result = "";
        error = "";
    }

    private static void check(long token) throws IOException {
        if (token != generation) throw new IOException("Preparation cancelled");
    }

    private static void prepare(String id, long token) {
        try {
            Path dir = ROOT.resolve("cache").resolve(id);
            Files.createDirectories(dir);
            Path wav = dir.resolve("audio-v1.wav");
            Path info = dir.resolve("title.txt");
            String title = id;
            String artist = id.startsWith("loc-") ? "Local track" : "YouTube audio";
            String sourceUrl = "https://www.youtube.com/watch?v=" + id;
            int bpm = 0;
            String preChart = null;

            LocalSource local = localSources.get(id);
            if (local != null) {
                sourceUrl = local.portableRef();
                title = local.displayTitle();
                Path srcPath = local.path();
                Path audioFile = Files.isDirectory(srcPath) ? findChartAudio(srcPath) : srcPath;
                if (audioFile == null || !Files.isRegularFile(audioFile)) {
                    throw new IOException("No supported audio file found in " + srcPath.getFileName());
                }
                if (Files.isDirectory(srcPath)) {
                    Path ini = srcPath.resolve("song.ini");
                    if (Files.isRegularFile(ini)) {
                        Map<String, String> meta = readSongIni(ini);
                        if (meta.containsKey("name")) title = meta.get("name");
                        if (meta.containsKey("artist")) artist = meta.get("artist");
                    }
                    Path chartFile = srcPath.resolve("notes.chart");
                    if (Files.isRegularFile(chartFile)) {
                        ChartParse parsed = parseCloneHeroChart(chartFile);
                        if (parsed != null) {
                            preChart = parsed.chart();
                            bpm = parsed.bpm();
                        }
                    }
                }
                if (!Files.isRegularFile(wav)) {
                    state = "decoding";
                    Path partial = dir.resolve("decoded.wav");
                    Path ffmpeg = tool("ffmpeg");
                    String lowName = audioFile.getFileName().toString().toLowerCase(Locale.ROOT);
                    if (lowName.endsWith(".wav") && tryPureJavaWavConvert(audioFile, partial)) {
                        // Converted cleanly with pure Java Sound
                    } else if (ffmpeg != null) {
                        run(List.of(ffmpeg.toString(), "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                            "-i", audioFile.toString(), "-t", "481", "-vn", "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le",
                            partial.toString()), dir.resolve("decode.log"), token, 120);
                    } else {
                        throw new IOException("Install ffmpeg (or put 16-bit PCM .wav) to decode " + audioFile.getFileName());
                    }
                    check(token);
                    validateWav(partial);
                    Files.move(partial, wav, StandardCopyOption.REPLACE_EXISTING);
                }
                Files.writeString(info, title, StandardCharsets.UTF_8);
            } else {
                if (!Files.isRegularFile(wav)) {
                    Path downloader = tool("yt-dlp"), ffmpeg = tool("ffmpeg");
                    if (downloader == null || ffmpeg == null) throw new IOException(toolsStatus());
                    run(List.of(downloader.toString(), "--ignore-config", "--no-playlist", "--no-progress", "--no-simulate", "--no-warnings",
                        "--socket-timeout", "20", "--retries", "2", "--max-filesize", "80M", "--match-filters", "duration <= 480 & !is_live",
                        "--ffmpeg-location", ffmpeg.toString(), "--format", "bestaudio[ext=m4a]/bestaudio",
                        "--print-to-file", "title", info.toString(), "--output", dir.resolve("source.%(ext)s").toString(),
                        "--", "https://www.youtube.com/watch?v=" + id), dir.resolve("download.log"), token, 300);
                    check(token);
                    Path source;
                    try (var files = Files.list(dir)) {
                        source = files.filter(p -> p.getFileName().toString().matches("source\\.[A-Za-z0-9]{1,6}"))
                            .findFirst().orElseThrow(() -> new IOException("No finite downloadable audio found; inspect download.log in Zomboid/ZombBand/cache."));
                    }
                    if (Files.size(source) > 84_000_000) throw new IOException("Source exceeds 80 MB");
                    state = "decoding";
                    Path partial = dir.resolve("decoded.wav");
                    run(List.of(ffmpeg.toString(), "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", source.toString(), "-t", "481", "-vn", "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le",
                        partial.toString()), dir.resolve("decode.log"), token, 120);
                    check(token);
                    validateWav(partial);
                    Files.move(partial, wav, StandardCopyOption.REPLACE_EXISTING);
                    Files.deleteIfExists(source);
                }
                if (Files.isRegularFile(info)) {
                    title = Files.readString(info, StandardCharsets.UTF_8).lines().findFirst().orElse(id);
                }
            }

            check(token);
            state = "analyzing";
            Track track = analyze(id, title, artist, bpm, sourceUrl, preChart, wav);
            check(token);
            synchronized (ZombBandMedia.class) {
                check(token);
                tracks.put(id, track);
                result = id;
                state = "ready";
            }
        } catch (Exception e) {
            if (token == generation) {
                error = Objects.toString(e.getMessage(), e.getClass().getSimpleName());
                state = "error";
            }
        }
    }

    private static boolean tryPureJavaWavConvert(Path srcWav, Path dstWav) {
        try (AudioInputStream raw = AudioSystem.getAudioInputStream(srcWav.toFile())) {
            AudioFormat sf = raw.getFormat();
            AudioFormat pcm = new AudioFormat(AudioFormat.Encoding.PCM_SIGNED, sf.getSampleRate(), 16, sf.getChannels(), sf.getChannels() * 2, sf.getSampleRate(), false);
            try (AudioInputStream decoded = sf.equals(pcm) ? raw : AudioSystem.getAudioInputStream(pcm, raw)) {
                byte[] all = decoded.readAllBytes();
                int ch = Math.max(1, pcm.getChannels());
                int frames = all.length / (ch * 2);
                double srcRate = pcm.getSampleRate();
                if (frames < srcRate * 5 || frames > srcRate * (MAX_MS / 1000.0)) return false;
                double[] mono = new double[frames];
                for (int i = 0; i < frames; i++) {
                    long sum = 0;
                    for (int c = 0; c < ch; c++) {
                        int idx = (i * ch + c) * 2;
                        sum += (short) ((all[idx] & 255) | (all[idx + 1] << 8));
                    }
                    mono[i] = sum / (double) ch;
                }
                int outFrames = Math.min(RATE * (MAX_MS / 1000), (int) Math.round(frames * (RATE / srcRate)));
                byte[] outPcm = new byte[outFrames * 2];
                for (int j = 0; j < outFrames; j++) {
                    double pos = j * (srcRate / RATE);
                    int idx = Math.min(frames - 1, (int) pos);
                    int next = Math.min(frames - 1, idx + 1);
                    double frac = pos - idx;
                    int val = (int) Math.round(mono[idx] * (1.0 - frac) + mono[next] * frac);
                    if (val > 32767) val = 32767;
                    else if (val < -32768) val = -32768;
                    outPcm[j * 2] = (byte) (val & 255);
                    outPcm[j * 2 + 1] = (byte) ((val >> 8) & 255);
                }
                AudioFormat target = new AudioFormat(AudioFormat.Encoding.PCM_SIGNED, RATE, 16, 1, 2, RATE, false);
                try (AudioInputStream outStream = new AudioInputStream(new ByteArrayInputStream(outPcm), target, outFrames)) {
                    AudioSystem.write(outStream, AudioFileFormat.Type.WAVE, dstWav.toFile());
                }
                return Files.isRegularFile(dstWav);
            }
        } catch (Exception e) {
            return false;
        }
    }

    private static Map<String, String> readSongIni(Path ini) {
        Map<String, String> map = new HashMap<>();
        try {
            for (String line : Files.readAllLines(ini, StandardCharsets.UTF_8)) {
                int eq = line.indexOf('=');
                if (eq > 0) {
                    map.put(line.substring(0, eq).trim().toLowerCase(Locale.ROOT), line.substring(eq + 1).trim());
                }
            }
        } catch (Exception ignored) {}
        return map;
    }

    private record ChartParse(String chart, int bpm) {}

    private static ChartParse parseCloneHeroChart(Path chartPath) {
        try {
            List<String> lines = Files.readAllLines(chartPath, StandardCharsets.UTF_8);
            int resolution = 192;
            TreeMap<Long, Integer> bpmEvents = new TreeMap<>();
            bpmEvents.put(0L, 120000);
            Map<String, List<long[]>> sections = new HashMap<>();
            String cur = "";
            Pattern resP = Pattern.compile("Resolution\\s*=\\s*(\\d+)", Pattern.CASE_INSENSITIVE);
            Pattern bpmP = Pattern.compile("(\\d+)\\s*=\\s*B\\s+(\\d+)");
            Pattern noteP = Pattern.compile("(\\d+)\\s*=\\s*N\\s+(\\d+)\\s+(\\d+)");
            for (String raw : lines) {
                String line = raw.trim();
                if (line.startsWith("[") && line.endsWith("]")) {
                    cur = line.substring(1, line.length() - 1);
                    sections.putIfAbsent(cur, new ArrayList<>());
                    continue;
                }
                if ("Song".equalsIgnoreCase(cur)) {
                    Matcher rm = resP.matcher(line);
                    if (rm.find()) resolution = Math.max(1, Integer.parseInt(rm.group(1)));
                } else if ("SyncTrack".equalsIgnoreCase(cur)) {
                    Matcher bm = bpmP.matcher(line);
                    if (bm.find()) bpmEvents.put(Long.parseLong(bm.group(1)), Math.max(20000, Integer.parseInt(bm.group(2))));
                } else if (!cur.isEmpty()) {
                    Matcher nm = noteP.matcher(line);
                    if (nm.find()) {
                        long tick = Long.parseLong(nm.group(1));
                        int fret = Integer.parseInt(nm.group(2));
                        if (fret >= 0 && fret <= 4) {
                            sections.get(cur).add(new long[]{tick, fret});
                        }
                    }
                }
            }
            List<long[]> picked = null;
            for (String sec : List.of("ExpertSingle", "HardSingle", "MediumSingle", "EasySingle", "ExpertDrums", "HardDrums", "ExpertDoubleBass")) {
                List<long[]> l = sections.get(sec);
                if (l != null && l.size() >= 8) { picked = l; break; }
            }
            if (picked == null) return null;
            StringBuilder sb = new StringBuilder();
            long lastMs = -1000;
            int count = 0;
            for (long[] ev : picked) {
                if (count >= 4800) break;
                long ms = tickToMs(ev[0], resolution, bpmEvents);
                if (ms < 2400 || ms >= MAX_MS - 1000 || ms - lastMs < 80) continue;
                int lane = 1 + (int) ((ev[1] >= 4) ? 3 : ev[1]);
                if (sb.length() > 0) sb.append(';');
                sb.append(ms).append(',').append(lane);
                lastMs = ms;
                count++;
            }
            if (count < 8) return null;
            int baseBpm = (int) Math.round(bpmEvents.firstEntry().getValue() / 1000.0);
            return new ChartParse(sb.toString(), baseBpm);
        } catch (Exception e) {
            return null;
        }
    }

    private static long tickToMs(long targetTick, int resolution, TreeMap<Long, Integer> bpmEvents) {
        double ms = 0.0;
        long prevTick = 0;
        int curMilliBpm = 120000;
        for (var entry : bpmEvents.entrySet()) {
            long t = entry.getKey();
            if (t >= targetTick) break;
            if (t > prevTick) {
                ms += ((t - prevTick) / (double) resolution) * (60_000_000.0 / curMilliBpm);
                prevTick = t;
            }
            curMilliBpm = entry.getValue();
        }
        ms += ((targetTick - prevTick) / (double) resolution) * (60_000_000.0 / curMilliBpm);
        return Math.round(ms);
    }

    private static void run(List<String> args, Path log, long token, int seconds) throws Exception {
        check(token);
        Process p = new ProcessBuilder(args).redirectErrorStream(true).redirectOutput(log.toFile()).start();
        process = p;
        try {
            long until = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
            while (!p.waitFor(200, TimeUnit.MILLISECONDS)) {
                check(token);
                if (System.nanoTime() > until) throw new IOException("Media tool timed out");
                if (log.getFileName().toString().startsWith("download")) {
                    long bytes = 0;
                    try (var files = Files.walk(log.getParent(), 2)) {
                        for (Path f : files.filter(Files::isRegularFile).toList()) {
                            if (f.getFileName().toString().startsWith("source.")) bytes += Files.size(f);
                        }
                    }
                    if (bytes > 84_000_000) throw new IOException("Download exceeds the 80 MB source limit");
                }
                if (Files.exists(log) && Files.size(log) > 2_000_000) throw new IOException("Media tool produced excessive error output");
            }
            check(token);
            if (p.exitValue() != 0) throw new IOException("Media preparation failed; see " + log.getFileName() + " in Zomboid/ZombBand/cache.");
        } finally {
            if (p.isAlive()) {
                p.descendants().forEach(ProcessHandle::destroyForcibly);
                p.destroyForcibly();
            }
            if (process == p) process = null;
        }
    }

    private static void validateWav(Path path) throws Exception {
        if (Files.size(path) > 44_000_000) throw new IOException("Song exceeds the eight-minute PCM limit");
        try (AudioInputStream in = AudioSystem.getAudioInputStream(path.toFile())) {
            AudioFormat f = in.getFormat();
            long ms = in.getFrameLength() * 1000 / RATE;
            if (f.getChannels() != 1 || f.getSampleSizeInBits() != 16 || f.getSampleRate() != RATE
                || f.isBigEndian() || !AudioFormat.Encoding.PCM_SIGNED.equals(f.getEncoding())
                || ms < 5000 || ms > MAX_MS) {
                throw new IOException("Use a finite song between five seconds and eight minutes");
            }
        }
    }

    static Track analyze(String id, String title, String artist, int bpm, String sourceUrl, String preChart, Path wav) throws Exception {
        validateWav(wav);
        byte[] pcm;
        try (AudioInputStream in = AudioSystem.getAudioInputStream(wav.toFile())) {
            pcm = in.readAllBytes();
        }
        String hash = sha(pcm);
        int samples = pcm.length / 2;
        int durationMs = (int) ((long) samples * 1000 / RATE);
        String text = preChart;
        if (text == null || text.isEmpty()) {
            int hop = 441, n = (samples + hop - 1) / hop;
            double[] energy = new double[n];
            for (int h = 0; h < n; h++) {
                double sum = 0;
                int end = Math.min(samples, (h + 1) * hop);
                for (int i = h * hop; i < end; i++) {
                    int s = (short) ((pcm[i * 2] & 255) | (pcm[i * 2 + 1] << 8));
                    sum += (double) s * s;
                }
                energy[h] = StrictMath.sqrt(sum / Math.max(1, end - h * hop));
            }
            StringBuilder chart = new StringBuilder();
            int last = -100, index = 0;
            for (int h = 240; h < n - 3 && index < 4800; h++) {
                double avg = 0;
                for (int j = Math.max(0, h - 12); j < h; j++) avg += energy[j];
                avg /= Math.min(12, h);
                double flux = energy[h] - energy[Math.max(0, h - 2)];
                if (energy[h] > 110 && flux > Math.max(75, avg * .10) && energy[h] >= energy[h + 1] && energy[h] >= energy[h - 1] && h - last >= 11) {
                    int lane = 1 + (int) ((long) StrictMath.floor(energy[h] / 96) + index) % 4;
                    if (chart.length() > 0) chart.append(';');
                    chart.append(h * 10).append(',').append(lane);
                    last = h;
                    index++;
                }
            }
            if (index < 8) throw new IOException("Not enough detectable attacks for an automatic rhythm chart; use a recording with clearer rhythm.");
            text = chart.toString();
        }
        return new Track(id, clean(title), clean(artist), bpm, durationMs, hash,
            sha(text.getBytes(StandardCharsets.US_ASCII)), text, sourceUrl, wav);
    }

    static String sha(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    private static String clean(String text) {
        if (text == null) return "";
        String c = text.replace('\t', ' ').replaceAll("[\\p{Cntrl}]", " ");
        return c.substring(0, Math.min(120, c.length())).trim();
    }

    public static String manifest(String id) {
        Track t = tracks.get(id);
        return t == null ? "" : t.id + "\t" + t.title + "\t" + t.duration + "\t" + t.hash + "\t" + t.chartHash + "\t" + t.sourceUrl + "\t" + t.artist + "\t" + t.bpm;
    }

    public static String chart(String id) {
        Track t = tracks.get(id);
        return t == null ? "" : t.chart;
    }

    public static boolean matches(String id, String hash, String chartHash) {
        Track t = tracks.get(id);
        return t != null && t.hash.equals(hash) && t.chartHash.equals(chartHash);
    }

    public static synchronized boolean arm(String id) {
        if (id.equals(clipID) && clip != null && clip.isOpen()) return true;
        Track t = tracks.get(id);
        if (t == null) return false;
        if (id.equals(armingID) || System.nanoTime() < armRetry) return false;
        stop();
        armingID = id;
        long token = audioGeneration;
        error = "Opening custom audio output...";
        WORK.submit(() -> {
            Clip opened = null;
            try (AudioInputStream in = AudioSystem.getAudioInputStream(t.wav.toFile())) {
                opened = AudioSystem.getClip();
                opened.open(in);
                synchronized (ZombBandMedia.class) {
                    if (token != audioGeneration) { opened.close(); return; }
                    clip = opened;
                    clipID = id;
                    armingID = "";
                    error = "";
                    setLevel(0, 0);
                }
            } catch (Exception e) {
                if (opened != null) opened.close();
                synchronized (ZombBandMedia.class) {
                    if (token == audioGeneration) {
                        armingID = "";
                        armRetry = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
                        error = "Audio output unavailable: " + e.getMessage();
                    }
                }
            }
        });
        return false;
    }

    public static synchronized boolean schedule(String id, String token, double delayMs) {
        if (token.equals(playToken) && id.equals(clipID)) return true;
        if (!arm(id)) return false;
        clip.stop();
        clip.setFramePosition(0);
        playToken = token;
        started = false;
        long now = System.nanoTime();
        playAt = now + (long) (delayMs * 1_000_000);
        leaseAt = now;
        seekAt = 0;
        seekMs = -delayMs;
        return true;
    }

    public static synchronized void update(String token, double elapsedMs, double gain, double stereoPan) {
        if (!token.equals(playToken)) return;
        long now = System.nanoTime();
        leaseAt = now;
        volume = Math.max(0, Math.min(1, gain));
        pan = Math.max(-1, Math.min(1, stereoPan));
        seekMs = elapsedMs;
        seekAt = now;
        setLevel(volume, pan);
    }

    public static synchronized double cursorMs() {
        return clip == null ? -1 : clip.getMicrosecondPosition() / 1000.0;
    }

    private static synchronized void audioTick() {
        if (clip == null || playToken.isEmpty()) return;
        long now = System.nanoTime();
        if (now - leaseAt > TimeUnit.SECONDS.toNanos(2)) { stop(); return; }
        if (!started && now >= playAt) {
            long frame = Math.max(0, Math.min(clip.getFrameLength() - 1, (now - playAt) * RATE / 1_000_000_000));
            clip.setFramePosition((int) frame);
            setLevel(volume, pan);
            clip.start();
            started = true;
        }
        if (started && seekAt != 0 && now - seekAt < TimeUnit.MILLISECONDS.toNanos(500)) {
            double expected = seekMs + (now - seekAt) / 1_000_000.0;
            if (expected >= 0 && expected < clip.getMicrosecondLength() / 1000.0 && Math.abs(cursorMs() - expected) > 65) {
                clip.setMicrosecondPosition((long) (expected * 1000));
            }
        }
    }

    private static void setLevel(double gain, double p) {
        if (clip == null) return;
        if (clip.isControlSupported(FloatControl.Type.MASTER_GAIN)) {
            FloatControl c = (FloatControl) clip.getControl(FloatControl.Type.MASTER_GAIN);
            c.setValue((float) Math.max(c.getMinimum(), Math.min(c.getMaximum(), gain <= 0 ? c.getMinimum() : 20 * StrictMath.log10(gain))));
        } else if (clip.isControlSupported(FloatControl.Type.VOLUME)) {
            FloatControl c = (FloatControl) clip.getControl(FloatControl.Type.VOLUME);
            c.setValue((float) (c.getMinimum() + (c.getMaximum() - c.getMinimum()) * Math.max(0, Math.min(1, gain))));
        }
        if (clip.isControlSupported(BooleanControl.Type.MUTE)) {
            ((BooleanControl) clip.getControl(BooleanControl.Type.MUTE)).setValue(gain < .001);
        }
        if (clip.isControlSupported(FloatControl.Type.PAN)) {
            ((FloatControl) clip.getControl(FloatControl.Type.PAN)).setValue((float) p);
        }
    }

    private static synchronized void audioFailure(Throwable e) {
        error = "Audio output error: " + e.getClass().getSimpleName();
        stop();
    }

    public static synchronized void stop() {
        audioGeneration++;
        armingID = "";
        if (clip != null) { clip.stop(); clip.close(); clip = null; }
        clipID = "";
        playToken = "";
        started = false;
        volume = 0;
    }
}

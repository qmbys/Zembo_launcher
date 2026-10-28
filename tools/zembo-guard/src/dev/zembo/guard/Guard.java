package dev.zembo.guard;

import java.io.*;
import java.net.URL;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.CodeSource;
import java.security.ProtectionDomain;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Логика решений. Методы вызываются из пропатченных методов JDK.
 * Любая внутренняя ошибка = «разрешить» (guard никогда не должен ломать игру).
 */
public final class Guard {
    private Guard() {}

    public static volatile boolean ready;

    static final boolean WIN = System.getProperty("os.name", "").toLowerCase().contains("win");

    static final class Mod {
        final String file;
        final String fileLower;
        final boolean noCreate, noRead, noWindows;
        final AtomicInteger blockedCreate = new AtomicInteger();
        final AtomicInteger blockedRead = new AtomicInteger();
        final AtomicInteger blockedWindows = new AtomicInteger();

        Mod(String file, boolean noCreate, boolean noRead, boolean noWindows) {
            this.file = file;
            this.fileLower = file.toLowerCase();
            this.noCreate = noCreate;
            this.noRead = noRead;
            this.noWindows = noWindows;
        }
    }

    private static final List<Mod> MODS = new ArrayList<>();
    private static final List<String> ALLOW = new ArrayList<>();
    private static String reportPath;
    private static boolean anyCreate, anyRead, anyWindows;

    private static final Object JDK = new Object();
    private static final Object PASS = new Object();
    private static final Object OTHER = new Object();

    /** Библиотеки-помощники: если мод вызывает файловую операцию через них, считаем, что её сделал мод. */
    private static final String[] PASS_PREFIXES = {
        "org.apache.commons.io.", "org.apache.commons.lang3.", "org.apache.commons.compress.",
        "com.google.common.io.", "com.google.common.base.", "com.google.common.collect.",
        "com.google.gson.", "kotlin.", "kotlinx.", "scala."
    };

    private static final ThreadLocal<boolean[]> BUSY = ThreadLocal.withInitial(() -> new boolean[1]);

    private static final ClassValue<Object> KIND = new ClassValue<Object>() {
        @Override
        protected Object computeValue(Class<?> c) {
            return classify(c);
        }
    };

    // ---------------------------------------------------------------- init

    /** Возвращает маску включённых видов защиты (Patcher.CREATE | READ | WINDOWS). */
    public static int init(String configPath) throws IOException {
        File conf = new File(configPath);
        File dir = conf.getAbsoluteFile().getParentFile();
        reportPath = new File(dir, "zembo_guard_report.json").getPath();

        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(conf), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                int eq = line.indexOf('=');
                if (eq < 0) continue;
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                if (key.equals("allow")) {
                    String n = normalizeString(value);
                    if (n != null) ALLOW.add(n);
                } else if (key.equals("mod")) {
                    int bar = value.lastIndexOf('|');
                    if (bar <= 0) continue;
                    String file = value.substring(0, bar).trim();
                    Set<String> flags = new HashSet<>(Arrays.asList(value.substring(bar + 1).trim().toLowerCase().split(",")));
                    Mod m = new Mod(file, flags.contains("create"), flags.contains("read"), flags.contains("windows"));
                    if (m.noCreate || m.noRead || m.noWindows) {
                        MODS.add(m);
                        anyCreate |= m.noCreate;
                        anyRead |= m.noRead;
                        anyWindows |= m.noWindows;
                    }
                }
            }
        }
        for (String prop : new String[] {"java.home", "java.io.tmpdir"}) {
            String n = normalizeString(System.getProperty(prop));
            if (n != null) ALLOW.add(n);
        }

        // Прогрев: загружаем все классы, которые понадобятся внутри хуков, чтобы не было рекурсии при инициализации.
        boolean[] busy = BUSY.get();
        busy[0] = true;
        try {
            KIND.get(Guard.class);
            attribute();
            normalize(new File("."));
            normalize(Paths.get("."));
            Class.forName("java.nio.file.AccessDeniedException");
            Class.forName("java.io.FileNotFoundException");
            Class.forName("dev.zembo.guard.Guard$Mod");
        } catch (Throwable ignored) {
        } finally {
            busy[0] = false;
        }

        int mask = 0;
        if (anyCreate) mask |= Patcher.CREATE;
        if (anyRead) mask |= Patcher.READ;
        if (anyWindows) mask |= Patcher.WINDOWS;
        return mask;
    }

    static String describeMods() {
        StringBuilder sb = new StringBuilder();
        for (Mod m : MODS) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(m.file);
        }
        return sb.toString();
    }

    // ---------------------------------------------------------------- hooks: THROW mode

    public static void writeIo(Object file) throws FileNotFoundException {
        if (deny(Patcher.CREATE, file, "write")) throw new FileNotFoundException(describe(file) + " (Access is denied by Zembo Guard)");
    }

    public static void readIo(Object file) throws FileNotFoundException {
        if (deny(Patcher.READ, file, "read")) throw new FileNotFoundException(describe(file) + " (Access is denied by Zembo Guard)");
    }

    public static void rafIo(Object file, Object mode) throws FileNotFoundException {
        boolean write = mode != null && mode.toString().indexOf('w') >= 0;
        if (write ? deny(Patcher.CREATE, file, "write") : deny(Patcher.READ, file, "read")) {
            throw new FileNotFoundException(describe(file) + " (Access is denied by Zembo Guard)");
        }
    }

    public static void writeNio(Object path) throws IOException {
        if (deny(Patcher.CREATE, path, "write")) throw new AccessDeniedException(describe(path), null, "denied by Zembo Guard");
    }

    public static void readNio(Object path) throws IOException {
        if (deny(Patcher.READ, path, "read")) throw new AccessDeniedException(describe(path), null, "denied by Zembo Guard");
    }

    public static void optsNio(Object path, Object options) throws IOException {
        boolean write = false;
        if (options instanceof Collection) {
            for (Object o : (Collection<?>) options) write |= isWriteOption(o);
        } else if (options instanceof Object[]) {
            for (Object o : (Object[]) options) write |= isWriteOption(o);
        }
        if (write) writeNio(path); else readNio(path);
    }

    public static void copyNio(Object src, Object dst) throws IOException {
        readNio(src);
        writeNio(dst);
    }

    public static void moveNio(Object src, Object dst) throws IOException {
        writeNio(src);
        writeNio(dst);
    }

    public static void processIo() throws IOException {
        if (deny(Patcher.WINDOWS, "process", "start-process")) throw new IOException("Access is denied by Zembo Guard");
    }

    // ---------------------------------------------------------------- hooks: SKIP mode (true = пропустить вызов)

    public static boolean skipWrite(Object file) {
        return deny(Patcher.CREATE, file, "write");
    }

    public static boolean skipRename(Object a, Object b) {
        return deny(Patcher.CREATE, a, "write");
    }

    public static boolean skipRead(Object file) {
        return deny(Patcher.READ, file, "read");
    }

    public static boolean skipWindow(int visible) {
        return visible != 0 && deny(Patcher.WINDOWS, "window", "open-window");
    }

    public static boolean skipWindowAlways() {
        return deny(Patcher.WINDOWS, "window", "open-window");
    }

    // ---------------------------------------------------------------- core

    private static boolean isWriteOption(Object o) {
        if (!(o instanceof StandardOpenOption)) return false;
        switch ((StandardOpenOption) o) {
            case WRITE: case APPEND: case CREATE: case CREATE_NEW: case DELETE_ON_CLOSE: case TRUNCATE_EXISTING:
                return true;
            default:
                return false;
        }
    }

    private static boolean deny(int kind, Object target, String action) {
        if (!ready) return false;
        if (kind == Patcher.CREATE && !anyCreate) return false;
        if (kind == Patcher.READ && !anyRead) return false;
        if (kind == Patcher.WINDOWS && !anyWindows) return false;

        boolean[] busy = BUSY.get();
        if (busy[0]) return false;
        busy[0] = true;
        try {
            String normalized = null;
            if (kind == Patcher.READ) {
                // Дешёвая предфильтрация: чтение внутри разрешённых папок не проверяем вообще.
                normalized = normalize(target);
                if (normalized == null || insideAllowed(normalized)) return false;
            }
            Mod mod = attribute();
            if (mod == null) return false;
            boolean denied = (kind == Patcher.CREATE && mod.noCreate)
                || (kind == Patcher.READ && mod.noRead)
                || (kind == Patcher.WINDOWS && mod.noWindows);
            if (!denied) return false;

            AtomicInteger counter = kind == Patcher.CREATE ? mod.blockedCreate : kind == Patcher.READ ? mod.blockedRead : mod.blockedWindows;
            int n = counter.incrementAndGet();
            if (n <= 20) {
                System.err.println("[ZemboGuard] blocked mod=" + mod.file + " action=" + action + " target=" + describe(target));
            }
            return true;
        } catch (Throwable t) {
            return false;
        } finally {
            busy[0] = false;
        }
    }

    /** Кто вызвал операцию: первый кадр стека, который не относится к JDK и не к библиотекам-помощникам. */
    private static Mod attribute() {
        return StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE).walk(frames -> {
            Iterator<StackWalker.StackFrame> it = frames.iterator();
            while (it.hasNext()) {
                Object k = KIND.get(it.next().getDeclaringClass());
                if (k == JDK || k == PASS) continue;
                return k instanceof Mod ? (Mod) k : null;
            }
            return null;
        });
    }

    private static Object classify(Class<?> c) {
        try {
            String n = c.getName();
            if (c.getClassLoader() == null
                || n.startsWith("java.") || n.startsWith("javax.") || n.startsWith("jdk.")
                || n.startsWith("sun.") || n.startsWith("com.sun.")) {
                return JDK;
            }
            String loc = location(c);
            if (loc != null) {
                String s;
                try {
                    s = URLDecoder.decode(loc.replace("+", "%2B"), "UTF-8");
                } catch (Exception e) {
                    s = loc;
                }
                s = s.replace('\\', '/').toLowerCase();
                for (Mod m : MODS) {
                    int from = 0;
                    String needle = "/" + m.fileLower;
                    while (true) {
                        int i = s.indexOf(needle, from);
                        if (i < 0) break;
                        int end = i + needle.length();
                        if (end == s.length() || "!#/?".indexOf(s.charAt(end)) >= 0) return m;
                        from = i + 1;
                    }
                }
            }
            for (String p : PASS_PREFIXES) if (n.startsWith(p)) return PASS;
        } catch (Throwable ignored) {
        }
        return OTHER;
    }

    private static String location(Class<?> c) {
        try {
            ProtectionDomain pd = c.getProtectionDomain();
            CodeSource cs = pd == null ? null : pd.getCodeSource();
            if (cs != null && cs.getLocation() != null) return cs.getLocation().toString();
        } catch (Throwable ignored) {
        }
        try {
            URL u = c.getResource("/" + c.getName().replace('.', '/') + ".class");
            if (u != null) return u.toString();
        } catch (Throwable ignored) {
        }
        return null;
    }

    // ---------------------------------------------------------------- paths

    private static boolean insideAllowed(String p) {
        for (String root : ALLOW) {
            if (p.equals(root) || p.startsWith(root.endsWith("/") ? root : root + "/")) return true;
        }
        return false;
    }

    /** null = путь не проверяем (не файловая система по умолчанию, или не удалось разобрать). */
    private static String normalize(Object o) {
        try {
            String s;
            if (o instanceof File) {
                s = ((File) o).getAbsolutePath();
            } else if (o instanceof Path) {
                Path p = (Path) o;
                if (p.getFileSystem() != FileSystems.getDefault()) return null; // zipfs, union fs и т.п.
                s = p.toAbsolutePath().toString();
            } else if (o instanceof String) {
                s = new File((String) o).getAbsolutePath();
            } else {
                return null;
            }
            return normalizeString(s);
        } catch (Throwable t) {
            return null;
        }
    }

    private static String normalizeString(String s) {
        if (s == null) return null;
        s = s.replace('\\', '/');
        boolean abs = s.startsWith("/");
        String[] parts = s.split("/");
        ArrayList<String> out = new ArrayList<>();
        for (String part : parts) {
            if (part.isEmpty() || part.equals(".")) continue;
            if (part.equals("..")) {
                if (!out.isEmpty()) out.remove(out.size() - 1);
                continue;
            }
            out.add(part);
        }
        String joined = String.join("/", out);
        String res = abs ? "/" + joined : joined;
        return WIN ? res.toLowerCase() : res;
    }

    private static String describe(Object o) {
        try {
            return o == null ? "null" : o.toString();
        } catch (Throwable t) {
            return "?";
        }
    }

    // ---------------------------------------------------------------- report

    static void writeReport() {
        boolean[] busy = BUSY.get();
        busy[0] = true;
        try {
            StringBuilder sb = new StringBuilder("{\n  \"mods\": {");
            boolean first = true;
            for (Mod m : MODS) {
                int c = m.blockedCreate.get(), r = m.blockedRead.get(), w = m.blockedWindows.get();
                if (c + r + w == 0) continue;
                if (!first) sb.append(',');
                first = false;
                sb.append("\n    \"").append(m.file.replace("\\", "\\\\").replace("\"", "\\\"")).append("\": {")
                  .append("\"create\": ").append(c).append(", \"read\": ").append(r).append(", \"windows\": ").append(w).append('}');
            }
            sb.append("\n  }\n}\n");
            Files.write(Paths.get(reportPath), sb.toString().getBytes(StandardCharsets.UTF_8));
        } catch (Throwable ignored) {
        } finally {
            busy[0] = false;
        }
    }
}

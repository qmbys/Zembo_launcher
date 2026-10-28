package dev.zembo.guard;

import java.io.*;
import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.*;

/**
 * Вставляет в начало выбранных методов JDK вызов Guard.* (без ASM, прямой правкой class-файла).
 * THROW-хук: вызов guard-метода, который сам бросает исключение.
 * SKIP-хук: если guard вернул true, метод сразу возвращает 0/null/void.
 */
public final class Patcher implements ClassFileTransformer {
    public static final int CREATE = 1, READ = 2, WINDOWS = 4;

    private static final String GUARD = "dev/zembo/guard/Guard";

    static final class Hook {
        final int kind;
        final String owner, name, desc, guard;
        final int[] slots;
        final boolean[] isInt;
        final boolean skip;

        Hook(int kind, String owner, String name, String desc, String guard, String pushes, boolean skip) {
            this.kind = kind;
            this.owner = owner;
            this.name = name;
            this.desc = desc;
            this.guard = guard;
            this.skip = skip;
            String[] t = pushes.isEmpty() ? new String[0] : pushes.split(",");
            slots = new int[t.length];
            isInt = new boolean[t.length];
            for (int i = 0; i < t.length; i++) {
                isInt[i] = t[i].endsWith("I");
                slots[i] = Integer.parseInt(isInt[i] ? t[i].substring(0, t[i].length() - 1) : t[i]);
            }
        }

        String guardDesc() {
            StringBuilder sb = new StringBuilder("(");
            for (boolean i : isInt) sb.append(i ? "I" : "Ljava/lang/Object;");
            return sb.append(')').append(skip ? "Z" : "V").toString();
        }
    }

    private static final String P = "Ljava/nio/file/Path;";
    private static final String OO = "[Ljava/nio/file/OpenOption;";
    private static final String CO = "[Ljava/nio/file/CopyOption;";
    private static final String FA = "[Ljava/nio/file/attribute/FileAttribute;";

    private static final List<Hook> ALL = new ArrayList<>();

    private static void t(int kind, String owner, String name, String desc, String guard, String pushes) {
        ALL.add(new Hook(kind, owner, name, desc, guard, pushes, false));
    }

    private static void s(int kind, String owner, String name, String desc, String guard, String pushes) {
        ALL.add(new Hook(kind, owner, name, desc, guard, pushes, true));
    }

    static {
        // ---- создание / изменение / удаление файлов
        t(CREATE, "java/io/FileOutputStream", "<init>", "(Ljava/io/File;Z)V", "writeIo", "1");
        t(CREATE, "java/io/RandomAccessFile", "<init>", "(Ljava/io/File;Ljava/lang/String;)V", "rafIo", "1,2");
        t(CREATE, "java/nio/file/Files", "newOutputStream", "(" + P + OO + ")Ljava/io/OutputStream;", "writeNio", "0");
        t(CREATE, "java/nio/file/Files", "createFile", "(" + P + FA + ")" + P, "writeNio", "0");
        t(CREATE, "java/nio/file/Files", "createDirectory", "(" + P + FA + ")" + P, "writeNio", "0");
        t(CREATE, "java/nio/file/Files", "delete", "(" + P + ")V", "writeNio", "0");
        t(CREATE, "java/nio/file/Files", "deleteIfExists", "(" + P + ")Z", "writeNio", "0");
        t(CREATE, "java/nio/file/Files", "copy", "(" + P + P + CO + ")" + P, "writeNio", "1");
        t(CREATE, "java/nio/file/Files", "copy", "(Ljava/io/InputStream;" + P + CO + ")J", "writeNio", "1");
        t(CREATE, "java/nio/file/Files", "move", "(" + P + P + CO + ")" + P, "moveNio", "0,1");
        s(CREATE, "java/io/File", "createNewFile", "()Z", "skipWrite", "0");
        s(CREATE, "java/io/File", "mkdir", "()Z", "skipWrite", "0");
        s(CREATE, "java/io/File", "delete", "()Z", "skipWrite", "0");
        s(CREATE, "java/io/File", "renameTo", "(Ljava/io/File;)Z", "skipRename", "0,1");
        // newByteChannel / FileChannel.open: режим определяется по OpenOption
        t(CREATE | READ, "java/nio/file/Files", "newByteChannel", "(" + P + "Ljava/util/Set;" + FA + ")Ljava/nio/channels/SeekableByteChannel;", "optsNio", "0,1");
        t(CREATE | READ, "java/nio/channels/FileChannel", "open", "(" + P + "Ljava/util/Set;" + FA + ")Ljava/nio/channels/FileChannel;", "optsNio", "0,1");

        // ---- чтение / просмотр файлов
        t(READ, "java/io/FileInputStream", "<init>", "(Ljava/io/File;)V", "readIo", "1");
        t(READ, "java/nio/file/Files", "newInputStream", "(" + P + OO + ")Ljava/io/InputStream;", "readNio", "0");
        t(READ, "java/nio/file/Files", "copy", "(" + P + "Ljava/io/OutputStream;)J", "readNio", "0");
        t(READ, "java/nio/file/Files", "newDirectoryStream", "(" + P + ")Ljava/nio/file/DirectoryStream;", "readNio", "0");
        t(READ, "java/nio/file/Files", "newDirectoryStream", "(" + P + "Ljava/lang/String;)Ljava/nio/file/DirectoryStream;", "readNio", "0");
        t(READ, "java/nio/file/Files", "newDirectoryStream", "(" + P + "Ljava/nio/file/DirectoryStream$Filter;)Ljava/nio/file/DirectoryStream;", "readNio", "0");
        s(READ, "java/io/File", "list", "()[Ljava/lang/String;", "skipRead", "0");

        // ---- окна, браузер, внешние программы
        s(WINDOWS, "java/awt/Window", "setVisible", "(Z)V", "skipWindow", "1I");
        s(WINDOWS, "java/awt/Window", "show", "()V", "skipWindowAlways", "");
        s(WINDOWS, "java/awt/Dialog", "setVisible", "(Z)V", "skipWindow", "1I");
        s(WINDOWS, "java/awt/Dialog", "show", "()V", "skipWindowAlways", "");
        s(WINDOWS, "java/awt/Desktop", "browse", "(Ljava/net/URI;)V", "skipWindowAlways", "");
        s(WINDOWS, "java/awt/Desktop", "open", "(Ljava/io/File;)V", "skipWindowAlways", "");
        s(WINDOWS, "java/awt/Desktop", "edit", "(Ljava/io/File;)V", "skipWindowAlways", "");
        s(WINDOWS, "java/awt/Desktop", "mail", "(Ljava/net/URI;)V", "skipWindowAlways", "");
        t(WINDOWS, "java/lang/ProcessBuilder", "start", "()Ljava/lang/Process;", "processIo", "");
    }

    private final Map<String, List<Hook>> byClass = new HashMap<>();

    public Patcher(int enabledKinds) {
        for (Hook h : ALL) {
            if ((h.kind & enabledKinds) != 0) byClass.computeIfAbsent(h.owner, k -> new ArrayList<>()).add(h);
        }
    }

    public boolean wants(String internalName) {
        return byClass.containsKey(internalName);
    }

    @Override
    public byte[] transform(ClassLoader loader, String name, Class<?> redefined, ProtectionDomain pd, byte[] buf) {
        if (name == null) return null;
        List<Hook> hooks = byClass.get(name);
        if (hooks == null) return null;
        try {
            return patch(buf, hooks);
        } catch (Throwable t) {
            System.err.println("[ZemboGuard] cannot patch " + name + ": " + t);
            return null;
        }
    }

    // ====================================================================== class file patching

    private static int u1(byte[] b, int p) { return b[p] & 0xff; }
    private static int u2(byte[] b, int p) { return ((b[p] & 0xff) << 8) | (b[p + 1] & 0xff); }
    private static int u4(byte[] b, int p) { return (u2(b, p) << 16) | u2(b, p + 2); }

    private static final class Out {
        final ByteArrayOutputStream bos = new ByteArrayOutputStream();
        void u1(int v) { bos.write(v); }
        void u2(int v) { bos.write(v >> 8); bos.write(v); }
        void u4(int v) { u2(v >>> 16); u2(v & 0xffff); }
        void raw(byte[] b, int off, int len) { bos.write(b, off, len); }
        void raw(byte[] b) { bos.write(b, 0, b.length); }
        int size() { return bos.size(); }
        byte[] bytes() { return bos.toByteArray(); }
    }

    private static final class Cp {
        final byte[] in;
        final int count;
        final int end;
        final int[] tag;
        final String[] utf;
        final Map<String, Integer> utfIndex = new HashMap<>();
        final Out extra = new Out();
        int next;
        final Map<String, Integer> added = new HashMap<>();

        Cp(byte[] in) {
            this.in = in;
            count = u2(in, 8);
            tag = new int[count];
            utf = new String[count];
            int p = 10;
            for (int i = 1; i < count; i++) {
                int t = u1(in, p);
                tag[i] = t;
                switch (t) {
                    case 1: {
                        int len = u2(in, p + 1);
                        utf[i] = new String(in, p + 3, len, java.nio.charset.StandardCharsets.ISO_8859_1);
                        utfIndex.putIfAbsent(utf[i], i);
                        p += 3 + len;
                        break;
                    }
                    case 3: case 4: case 9: case 10: case 11: case 12: case 17: case 18: p += 5; break;
                    case 5: case 6: p += 9; i++; break;
                    case 7: case 8: case 16: case 19: case 20: p += 3; break;
                    case 15: p += 4; break;
                    default: throw new IllegalStateException("bad cp tag " + t);
                }
            }
            end = p;
            next = count;
        }

        int utf8(String s) {
            Integer i = utfIndex.get(s);
            if (i != null) return i;
            Integer a = added.get("u:" + s);
            if (a != null) return a;
            extra.u1(1);
            extra.u2(s.length());
            for (int k = 0; k < s.length(); k++) extra.u1(s.charAt(k));
            added.put("u:" + s, next);
            return next++;
        }

        int cls(String name) {
            String key = "c:" + name;
            Integer a = added.get(key);
            if (a != null) return a;
            int n = utf8(name);
            extra.u1(7);
            extra.u2(n);
            added.put(key, next);
            return next++;
        }

        int methodref(String owner, String name, String desc) {
            String key = "m:" + owner + "." + name + desc;
            Integer a = added.get(key);
            if (a != null) return a;
            int c = cls(owner), n = utf8(name), d = utf8(desc);
            extra.u1(12);
            extra.u2(n);
            extra.u2(d);
            int nat = next++;
            extra.u1(10);
            extra.u2(c);
            extra.u2(nat);
            added.put(key, next);
            return next++;
        }
    }

    static byte[] patch(byte[] in, List<Hook> hooks) {
        if (u4(in, 0) != 0xCAFEBABE) return null;
        int major = u2(in, 6);
        if (major < 50) return null;

        Cp cp = new Cp(in);
        int p = cp.end + 6;                    // access, this, super
        p += 2 + 2 * u2(in, p);                // interfaces
        int fields = u2(in, p);
        p += 2;
        for (int i = 0; i < fields; i++) {
            p += 6;
            int ac = u2(in, p);
            p += 2;
            for (int a = 0; a < ac; a++) p += 6 + u4(in, p + 2);
        }
        int methodsStart = p;
        int methods = u2(in, p);
        p += 2;

        Out mout = new Out();
        mout.u2(methods);
        int patched = 0;
        for (int i = 0; i < methods; i++) {
            int mstart = p;
            String name = cp.utf[u2(in, p + 2)];
            String desc = cp.utf[u2(in, p + 4)];
            int ac = u2(in, p + 6);
            int q = p + 8;
            int[] attrStart = new int[ac];
            for (int a = 0; a < ac; a++) {
                attrStart[a] = q;
                q += 6 + u4(in, q + 2);
            }
            int mend = q;

            Hook hook = null;
            for (Hook h : hooks) if (h.name.equals(name) && h.desc.equals(desc)) { hook = h; break; }

            byte[] rewritten = null;
            if (hook != null) {
                rewritten = rewriteMethod(in, cp, mstart, ac, attrStart, mend, hook, major);
            }
            if (rewritten != null) {
                mout.raw(rewritten);
                patched++;
            } else {
                mout.raw(in, mstart, mend - mstart);
            }
            p = mend;
        }
        if (patched == 0) return null;

        Out out = new Out();
        out.raw(in, 0, 8);
        out.u2(cp.next);
        out.raw(in, 10, cp.end - 10);
        out.raw(cp.extra.bytes());
        out.raw(in, cp.end, methodsStart - cp.end);
        out.raw(mout.bytes());
        out.raw(in, p, in.length - p);
        return out.bytes();
    }

    private static byte[] rewriteMethod(byte[] in, Cp cp, int mstart, int ac, int[] attrStart, int mend, Hook hook, int major) {
        boolean ctor = hook.name.equals("<init>");
        if (ctor && hook.skip) return null;

        // Код возврата по умолчанию для SKIP-хуков
        byte[] retSeq = null;
        if (hook.skip) {
            char r = hook.desc.charAt(hook.desc.indexOf(')') + 1);
            switch (r) {
                case 'V': retSeq = new byte[] {(byte) 0xb1}; break;
                case 'Z': case 'B': case 'C': case 'S': case 'I': retSeq = new byte[] {0x03, (byte) 0xac}; break;
                case 'L': case '[': retSeq = new byte[] {0x01, (byte) 0xb0}; break;
                default: return null;
            }
        }

        int codeAttr = -1;
        for (int a = 0; a < ac; a++) {
            if ("Code".equals(cp.utf[u2(in, attrStart[a])])) { codeAttr = a; break; }
        }
        if (codeAttr < 0) return null;

        int ref = cp.methodref(GUARD, hook.guard, hook.guardDesc());

        // ---- префикс
        Out body = new Out();
        for (int i = 0; i < hook.slots.length; i++) {
            int slot = hook.slots[i];
            if (slot > 255) return null;
            if (hook.isInt[i]) {
                if (slot < 4) body.u1(0x1a + slot); else { body.u1(0x15); body.u1(slot); }
            } else {
                if (slot < 4) body.u1(0x2a + slot); else { body.u1(0x19); body.u1(slot); }
            }
        }
        body.u1(0xb8);
        body.u2(ref);
        if (hook.skip) {
            body.u1(0x99);                          // ifeq
            body.u2(3 + retSeq.length);
            body.raw(retSeq);
        }
        int pad = (4 - body.size() % 4) % 4;
        Out prefix = new Out();
        for (int i = 0; i < pad; i++) prefix.u1(0x00);   // nop в самом начале (выравнивание для tableswitch)
        prefix.raw(body.bytes());
        byte[] pre = prefix.bytes();
        int n = pre.length;
        if (hook.skip) {
            // ifeq-смещение считается от адреса самой инструкции ifeq; пересчитываем с учётом nop в начале не нужно:
            // смещение относительно ifeq не зависит от позиции.
        }

        // ---- разбор Code
        int a = attrStart[codeAttr];
        int bodyPos = a + 6;
        int maxStack = u2(in, bodyPos);
        int maxLocals = u2(in, bodyPos + 2);
        int codeLen = u4(in, bodyPos + 4);
        int codePos = bodyPos + 8;
        if (codeLen + n > 65535) return null;
        int excPos = codePos + codeLen;
        int excCount = u2(in, excPos);
        int attrPos = excPos + 2 + 8 * excCount;
        int codeAttrCount = u2(in, attrPos);
        attrPos += 2;

        Out code = new Out();
        code.u2(Math.max(maxStack, hook.slots.length + 2));
        code.u2(maxLocals);
        code.u4(codeLen + n);
        code.raw(pre);
        code.raw(in, codePos, codeLen);
        code.u2(excCount);
        for (int e = 0; e < excCount; e++) {
            int ep = excPos + 2 + 8 * e;
            code.u2(u2(in, ep) + n);
            code.u2(u2(in, ep + 2) + n);
            code.u2(u2(in, ep + 4) + n);
            code.u2(u2(in, ep + 6));
        }

        // атрибуты Code
        List<byte[]> attrs = new ArrayList<>();
        boolean hadSmt = false;
        int q = attrPos;
        for (int k = 0; k < codeAttrCount; k++) {
            String an = cp.utf[u2(in, q)];
            int len = u4(in, q + 2);
            int dpos = q + 6;
            Out ao = new Out();
            if ("LineNumberTable".equals(an)) {
                ao.u2(u2(in, q));
                ao.u4(len);
                int cnt = u2(in, dpos);
                ao.u2(cnt);
                for (int i = 0; i < cnt; i++) {
                    ao.u2(u2(in, dpos + 2 + 4 * i) + n);
                    ao.u2(u2(in, dpos + 4 + 4 * i));
                }
                attrs.add(ao.bytes());
            } else if ("LocalVariableTable".equals(an) || "LocalVariableTypeTable".equals(an)) {
                ao.u2(u2(in, q));
                ao.u4(len);
                int cnt = u2(in, dpos);
                ao.u2(cnt);
                for (int i = 0; i < cnt; i++) {
                    int e = dpos + 2 + 10 * i;
                    ao.u2(u2(in, e) + n);
                    ao.raw(in, e + 2, 8);
                }
                attrs.add(ao.bytes());
            } else if ("StackMapTable".equals(an)) {
                hadSmt = true;
                byte[] smt = rewriteSmt(in, dpos, n, hook.skip);
                ao.u2(u2(in, q));
                ao.u4(smt.length);
                ao.raw(smt);
                attrs.add(ao.bytes());
            } else if ("RuntimeVisibleTypeAnnotations".equals(an) || "RuntimeInvisibleTypeAnnotations".equals(an)) {
                // содержат смещения в коде — безопасно отбрасываем
            } else {
                ao.raw(in, q, 6 + len);
                attrs.add(ao.bytes());
            }
            q += 6 + len;
        }
        if (!hadSmt && hook.skip) {
            Out smt = new Out();
            smt.u2(1);
            writeSameFrame(smt, n);
            Out ao = new Out();
            ao.u2(cp.utf8("StackMapTable"));
            ao.u4(smt.size());
            ao.raw(smt.bytes());
            attrs.add(ao.bytes());
        }
        code.u2(attrs.size());
        for (byte[] b : attrs) code.raw(b);

        // ---- собираем метод
        Out m = new Out();
        m.raw(in, mstart, 8);                       // access, name, desc, attr_count (оригинальный — число не меняется)
        for (int i = 0; i < ac; i++) {
            if (i == codeAttr) {
                byte[] c = code.bytes();
                m.u2(u2(in, attrStart[i]));
                m.u4(c.length);
                m.raw(c);
            } else {
                m.raw(in, attrStart[i], 6 + u4(in, attrStart[i] + 2));
            }
        }
        return m.bytes();
    }

    private static void writeSameFrame(Out o, int delta) {
        if (delta <= 63) {
            o.u1(delta);
        } else {
            o.u1(251);
            o.u2(delta);
        }
    }

    // ---- StackMapTable

    private static final class Frame {
        int kind;     // 0 same, 1 same1, 2 same1ext, 3 chop, 4 sameext, 5 append, 6 full
        int delta;
        int k;
        byte[] data = new byte[0];      // для same1/append: vti; для full: locals+stack уже закодированные
        int nLocals, nStack;
        byte[] locals = new byte[0], stack = new byte[0];
    }

    private static int copyVti(byte[] in, int p, Out o, int shift) {
        int tag = u1(in, p);
        o.u1(tag);
        if (tag == 7) {
            o.u2(u2(in, p + 1));
            return p + 3;
        }
        if (tag == 8) {
            o.u2(u2(in, p + 1) + shift);        // смещение инструкции new сдвигается вместе с кодом
            return p + 3;
        }
        return p + 1;
    }

    private static byte[] rewriteSmt(byte[] in, int pos, int shift, boolean addFrame) {
        int count = u2(in, pos);
        int p = pos + 2;
        List<Frame> frames = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            Frame f = new Frame();
            int type = u1(in, p++);
            Out vt = new Out();
            if (type < 64) {
                f.kind = 0; f.delta = type;
            } else if (type < 128) {
                f.kind = 1; f.delta = type - 64;
                p = copyVti(in, p, vt, shift);
            } else if (type == 247) {
                f.kind = 2; f.delta = u2(in, p); p += 2;
                p = copyVti(in, p, vt, shift);
            } else if (type >= 248 && type <= 250) {
                f.kind = 3; f.k = 251 - type; f.delta = u2(in, p); p += 2;
            } else if (type == 251) {
                f.kind = 4; f.delta = u2(in, p); p += 2;
            } else if (type >= 252 && type <= 254) {
                f.kind = 5; f.k = type - 251; f.delta = u2(in, p); p += 2;
                for (int j = 0; j < f.k; j++) p = copyVti(in, p, vt, shift);
            } else if (type == 255) {
                f.kind = 6; f.delta = u2(in, p); p += 2;
                f.nLocals = u2(in, p); p += 2;
                Out lo = new Out();
                for (int j = 0; j < f.nLocals; j++) p = copyVti(in, p, lo, shift);
                f.locals = lo.bytes();
                f.nStack = u2(in, p); p += 2;
                Out so = new Out();
                for (int j = 0; j < f.nStack; j++) p = copyVti(in, p, so, shift);
                f.stack = so.bytes();
            } else {
                throw new IllegalStateException("bad frame type " + type);
            }
            f.data = vt.bytes();
            frames.add(f);
        }

        if (!addFrame) {
            if (!frames.isEmpty()) frames.get(0).delta += shift;
        } else if (frames.isEmpty()) {
            Frame nf = new Frame();
            nf.kind = 0;
            nf.delta = shift;
            frames.add(nf);
        } else {
            Frame first = frames.get(0);
            if (first.delta == 0) {
                first.delta = shift;                // исходный кадр на смещении 0 теперь стоит ровно на границе префикса
            } else {
                Frame nf = new Frame();
                nf.kind = 0;
                nf.delta = shift;
                first.delta = first.delta - 1;      // новое смещение (old+shift) относительно нашего кадра на shift
                frames.add(0, nf);
            }
        }

        Out o = new Out();
        o.u2(frames.size());
        for (Frame f : frames) {
            switch (f.kind) {
                case 0:
                    writeSameFrame(o, f.delta);
                    break;
                case 1:
                    if (f.delta <= 63) { o.u1(64 + f.delta); } else { o.u1(247); o.u2(f.delta); }
                    o.raw(f.data);
                    break;
                case 2:
                    o.u1(247); o.u2(f.delta); o.raw(f.data);
                    break;
                case 3:
                    o.u1(251 - f.k); o.u2(f.delta);
                    break;
                case 4:
                    o.u1(251); o.u2(f.delta);
                    break;
                case 5:
                    o.u1(251 + f.k); o.u2(f.delta); o.raw(f.data);
                    break;
                default:
                    o.u1(255); o.u2(f.delta);
                    o.u2(f.nLocals); o.raw(f.locals);
                    o.u2(f.nStack); o.raw(f.stack);
            }
        }
        return o.bytes();
    }
}

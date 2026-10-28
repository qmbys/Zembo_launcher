package dev.zembo.guard;

import java.io.File;
import java.lang.instrument.Instrumentation;
import java.util.jar.JarFile;

/** Точка входа -javaagent. Подключает jar к bootstrap-загрузчику и передаёт управление Bootstrap. */
public final class Agent {
    private Agent() {}

    public static void premain(String args, Instrumentation inst) {
        try {
            if (args == null || args.trim().isEmpty()) {
                System.err.println("[ZemboGuard] config path is missing, guard disabled");
                return;
            }
            File self = new File(Agent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            // Классы Guard вызываются из java.base, поэтому должны жить в bootstrap-загрузчике.
            inst.appendToBootstrapClassLoaderSearch(new JarFile(self));
            Bootstrap.start(args.trim(), inst);
        } catch (Throwable t) {
            System.err.println("[ZemboGuard] failed to start, game continues without guard: " + t);
        }
    }
}

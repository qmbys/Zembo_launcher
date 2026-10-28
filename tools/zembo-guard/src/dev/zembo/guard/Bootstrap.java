package dev.zembo.guard;

import java.lang.instrument.Instrumentation;
import java.util.*;

/** Загружается bootstrap-загрузчиком: читает конфиг, ставит трансформер и ретрансформирует уже загруженные классы JDK. */
public final class Bootstrap {
    private Bootstrap() {}

    public static void start(String configPath, Instrumentation inst) throws Exception {
        int mask = Guard.init(configPath);
        if (mask == 0) {
            System.err.println("[ZemboGuard] no restricted mods in config, nothing to do");
            return;
        }

        // Классы java.base / java.desktop должны «видеть» unnamed-модуль bootstrap-загрузчика, где лежит Guard.
        Module guardModule = Guard.class.getModule();
        Set<Module> targets = new HashSet<>();
        targets.add(Object.class.getModule());
        ModuleLayer.boot().findModule("java.desktop").ifPresent(targets::add);
        for (Module m : targets) {
            inst.redefineModule(m, Set.of(guardModule), Map.of(), Map.of(), Set.of(), Map.of());
        }

        Patcher patcher = new Patcher(mask);
        inst.addTransformer(patcher, true);

        int done = 0;
        for (Class<?> c : inst.getAllLoadedClasses()) {
            if (!patcher.wants(c.getName().replace('.', '/')) || !inst.isModifiableClass(c)) continue;
            try {
                inst.retransformClasses(c);
                done++;
            } catch (Throwable t) {
                System.err.println("[ZemboGuard] cannot retransform " + c.getName() + ": " + t);
            }
        }

        Guard.ready = true;
        Runtime.getRuntime().addShutdownHook(new Thread(Guard::writeReport, "zembo-guard-report"));
        System.err.println("[ZemboGuard] active: " + Guard.describeMods() + "; retransformed " + done + " JDK classes");
    }
}

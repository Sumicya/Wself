pluginManagement {
    repositories {
        // Optional local/self-hosted Maven mirror. Set via:
        //   -PwekitLocalMavenMirror=/path/to/mirror
        //   or env WEKIT_LOCAL_MAVEN_MIRROR=/path/to/mirror
        providers.gradleProperty("wekitLocalMavenMirror")
            .orElse(System.getenv("WEKIT_LOCAL_MAVEN_MIRROR") ?: "")
            .orNull
            ?.takeIf { it.isNotBlank() }
            ?.let { mirror ->
                maven { url = uri(mirror) }
            }

        // Optional China mirror. Opt-in only:
        //   -PwekitUseChinaMirror=true
        if (providers.gradleProperty("wekitUseChinaMirror").orElse("false").get().toBoolean()) {
            maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/")
        }

        mavenCentral()
        gradlePluginPortal()
    }
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Optional local/self-hosted Maven mirror (same property as pluginManagement).
        providers.gradleProperty("wekitLocalMavenMirror")
            .orElse(System.getenv("WEKIT_LOCAL_MAVEN_MIRROR") ?: "")
            .orNull
            ?.takeIf { it.isNotBlank() }
            ?.let { mirror ->
                maven { url = uri(mirror) }
            }

        // Optional China mirror (opt-in only).
        if (providers.gradleProperty("wekitUseChinaMirror").orElse("false").get().toBoolean()) {
            maven("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/")
        }

        maven("https://jitpack.io") {
            content {
                includeGroup("com.github.Ujhhgtg")
                includeGroup("com.github.Ujhhgtg.rhino")
                includeGroup("com.github.topjohnwu.libsu")
            }
        }
        maven("https://api.xposed.info/") {
            content {
                includeGroup("de.robv.android.xposed")
            }
        }
        mavenCentral()
    }

    versionCatalogs {
        create("libs")
    }
}

rootProject.name = "wekit"

include(
    ":app",
    ":libs:common:annotation-scanner",
    ":libs:common:stubs",
    ":libs:common:bsh",
    ":libs:common:reflekt"
)

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val appProjectDir = projectDir
val scriptsDir = rootProject.projectDir.parentFile.resolve("scripts")
val cliAssetsDir = appProjectDir.resolve("src/main/assets/cli")
val cliBundleDir = appProjectDir.resolve("src/main/cli-binaries")
val cliJniLibsDir = appProjectDir.resolve("src/main/jniLibs")
val cliAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")

tasks.register("prepareCliAssets") {
    group = "build setup"
    description = "Prepare bundled Speedtest CLI binaries for Android assets."

    doLast {
        fun syncCliOutputsFromBundle() {
            delete(cliAssetsDir)
            copy {
                from(cliBundleDir)
                into(cliAssetsDir)
                include("**/speedtest")
            }
            cliAssetsDir
                .walkTopDown()
                .filter { it.isFile && it.name == "speedtest" }
                .forEach { it.setExecutable(true, true) }

            delete(cliJniLibsDir)
            for (abi in cliAbis) {
                val source = cliBundleDir.resolve("$abi/speedtest")
                if (!source.exists()) {
                    continue
                }
                val targetDir = cliJniLibsDir.resolve(abi).apply { mkdirs() }
                val target = targetDir.resolve("libspeedtest.so")
                source.copyTo(target, overwrite = true)
                target.setExecutable(true, true)
            }
        }

        val hasDownloadUrl = !System.getenv("OOKLA_CLI_AARCH64_TGZ_URL").isNullOrBlank()
        val isWindows = System.getProperty("os.name")
            .lowercase()
            .contains("windows")

        if (hasDownloadUrl) {
            val fetchScript = if (isWindows) {
                scriptsDir.resolve("fetch_cli_binaries.ps1").absolutePath
            } else {
                scriptsDir.resolve("fetch_cli_binaries.sh").absolutePath
            }
            if (isWindows) {
                exec {
                    commandLine(
                        "powershell",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        fetchScript,
                    )
                }
            } else {
                exec {
                    commandLine("bash", fetchScript)
                }
            }
        }

        if (cliBundleDir.exists()) {
            syncCliOutputsFromBundle()
        } else {
            logger.lifecycle(
                "Speedtest CLI bundle not provided. " +
                    "Set OOKLA_CLI_AARCH64_TGZ_URL or place binaries under " +
                    "android/app/src/main/cli-binaries/<abi>/speedtest.",
            )
        }

        val primaryBinary = cliAssetsDir.resolve("arm64-v8a/speedtest")
        val primaryNativeBinary = cliJniLibsDir.resolve("arm64-v8a/libspeedtest.so")
        val allowMissingCli =
            System.getenv("SPEEDTEST_ALLOW_MISSING_CLI")
                ?.equals("true", ignoreCase = true) == true
        if (primaryBinary.exists() && primaryNativeBinary.exists()) {
            logger.lifecycle("Bundled Speedtest CLI asset: ${primaryBinary.absolutePath}")
            logger.lifecycle("Bundled Speedtest CLI native lib: ${primaryNativeBinary.absolutePath}")
        } else {
            val message =
                "Speedtest CLI arm64 binary not bundled: ${primaryBinary.absolutePath}. " +
                    "Set OOKLA_CLI_AARCH64_TGZ_URL or add " +
                    "android/app/src/main/cli-binaries/arm64-v8a/speedtest."
            if (allowMissingCli) {
                logger.warn(message)
            } else {
                throw GradleException("$message To bypass, set SPEEDTEST_ALLOW_MISSING_CLI=true.")
            }
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("prepareCliAssets")
}

android {
    namespace = "com.example.speedtest"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.speedtest"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.13.2")
}

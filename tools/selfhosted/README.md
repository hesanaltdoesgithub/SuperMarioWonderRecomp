# Building the Android APK with a self-hosted GitHub Actions runner

The workflow `.github/workflows/android-apk-selfhosted.yml` runs on **your own Linux machine**. Your dump, keys and
the APK built from them never leave it: nothing is uploaded, and the workflow only starts when you run it by hand.

## One time

1. **Toolchain.** On the machine, in a clone of this repo:
   ```sh
   bash tools/selfhosted/setup.sh
   ```
   It installs a few pacman packages (Arch/CachyOS), then puts Vulkan headers, .NET, the Ryujinx shader translator
   source, a Python venv and the Android SDK/NDK in `~/wonder-recomp-private/third_party` (about 6 GB). It asks you to
   accept the Android SDK licences.
2. **Your files.** Put `prod.keys`, `title.keys` and the Wonder **1.0.0** `.xci` (or `.nsp`) in one folder, e.g.
   `~/wonder`. Never inside the repo.
3. **Runner.** On GitHub: your fork → Settings → Actions → Runners → **New self-hosted runner** → Linux x64, and
   run the commands it shows on the machine. Start it with `./run.sh` (or install it as a service with `./svc.sh`).
4. **Safety.** Settings → Actions → General → "Fork pull request workflows from outside collaborators" →
   **Require approval for all external contributors**, so nobody else's code can run on your laptop.

## Each build

Actions tab → **Build Android APK (self-hosted)** → Run workflow. Inputs: the folder from step 2, the job count,
and whether to also make the ~4 GB data zip.

Every stage resumes: if the laptop sleeps or the run is cancelled, run it again and finished stages are skipped.
The result is `~/wonder-recomp-private/wonder/apk/wonder.apk`.

Without Actions, the same build runs directly: `bash tools/selfhosted/build_android.sh ~/wonder`.

## Weak machines

Expect roughly: import 5–15 min, CPU recompile 10–30 min (needs ~2.5 GB free RAM), shaders 5–20 min, APK 1–6+ hours.
About 2 GB of RAM per compile job; `auto` picks RAM/2 jobs. With 8 GB or less, close other apps or set `jobs` to 1–2;
running out of memory looks like a compiler killed by signal 9. You need about 25–30 GB of free disk.

The APK and data zip contain code and data from your dump: **for your own use only, never share them.**

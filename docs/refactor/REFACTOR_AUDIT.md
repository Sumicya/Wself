# WCX 重构审计与路线图

> 范围：`Sumicya/Wself` 当前 checkout（分支 `arena/01a07a0b-wself`）。
> 目标关键词：**简化 · 原生化 · 自由化 · 现代化**。
> 说明：审计基于源码静态检查完成；当前沙箱无 JDK / Android SDK / cargo，
> 无法跑 Gradle 与 Rust 构建验证，请在 CI 或本机执行 `./x build` 验证。

---

## 1. 项目现状画像

- 主模块：`app/`，约 **689 个 Kotlin 文件 / 约 15.7 万行**，另有 Rust native 库、Python 脚本、去混淆工具、Agent/MCP 子系统、主题与脚本引擎。
- 构建：AGP 9 + Kotlin 2.4 + KSP + Compose + Gradle 版本目录，Rust workspace（`wekit-native` + `xtask`）。
- 入口：`standard`（libxposed 101/102）/ `legacy`（Xposed API 51+）双变体，另有 Frida、Zygisk 入口代码。
- 版本：`app/build.gradle.kts` 中 `versionCode = 247 / versionName = v247` 为 **写死**；
  `VERSIONING.md` 描述的是自动版本，但当前 checkout 是压平的浅克隆（仅 1 个 commit），
  若直接改成“commit 计数自动递增”会让版本号回退，所以本期保留显式基线并标注 TODO。
- 数据与配置：MMKV（`WePrefs`）+ Room + 文件工作区。
- 外部依赖：网络/模型（OpenAI/Anthropic/MCP）、Osmdroid、Miuix、Coil、Rhino、DexKit、Ktor、Markwon 等，体量较大。

---

## 2. 审计发现（按四方向）

### 2.1 简化（Simplify）

| 现状 | 问题 | 建议 / 状态 |
|---|---|---|
| 仓库内跟踪了大量 `*.bak_vNNN`、`settings.gradle.kts.bak`、`gradle-wrapper.properties.bak` | 纯死文件，污染仓库，可能被误编译/误引用 | ✅ 已删除（15 个） |
| `app/build.gradle.kts` 有 `getCommitCount()`、`commitCount`、`versionBaseOffset` | `commitCount`/`versionBaseOffset` 实际未使用，且 `VERSIONING.md` 与代码不一致 | ✅ 已删除未用变量，保留显式版本基线 |
| `settings.gradle.kts` 写死 `file:///root/maven-mirror` | 绑定机器/CI 环境，离开该路径即中断 | ✅ 已改为可选 `wekitLocalMavenMirror` / `WEKIT_LOCAL_MAVEN_MIRROR` |
| `gradle.properties` 写死 `org.gradle.java.installations.paths=/opt/jdk/jdk-17.0.2` | 绑定单机 JDK 路径，其他机器/CI 不稳定 | ✅ 已移除，统一走 `JAVA_HOME`/Gradle toolchain |
| `androidResources.localeFilters += setOf("zh")` | 强制只保留中文资源，不利于国际化/二次开发 | ✅ 已移除，保留全部 locale |
| `app/` 内仍有大量死代码/注释放置（`embedMonetAssets` 等被注释、BouncyCastle/ARSCLib 被注释） | 需要在后续清理阶段确认是否保留 | ✅ 已删除：无引用的 `EmbedMonetAssetsTask.java`、注释块 `embedMonetAssets`/`arsclib`/`apksig`/`bouncycastle`/`resolutionStrategy`、`useActivityInsteadOfDialog` |
| `docs/` 与 `docs/gitbook/` 并存 | `docs/gitbook` 为过期 GitBook 导出，引用旧上游 repo | ✅ 已删除整个 `docs/gitbook/`，保留根目录 `docs/` |

### 2.2 原生化（Nativize）

现状（已原生化部分）：

- Rust 库已有 JNI 暴露：崩溃处理、Markdown→HTML、音频 `anyToSilk/silkToPcm/pcmToMp3`、Telegram 贴纸 `tgsToGif/webmToGif`、签名校验。
- `wekit-native` 约 **4966 行 Rust**，含 `nuke_client`（1679 行）、`native_hook`（630 行）、音频（550 行）、闪光等。

建议优先级（本期未做，因为改动面大、需要设备与 CI 验证）：

1. **定型 JNI ABI**：当前 JNI 方法按单一类绑定，建议抽象成稳定的 `NativeBridge` + 版本化 ABI，
   并让 Java 侧只经 `NativeBridge` 调用，避免散落的 `external "C"` 方法。
2. **热路径下沉**：媒体转换、Hash/加密、日志、原生 Hook 已 native；下一步把
   特征库缓存（`CloudFeatureDB` 的读/写/增量合并）与 Dex 扫描结果缓存下沉为 Rust 管理的文件/映射层。
3. **libxposed API 102 热重载深化**：已有 `Lsp10xUnifiedHookEntry` 检测 `>=102` 并触发 `ModuleLoader.hotReload()`；
   建议继续：把“配置变更→热重载生效”做成用户可感知状态，并把 settings 变更通过 API 102 热重载回调统一刷新，
   而不是依赖进程重启。
4. **ABI 支持收敛**：`xtask` 与 Android `splits` 不一致（xtask 支持 x86_64/x86，Gradle 只打包
   arm64/armeabi-v7a）。若目标是精简，建议把 Native ABI 收敛到 **arm64-v8a + armeabi-v7a**，
   减少维护面；若目标是兼容旧设备再保留 x86。
5. **移除/替换重依赖**：`Miuix`、`Coil(+gif+okhttp)`、`Rhino`、`Markwon`、`Osmdroid`、`Fastjson2` 等都可评估
   用平台能力或更轻实现替代，属于“原生化/现代化”中长期的体积优化方向。

### 2.3 自由化（Liberalize / 去绑定）

| 现状 | 问题 | 建议 / 状态 |
|---|---|---|
| `CloudFeatureDB.CLOUD_URL` 写死 `https://wcx-features.example.com/...`（示例域名） | 要么无效、要么潜在成为中心化依赖 | ✅ 已改为默认空 URL（关闭云同步），可通过 `WePrefs` 配置自托管地址与更新间隔 |
| 云请求 `module_version=${HostInfo.versionName}` | 传的是宿主（微信）版本，不是模块版本，是明显 bug | ✅ 已改为 `module_version=${BuildConfig.VERSION_CODE}`，并将 URL 拼接改为兼容已有 query 的 `&` |
| 更新源 `AppUpdater` 写死 `Johnny520/wcx` | 绑定旧上游仓库，fork 无法使用自己的 Release | ✅ 已改为默认 `Sumicya/Wself`，支持 `WePrefs` 键 `app_update_repo` 覆盖，置空可禁用更新 |
| 微信版本门槛：`WeChatVersions` 中大量版本常量，但实际 `HostInfo.versionCode` 使用仅 3 处，且存在全自动适配（`AutoAdaptationManager`/`DexKit`） | 版本绑定已大幅弱化，基本自适应 | 🕐 长期建议：把版本判断收敛到 `VersionPolicy`，新版本默认“尝试 + 降级”而非拒绝 |
| 运行时/在线校验类依赖 | 未发现明显强制在线校验；主要是模型 API、天气 API、MCP 等用户主动配置项 | 🕐 建议设置默认全部离线，联网功能做成显式开关 |

### 2.4 现代化（Modernize）

- 已在 AGP 9 / Kotlin 2.4 / Compose BOM 上，方向正确。
- `org.gradle.configuration-cache=false` 仍关闭，建议后续开启并修复配置缓存不兼容点。
- `gradle-wrapper.properties` 之前写死腾讯镜像；✅ 已改为官方 `services.gradle.org`，需要镜像时在本地改 wrapper。
- `compose-material3 = 1.5.0-alpha19` 被注释为“不要升级”（Google 破坏 Ripple），这是已知痛处，属于工程风险；建议后续隔离为依赖升级任务，不要随意动。
- `VERSIONING.md` 与构建脚本不一致；建议二选一：恢复完整 git 历史后的自动版本，或明确改成“显式基线 + 发布流水线赋予版本”。
- `settings.gradle.kts` 的 `rootProject.name = "wekit"` 与品牌 `WCX` 不完全一致，改名会影响产物路径，需专项处理。

---

## 3. 本期已实施改动

| 文件 | 改动 | 方向 |
|---|---|---|
| `gradle/wrapper/gradle-wrapper.properties.bak` 等 15 个备份/临时文件 | 删除 | 简化 |
| `settings.gradle.kts` | 移除 `file:///root/maven-mirror` 与强制中国镜像；支持 `-PwekitLocalMavenMirror` / `WEKIT_LOCAL_MAVEN_MIRROR` / `-PwekitUseChinaMirror` | 简化 / 自由化 / 现代化 |
| `gradle.properties` | 移除单机 JDK 路径；补充可选镜像配置说明 | 自由化 / 现代化 |
| `app/build.gradle.kts` | 移除未用 `getCommitCount/commitCount/versionBaseOffset`；移除 `localeFilters += setOf("zh")`；清理注释死块 | 简化 / 自由化 |
| `app/src/main/java/.../dynamic/CloudFeatureDB.kt` | 云端特征库改为默认禁用 + 可配置 URL/更新间隔；修复 `module_version` 参数与 query 拼接 | 自由化 |
| `app/src/main/java/.../utils/AppUpdater.kt` | 更新源改为默认 `Sumicya/Wself`，支持 `WePrefs` 覆盖/禁用 | 自由化 |
| `MainActivity` / `SettingsPager` / `ApiServer` | 运行时仓库/官网链接指向当前仓库 | 自由化 |
| `gradle/wrapper/gradle-wrapper.properties` | 腾讯镜像 → 官方 Gradle 分发地址 | 现代化 |
| `.gitattributes` / `.gitignore` | 文本行尾标准化；忽略本地配置、签名、构建产物、Rust target | 现代化 |
| `buildSrc/.../EmbedMonetAssetsTask.java` | 删除未引用任务 | 简化 |
| `docs/gitbook/` | 删除过期 GitBook 导出，根文档仓库链接指向当前仓库 | 简化 / 自由化 |
| `docs/refactor/REFACTOR_AUDIT.md` | 本审计与路线图 | 文档 |

---

## 4. 后续路线图（建议顺序）

1. **验证期**：在本机/CI 执行 `./x build`，确认本期改动可构建、可安装、功能不回归。
2. **清理期**：确认并删除未使用的 `deobf`、`scripts`、`embedded/monet` 注释任务、未启用入口（`frida`/`zygisk` 等是否保留）。
3. **原生化 ABI 定型**：统一 JNI bridge；把特征库缓存、Dex 扫描结果缓存、配置快照下沉 Rust。
4. **API 102 热重载体验**：设置页“热重载/重启”状态提示；支持配置变更后自动 `ModuleLoader.hotReload()`。
5. **现代化构建**：尝试 `configuration-cache`；统一 `VERSIONING.md` 与构建；评估依赖替换与包体优化。
6. **自由化默认值**：所有网络功能默认关闭；云端/代理/模型地址全部用户显式配置。

### 在 Termux 上验证构建

如果当前机器没有构建环境，可在 Android 手机的 Termux 里做一次构建验证：

```bash
# 1. 基础环境
pkg update && pkg upgrade
pkg install git openjdk-21 wget unzip p7zip python -y

# 2. 安装 Android SDK/NDK（推荐用社区安装器，会同时配置 aapt2 覆盖与 env）
#    https://github.com/Willie169/termux-android-sdk-ndk
wget https://raw.githubusercontent.com/Willie169/termux-android-sdk-ndk/refs/heads/main/install.sh
chmod +x install.sh
./install.sh

# 3. 重新进入 shell 后验证
java -version
sdkmanager --list_installed
ls "$ANDROID_HOME"

# 4. 拉取并构建（先只编译 native 与 Android 配置）
cd ~
git clone https://github.com/Sumicya/Wself.git
cd Wself
./x build --release
# 产物在 app/build/outputs/apk/standard/release/
```

> ⚠️ Termux 的 NDK/compileSdk 与宿主机可能有差异；`compileSdk 37`/`targetSdk 37` 可能需要在
> `sdkmanager --install "platforms;android-37"` 或降级到本机可用版本后重试。
> `app/src/main/jniLibs/*/*.so` 为已提交的 native 二进制，若不重建 Rust 也可直接走 Gradle 构建。

---

## 5. 风险与验证约束

- 当前环境**没有** JDK、Android SDK、NDK、cargo，无法执行 `./x build`、`./gradlew` 或 `cargo check`。
- 本期改动都是删除死文件/死代码、放开镜像与 locale、以及把云端特征库改成可选，
  **不改变运行期行为默认路径**（云同步默认关闭意味着模块不再尝试连示例域名）。
- 下一步请先跑 `./x build`，并人工验证：
  - settings 能解析仓库（不用 local mirror 时）；
  - 云特征库关闭时，`AutoAdaptationManager` 仍能本地动态适配；
  - 正常安装后主功能（聊天增强 / 美化 / 隐私）不回归。

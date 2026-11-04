# LumeiXiang

> **LumeiXiang** 是 [LumeBox](https://github.com/teng662858/LumeBox) 的安卓衍生版。
> 衍生版在上游代码基础上对 Android 端做了全量适配与体验优化，应用展示名由此更名。
> **特别感谢上游仓库 [teng662858/LumeBox](https://github.com/teng662858/LumeBox) 作者的付出**——
> 没有上游持续的高质量开发（图源引擎、播放器、阅读器、聚合搜索、dongpiandi 源等），
> 就没有这个衍生版。所有核心能力均来自上游，本仓库的贡献聚焦在 Android 平台落地。

## 目前的成果（android-1.0.2 分支）

- **图源引擎全量解锁**：修复 QuickJS 原生库名探测，Android 开放漫画 / 视频 / REX / 猫源全链路（此前上游仅 iOS 可用，Android 全部页面骨架）
- **播放内核开放**：MPV（libmpv，全 ABI 随包，ffmpeg 软解兜底）对 Android 开放，修复播放报 `video player had error … source error` 的问题；平台门改为「任一内核可用」口径
- **性能优化**：阅读器面板毛玻璃在 Android 降级为纯色材质（消除全屏 BackdropFilter 逐帧重算导致的打开漫画卡顿）；解锁 120Hz 高刷新率
- **原生通道补齐**：电量状态栏（此前 Android 恒显示「—」）、阅读器亮度独立调节、任务切换防窥（FLAG_SECURE）、WAF 校验 HttpOnly Cookie 回传（cf_clearance）、本地凭证加密（AndroidKeyStore）
- **翻译门控 Android 化**：设备端翻译仅 iOS 提供，Android 不再出现「iOS 18」提示，存量配置自动降级 AI 翻译
- **同步上游 254 个提交**（聚合搜索、dongpiandi 源、Kokoro / MiMo 语音、跳过标记、设置重组等），版本 1.0.2，APK 体积瘦身 372MB → 160.6MB（arm64）
- **质量护栏**：13 项集成测试（引擎门 / 导入链路 / 五通道 / 平台门）+ 23 项单元测试全绿

## 分支说明

| 分支 | 内容 |
| --- | --- |
| `main` | 原开发主线（含 iOS 构建链路） |
| `android-1.0.2` | 安卓衍生版：上游 254 提交同步 + Android 全量适配（版本 1.0.2） |
| `backup-pre-sync-1104` | 同步前状态备份 |

## 下载安装

APK 在 [Releases](https://github.com/tglingming/LumeBox/releases) 页发布：
`LumeiXiang-1.0.2-arm64.apk`（主流 64 位机型推荐，S24U 等）或
`LumeiXiang-1.0.2-all.apk`（全机型通用）。使用 debug 签名，请侧载安装。

## 致谢

- 上游仓库：[teng662858/LumeBox](https://github.com/teng662858/LumeBox)
- 播放内核：[media-kit](https://github.com/media-kit/media-kit)（libmpv）
- JS 引擎：[QuickJS](https://github.com/bigcatbin/quickjs_c_bridge_plugin)
- 加密：[pointycastle](https://github.com/pointycastle/pointycastle) / Android Keystore
- 字体与图标、弹弹play 开放弹幕网络及所有开源依赖的作者

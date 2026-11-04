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

## 使用说明（原主线文档）

- [片头片尾识别、手动打点、模型替换与日志](docs/2026-10-19_片头片尾识别接入.md)
- [漫画阅读器的截图对照与操作验收](docs/2026-10-18_漫画阅读器截图对照验收.md)
- [主题色、字体与自适应颜色设置](docs/2026-10-18_个性化设置.md)

底部导航为漫画／视频／设置，猫源从视频选择器进入，网页主页支持长按排序。视频源支持通用 Python Spider、Python／JS 多文件 ZIP 源包、ESM／CommonJS 依赖加载、JS Spider 及远程 T4／RPC，见 [三 TAB 与多文件源包](docs/2026-10-20_三TAB与多文件源包.md)。Python 代码在 App 进程内执行，请仅导入可信来源；Android Java／DEX 需外部后端，原生扩展需随 iOS 构建签名。

Rex 明文经典 Widget 已接入参数、同步存储／共享缓存、搜索到播放和集合解析；大师兄、采集聚合、荐片已通过原文件离线链路及重开测试。REXENC／FWENC 加密模块尚未接通密钥加载，详见 [Rex Widget 接入范围](docs/2026-10-20_Rex-Widget接入.md)。

## 打包产物（未签名 IPA）

**构建产物统一放 `ipa/`**（目录已忽略，不进版本库）。文件名带**构建号**：

```
ipa/LumeBox-unsigned-1.0.<run_number>.ipa
```

拉最新一次 CI 构建（`gh` 已登录即可）：

```bash
bash tool/fetch_ipa.sh        # 等价于「把最新成功的 IPA 拉到 ipa/」
bash tool/fetch_ipa.sh <run>  # 指定某次 run
```

装到手机后**核对装的是哪一版**：设置 →「关于」会显示
`LumeBox · 版本 1.0.<run_number>（构建 <run_number>）`——与文件名对上才是这一版。
（以前所有包都是 `1.0.0(1)`、文件名也一直相同，装上旧包看不出来，真机踩过一次
「代码改了但界面没变」。）

### 公共弹幕服务

播放器同时保留源弹幕，并支持[弹弹play开放弹幕网络](https://www.dandanplay.com/)及兼容 API。
在播放器“更多 → 弹幕服务地址”中选择 Cynn、Wenjian、官方服务或自定义 HTTPS 部署前缀；支持 [danmu_api](https://github.com/huangxd-/danmu_api) 的搜索与弹幕接口。默认使用用户指定的 Cynn 地址；服务无结果或不稳定时可换服务。匹配不唯一时使用“匹配公共弹幕”选择对应作品和集数。

官方服务须按[官方接入说明](https://doc.dandanplay.com/open/)申请应用凭证。iOS 配置保存在设备钥匙串，签名仅发到官方主机；第三方兼容服务不接收官方凭证。没有对应弹幕的作品不生成模拟弹幕。

## 致谢

- 上游仓库：[teng662858/LumeBox](https://github.com/teng662858/LumeBox)
- 播放内核：[media-kit](https://github.com/media-kit/media-kit)（libmpv）
- JS 引擎：[QuickJS](https://github.com/bigcatbin/quickjs_c_bridge_plugin)
- 加密：[pointycastle](https://github.com/pointycastle/pointycastle) / Android Keystore
- 字体与图标、弹弹play 开放弹幕网络及所有开源依赖的作者

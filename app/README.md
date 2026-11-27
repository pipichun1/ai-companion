# App 构建说明

## 通用版（开源默认）

```bash
cd app
flutter pub get
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

```
包名    top.example.aicompanion
名称    AI Companion
默认地址  空（用户自己在设置里填）
```

## 私有版（带自己的品牌与默认连接）

用环境变量 + `--dart-define` 覆盖，**不用改任何源码**：

```bash
export APP_ID=top.example.myapp          # Android 包名
export APP_LABEL="我的应用"               # 桌面图标下的名字

flutter build apk --release \
  --dart-define=BRAND="我的应用" \
  --dart-define=DEFAULT_BASE=https://your-domain.com \
  --dart-define=DEFAULT_TOKEN=你的令牌
```

字段对应：

| 参数 | 作用 | 不填时 |
| --- | --- | --- |
| `APP_ID` | Android applicationId（装机的唯一身份） | `top.example.aicompanion` |
| `APP_LABEL` | 桌面显示名 | `AI Companion` |
| `BRAND` | App 内标题、设置页、默认会话名 | `AI 伴侣` |
| `DEFAULT_BASE` | 首次启动的服务器地址 | 空，用户自己填 |
| `DEFAULT_TOKEN` | 首次启动的令牌 | 空，用户自己填 |

> ⚠️ 升级已有安装时，`APP_ID` 必须与原包名一致（例如 `top.xdafeiyu.dafeiyu_app`），
> 否则会装成两个 App、数据不互通。

## 注意事项

**路径不能带中文**

```
Gradle 不接受含非 ASCII 字符的项目路径，安卓构建会直接失败。
把仓库放在纯英文路径下，例如 D:\dev\aicompanion
```

**快捷写法**

Windows 下可以用一个 `build_private.ps1` 把上面的环境变量和参数包起来，
避免每次手打。

**图标与启动页**

`android/app/src/main/res/mipmap-*/` 与 `drawable/launch_background.xml`，
换成自己的即可；仓库里默认是占位图。

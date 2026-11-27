/// 品牌与默认连接配置。
///
/// 这个文件是**唯一**允许出现"默认地址 / 默认令牌 / 品牌名"的地方。
/// 公开仓库里这些值都是中性的，私有版本在编译时用 --dart-define 覆盖：
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=BRAND=我的应用 \
///   --dart-define=DEFAULT_BASE=https://example.com \
///   --dart-define=DEFAULT_TOKEN=xxxx
/// ```
class AppConfig {
  AppConfig._();

  /// 显示名：窗口标题、设置页、默认会话名
  static const String brand =
      String.fromEnvironment('BRAND', defaultValue: 'AI 伴侣');

  /// 首次启动时的服务器地址，留空表示用户自己填
  static const String defaultBase =
      String.fromEnvironment('DEFAULT_BASE', defaultValue: '');

  /// 首次启动时的令牌，留空表示用户自己填
  static const String defaultToken =
      String.fromEnvironment('DEFAULT_TOKEN', defaultValue: '');

  /// 默认会话名（未设置时为 brand）
  static String get defaultConvName => brand;
}

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

const kDefaultBase = AppConfig.defaultBase;
const kDefaultToken = AppConfig.defaultToken;
const kDefaultConv = 'main';

class Settings {
  Settings(this.base, this.token, this.conv);
  String base;
  String token;
  String conv;

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    return Settings(
      p.getString('base') ?? kDefaultBase,
      p.getString('token') ?? kDefaultToken,
      p.getString('conv') ?? kDefaultConv,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('base', base);
    await p.setString('token', token);
    await p.setString('conv', conv);
  }
}

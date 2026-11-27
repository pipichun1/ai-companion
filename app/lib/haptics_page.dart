import 'package:flutter/material.dart';

import 'haptics.dart';
import 'prefs.dart';
import 'theme.dart';

/// 震动反馈设置
class HapticsPage extends StatefulWidget {
  const HapticsPage({super.key});

  @override
  State<HapticsPage> createState() => _HapticsPageState();
}

class _HapticsPageState extends State<HapticsPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = prefs.palette;
        return Scaffold(
          appBar: AppBar(title: const Text('震动反馈')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              SwitchListTile(
                title: const Text('震动反馈'),
                subtitle: Text('关掉后所有震动都停止',
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                value: prefs.hapticsEnabled,
                onChanged: (v) async {
                  await prefs.setHapticsEnabled(v);
                  await Haptics.select();
                  if (mounted) setState(() {});
                },
              ),
              SwitchListTile(
                title: const Text('她回消息时震动'),
                subtitle: Text(
                    prefs.hapticsEnabled
                        ? '只控制她说话；你发消息不震'
                        : '先打开上面的开关',
                    style:
                        TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                value: prefs.chatVibrate,
                onChanged: prefs.hapticsEnabled
                    ? (v) async {
                        await prefs.setChatVibrate(v);
                        await Haptics.select();
                        if (mounted) setState(() {});
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

}

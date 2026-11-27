import 'package:flutter/material.dart';

import 'haptics.dart';
import 'prefs.dart';
import 'theme.dart';

/// 聊天显示：字体、气泡透明度、输入栏毛玻璃
class ChatDisplayPage extends StatefulWidget {
  const ChatDisplayPage({super.key, this.palette});

  final Palette? palette;

  @override
  State<ChatDisplayPage> createState() => _ChatDisplayPageState();
}

class _ChatDisplayPageState extends State<ChatDisplayPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPrefs.instance,
      builder: (context, _) {
        final prefs = AppPrefs.instance;
        final palette = widget.palette ?? prefs.palette;
        return Theme(
          data: buildTheme(palette),
          child: Scaffold(
          appBar: AppBar(title: const Text('聊天')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _section('字体大小', palette),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(3, (i) {
                    const names = ['小', '中', '大'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(names[i]),
                        selected: prefs.fontScaleIdx == i,
                        onSelected: (_) async {
                          await Haptics.select();
                          await prefs.setFontScaleIdx(i);
                          if (mounted) setState(() {});
                        },
                      ),
                    );
                  }),
                ),
              ),
              _section('气泡', palette),
              _percent(
                palette,
                label: '气泡透明度',
                value: prefs.bubbleOpacity,
                min: 0.2,
                onChanged: prefs.setBubbleOpacity,
              ),
              _section('输入栏', palette),
              SwitchListTile(
                title: const Text('毛玻璃'),
                subtitle: Text('背景图模糊着透上来（略费电）',
                    style: TextStyle(fontSize: 11, color: palette.fgWith(0.4))),
                value: prefs.glassComposer,
                onChanged: (v) async {
                  await prefs.setGlassComposer(v);
                  if (mounted) setState(() {});
                },
              ),
              if (prefs.glassComposer)
                _percent(
                  palette,
                  label: '模糊强度',
                  value: prefs.glassSigma / 40,
                  onChanged: (v) => prefs.setGlassSigma(v * 40),
                ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _section(String text, Palette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.accent)),
      );

  Widget _percent(
    Palette palette, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
  }) {
    return ListTile(
      title: Row(
        children: [
          Text(label),
          const Spacer(),
          Text('${(value * 100).round()}%',
              style: TextStyle(fontSize: 12, color: palette.fgWith(0.5))),
        ],
      ),
      subtitle: Slider(
        value: value.clamp(min, 1.0),
        min: min,
        max: 1.0,
        divisions: ((1.0 - min) * 100).round(),
        onChanged: onChanged,
      ),
    );
  }
}

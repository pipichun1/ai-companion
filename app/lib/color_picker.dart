import 'package:flutter/material.dart';

/// HSV 取色器：色相条 + 饱和度/明度方块，紧凑排版
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({
    super.key,
    required this.initial,
    this.title = '选择颜色',
  });

  final Color initial;
  final String title;

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  late HSVColor _hsv;

  static const _quick = [
    Color(0xFF3D7EFF),
    Color(0xFF8B5CF6),
    Color(0xFFF06292),
    Color(0xFF3DBB8B),
    Color(0xFFFF8A3D),
    Color(0xFF4DD0C4),
    Color(0xFF8A94A6),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  String get _hex =>
      '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  void _updateSV(Offset local, Size size) {
    setState(() {
      _hsv = _hsv
          .withSaturation((local.dx / size.width).clamp(0.0, 1.0))
          .withValue((1 - local.dy / size.height).clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final squareHeight = (constraints.maxHeight * 0.32).clamp(160.0, 260.0);
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 预览 + 色值
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: dark ? Colors.white24 : Colors.black12,
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_hex,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 16)),
                                Text('拖动下方取色',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5))),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 饱和度 / 明度
                        LayoutBuilder(
                          builder: (context, c) {
                            final size = Size(c.maxWidth, squareHeight);
                            return GestureDetector(
                              onPanDown: (d) => _updateSV(d.localPosition, size),
                              onPanUpdate: (d) =>
                                  _updateSV(d.localPosition, size),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: size.width,
                                  height: size.height,
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Colors.white,
                                              HSVColor.fromAHSV(
                                                      1, _hsv.hue, 1, 1)
                                                  .toColor(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: _hsv.saturation * size.width - 9,
                                        top: (1 - _hsv.value) * size.height - 9,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 3),
                                            boxShadow: const [
                                              BoxShadow(
                                                  color: Colors.black45,
                                                  blurRadius: 4)
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // 色相条
                        LayoutBuilder(
                          builder: (context, c) {
                            final width = c.maxWidth;
                            void setHue(Offset p) {
                              final hue =
                                  (p.dx / width).clamp(0.0, 1.0) * 360;
                              setState(() => _hsv = _hsv.withHue(hue));
                            }

                            return GestureDetector(
                              onPanDown: (d) => setHue(d.localPosition),
                              onPanUpdate: (d) => setHue(d.localPosition),
                              child: Container(
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(13),
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFFFF0000),
                                    Color(0xFFFFFF00),
                                    Color(0xFF00FF00),
                                    Color(0xFF00FFFF),
                                    Color(0xFF0000FF),
                                    Color(0xFFFF00FF),
                                    Color(0xFFFF0000),
                                  ]),
                                ),
                                child: Align(
                                  alignment:
                                      Alignment((_hsv.hue / 360) * 2 - 1, 0),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _color,
                                      border: Border.all(
                                          color: Colors.white, width: 3),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),

                        // 常用色
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _quick.map((c) {
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _hsv = HSVColor.fromColor(c)),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: dark
                                          ? Colors.white24
                                          : Colors.black12),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_color),
                      child: Text('使用 $_hex'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

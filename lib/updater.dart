import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

// =========================
// 📦 МОДЕЛЬ
// =========================
class UpdateInfo {
  final String version;
  final String apkUrl;
  final String notes;

  UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.notes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: (json['version'] ?? '').toString(),
      apkUrl: (json['apk_url'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}

// =========================
// 🚀 ОБНОВЛЯТОР
// =========================
class Updater {
  // 🔥 ломаем кеш
  static const String url =
      "https://blad-7.github.io/update_host/update.json?v=4";

  static const String currentVersion = "9.0.2";

  // =========================
  // 🔍 ПРОВЕРКА
  // =========================
  static Future<UpdateInfo?> check() async {
    try {
      debugPrint("=== UPDATE CHECK START ===");
      debugPrint("CURRENT VERSION: $currentVersion");

      final res = await http.get(
        Uri.parse(url),
        headers: {
          "Cache-Control": "no-cache",
          "Pragma": "no-cache",
        },
      ).timeout(const Duration(seconds: 5));

      debugPrint("STATUS: ${res.statusCode}");

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);

      if (data is! Map<String, dynamic>) return null;

      final update = UpdateInfo.fromJson(data);

      debugPrint("REMOTE VERSION: ${update.version}");

      if (update.version.isEmpty || update.apkUrl.isEmpty) return null;

      if (_isNewer(update.version, currentVersion)) {
        debugPrint("UPDATE FOUND");
        return update;
      }

      debugPrint("NO UPDATE");
      return null;
    } catch (e) {
      debugPrint("CHECK ERROR: $e");
      return null;
    }
  }

  // =========================
  // ⚖️ СРАВНЕНИЕ
  // =========================
  static bool _isNewer(String remote, String local) {
    final a = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final m = a.length > b.length ? a.length : b.length;

    for (int i = 0; i < m; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;

      if (x > y) return true;
      if (x < y) return false;
    }

    return false;
  }

  // =========================
  // 📥 СКАЧИВАНИЕ
  // =========================
  static Future<void> download(
    String apkUrl,
    Function(double) onProgress,
  ) async {
    // 🔥 сохраняем в DOWNLOADS
    final dir = Directory("/storage/emulated/0/Download");
    final path = "${dir.path}/hydro_update.apk";
    final file = File(path);

    debugPrint("SAVE TO: $path");

    if (file.existsSync()) {
      file.deleteSync();
    }

    final dio = Dio();

    await dio.download(
      apkUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
    );

    if (!file.existsSync()) {
      throw Exception("APK не найден");
    }

    final size = file.lengthSync();
    debugPrint("SIZE: $size");

    if (size < 1000000) {
      throw Exception("APK поврежден");
    }

    // 🔥 пробуем открыть установщик
    final result = await OpenFilex.open(path);
    debugPrint("OPEN: ${result.type}");

    // 🔥 если не открылся — fallback
    if (result.type.name != 'done') {
      throw Exception(
        "Не удалось открыть установщик.\nОткрой вручную:\nDownload/hydro_update.apk",
      );
    }
  }
}

// =========================
// 🎨 UI
// =========================
class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({
    super.key,
    required this.child,
  });

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  UpdateInfo? update;
  bool loading = true;
  bool downloading = false;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_check);
  }

  Future<void> _check() async {
    final upd = await Updater.check();

    if (!mounted) return;

    setState(() {
      update = upd;
      loading = false;
    });
  }

  Future<void> _startDownload() async {
    if (update == null || downloading) return;

    setState(() {
      downloading = true;
      progress = 0;
    });

    try {
      await Updater.download(
        update!.apkUrl,
        (p) {
          if (!mounted) return;
          setState(() {
            progress = p;
          });
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Файл скачан → открой Download и установи APK"),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    }

    if (!mounted) return;

    setState(() {
      downloading = false;
      progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return widget.child;

    if (update != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Обновление")),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text("Текущая: ${Updater.currentVersion}"),
              Text("Новая: ${update!.version}"),
              const SizedBox(height: 10),
              Text(update!.notes),
              const SizedBox(height: 20),
              if (!downloading)
                ElevatedButton(
                  onPressed: _startDownload,
                  child: const Text("ОБНОВИТЬ"),
                ),
              if (downloading)
                Column(
                  children: [
                    LinearProgressIndicator(value: progress),
                    Text("${(progress * 100).toStringAsFixed(0)}%"),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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
  static const String url =
      "https://blad-7.github.io/update_host/update.json";

  static const String currentVersion = "9.0.2";

  // =========================
  // 🔍 ПРОВЕРКА
  // =========================
  static Future<UpdateInfo?> check() async {
    try {
      debugPrint("=== UPDATE CHECK START ===");
      debugPrint("CURRENT VERSION: $currentVersion");
      debugPrint("UPDATE URL: $url");

      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      debugPrint("STATUS: ${res.statusCode}");

      if (res.statusCode != 200) {
        debugPrint("UPDATE CHECK FAILED: STATUS ${res.statusCode}");
        return null;
      }

      final dynamic data = jsonDecode(res.body);

      if (data is! Map<String, dynamic>) {
        debugPrint("INVALID JSON STRUCTURE");
        return null;
      }

      final update = UpdateInfo.fromJson(data);

      debugPrint("REMOTE VERSION: ${update.version}");
      debugPrint("REMOTE APK URL: ${update.apkUrl}");

      if (update.version.isEmpty || update.apkUrl.isEmpty) {
        debugPrint("INVALID JSON DATA");
        return null;
      }

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
  // ⚖️ СРАВНЕНИЕ ВЕРСИЙ
  // =========================
  static bool _isNewer(String remote, String local) {
    try {
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
    } catch (e) {
      debugPrint("VERSION COMPARE ERROR: $e");
      return false;
    }
  }

  // =========================
  // 📥 СКАЧИВАНИЕ
  // =========================
  static Future<void> download(
    String apkUrl,
    Function(double) onProgress,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = "${dir.path}/update.apk";
    final file = File(path);

    debugPrint("DOWNLOAD PATH: $path");
    debugPrint("APK URL: $apkUrl");

    if (file.existsSync()) {
      file.deleteSync();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 15),
        followRedirects: true,
      ),
    );

    await dio.download(
      apkUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
    );

    debugPrint("DOWNLOAD COMPLETE: $path");

    if (!file.existsSync()) {
      throw Exception("APK файл не найден после скачивания");
    }

    final size = file.lengthSync();
    debugPrint("APK SIZE: $size");

    if (size < 1000000) {
      throw Exception("APK поврежден или скачан не полностью");
    }

    final result = await OpenFilex.open(path);
    debugPrint("OPEN RESULT: ${result.type} ${result.message}");

    if (result.type.name != 'done') {
      throw Exception("Не удалось открыть APK: ${result.message}");
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
    try {
      final upd = await Updater.check().timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );

      if (!mounted) return;

      setState(() {
        update = upd;
        loading = false;
      });
    } catch (e) {
      debugPrint("UPDATE GATE ERROR: $e");

      if (!mounted) return;

      setState(() {
        update = null;
        loading = false;
      });
    }
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
          content: Text("APK скачан. Установите обновление"),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ошибка: $e"),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        downloading = false;
        progress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return widget.child;
    }

    if (update != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Обновление"),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.system_update_alt_rounded,
                    size: 72,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Доступно обновление",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Текущая версия: ${Updater.currentVersion}",
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Новая версия: ${update!.version}",
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    update!.notes.isEmpty
                        ? "Доступна новая версия приложения"
                        : update!.notes,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (!downloading)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _startDownload,
                        child: const Text("ОБНОВИТЬ"),
                      ),
                    ),
                  if (downloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 10),
                    Text("${(progress * 100).toStringAsFixed(0)}%"),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: downloading
                        ? null
                        : () {
                            setState(() {
                              update = null;
                            });
                          },
                    child: const Text("ПРОПУСТИТЬ"),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'updater.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HydroTrackerApp());
}

class HydroTrackerApp extends StatelessWidget {
  const HydroTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050B18),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// =========================
// SPLASH
// =========================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const UpdateGate(child: WaterHome()),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Icon(Icons.water_drop, size: 120, color: Colors.blue),
      ),
    );
  }
}

// =========================
// MAIN
// =========================
class WaterHome extends StatefulWidget {
  const WaterHome({super.key});

  @override
  State<WaterHome> createState() => _WaterHomeState();
}

class _WaterHomeState extends State<WaterHome> {
  int waterMl = 0;
  int goalMl = 2000;
  bool loading = true;

  Map<String, int> dailyHistory = {};
  Timer? reminderTimer;

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get todayKey => _key(DateTime.now());

  bool get isGoalReached => waterMl >= goalMl && goalMl > 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startReminder();
  }

  @override
  void dispose() {
    reminderTimer?.cancel();
    super.dispose();
  }

  // =========================
  // DATA
  // =========================
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    goalMl = prefs.getInt('goal_ml') ?? 2000;

    final raw = prefs.getString('daily_history');

    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      dailyHistory =
          decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    waterMl = dailyHistory[todayKey] ?? 0;

    setState(() => loading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_history', jsonEncode(dailyHistory));
    await prefs.setInt('goal_ml', goalMl);
  }

  Future<void> _addWater(int amount) async {
    final wasReached = isGoalReached;

    setState(() {
      waterMl += amount;
      dailyHistory[todayKey] = waterMl;
    });

    await _saveData();
    _startReminder(); // 🔥 пересчет

    if (!wasReached && isGoalReached) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔥 Цель достигнута!')),
      );
    }
  }

  Future<void> _resetWater() async {
    setState(() {
      waterMl = 0;
      dailyHistory[todayKey] = 0;
    });

    await _saveData();
    _startReminder();
  }

  Future<void> _changeGoal() async {
    final controller = TextEditingController(text: goalMl.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Цель на день'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      setState(() => goalMl = result);
      await _saveData();
      _startReminder();
    }
  }

  // =========================
  // SMART REMINDER
  // =========================
  void _startReminder() {
    reminderTimer?.cancel();

    final now = DateTime.now();

    if (now.hour < 8 || now.hour >= 22) return;

    final remaining = (goalMl - waterMl).clamp(0, goalMl);
    if (remaining <= 0) return;

    int portions = (remaining / 200).ceil();

    final end = DateTime(now.year, now.month, now.day, 22);
    final minutesLeft = end.difference(now).inMinutes;

    if (minutesLeft <= 0) return;

    int interval = (minutesLeft / portions).floor();

    if (interval < 20) interval = 20;

    reminderTimer =
        Timer.periodic(Duration(minutes: interval), (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('💧 Выпей воды (~200 мл)')),
      );
    });
  }

  // =========================
  // UI
  // =========================

  Widget glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTopCard() {
    final progress =
        goalMl == 0 ? 0.0 : (waterMl / goalMl).clamp(0.0, 1.0);

    return glassCard(
      child: Stack(
        children: [
          if (isGoalReached)
            const Positioned(
              top: 0,
              right: 0,
              child: Icon(Icons.local_fire_department,
                  color: Colors.orange),
            ),
          Column(
            children: [
              const Icon(Icons.water_drop,
                  size: 90, color: Color(0xFF4DB7FF)),
              const SizedBox(height: 12),
              Text('$waterMl мл',
                  style: const TextStyle(
                      fontSize: 42, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Цель: $goalMl мл'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return glassCard(
      child: Row(
        children: [
          Expanded(child: _stat('Сегодня', '$waterMl')),
          Expanded(child: _stat('Среднее', '${_avg(7)}')),
          Expanded(child: _stat('Серия', '${_streak()}')),
        ],
      ),
    );
  }

  Widget _stat(String t, String v) {
    return Column(
      children: [
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(t, style: const TextStyle(fontSize: 12))
      ],
    );
  }

  int _streak() {
    int s = 0;
    final now = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      if ((dailyHistory[_key(d)] ?? 0) > 0) {
        s++;
      } else {
        break;
      }
    }
    return s;
  }

  int _avg(int d) {
    int sum = 0;
    final now = DateTime.now();

    for (int i = 0; i < d; i++) {
      final day = now.subtract(Duration(days: i));
      sum += dailyHistory[_key(day)] ?? 0;
    }
    return (sum / d).round();
  }

  Widget _buildChart() {
    final values = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: i));
      return dailyHistory[_key(d)] ?? 0;
    }).reversed.toList();

    final maxVal = values.fold(1, (a, b) => b > a ? b : a);

    return glassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final h = (v / maxVal) * 100 + 10;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF4DB7FF),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _button(int ml) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _addWater(ml),
        child: Text('+$ml'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hydro Tracker'),
        actions: [
          IconButton(onPressed: _changeGoal, icon: const Icon(Icons.flag)),
          IconButton(onPressed: _resetWater, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTopCard(),
          const SizedBox(height: 16),
          Row(children: [_button(150), _button(200), _button(300)]),
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 16),
          _buildChart(),
        ],
      ),
    );
  }
}
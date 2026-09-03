import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class DoorlockController extends ChangeNotifier {

  // ================= BASE URL =================
  final String baseUrl = "http://doorlockku.my.id";

  // ================= LOKASI DOORLOCK =================
  double doorlockLat = 0;
  double doorlockLng = 0;

  // ================= LOKASI USER =================
  double userLat = 0;
  double userLng = 0;

  double jarak = 0;
  bool dalamRadius = false;
  bool sudahUpdate = false;
  double radiusToleransi = 5; 

  // ================= FINGERPRINT =================
  bool fingerprintAktif = false;
  int sisaFingerprint = 0;
  Timer? _fingerTimer;

  // ================= STATUS =================
  bool isLoading = false;
  String statusPesan = '';

  final int durasiFingerprint = 60;

  // ================= INIT =================
  void initSystem() {
    resetSystemState();
  }

  // ================= RESET =================
  void resetFingerprintState() {
    fingerprintAktif = false;
    sisaFingerprint = 0;
    _fingerTimer?.cancel();
    notifyListeners();
  }

  void resetSystemState() {
    jarak = 0;
    dalamRadius = false;
    sudahUpdate = false;
    fingerprintAktif = false;
    sisaFingerprint = 0;
    isLoading = false;
    statusPesan = '';
    _fingerTimer?.cancel();
    notifyListeners();
  }

  // ================= HAVERSINE =================
  void _hitungJarak() {
    const R = 6371000;
    double dLat = _toRad(doorlockLat - userLat);
    double dLon = _toRad(doorlockLng - userLng);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(userLat)) *
        cos(_toRad(doorlockLat)) *
        sin(dLon / 2) *
        sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    jarak = R * c;
    dalamRadius = jarak <= radiusToleransi;
  }

  double _toRad(double d) => d * pi / 180;
  void main() => print(pi);
  
  void setRadius(double meter) {
    radiusToleransi = meter;
    if (sudahUpdate) {
      dalamRadius = jarak <= radiusToleransi; // langsung update status tanpa perlu tekan Update Lokasi lagi
    }
    notifyListeners();
  }

  // ================= HTTP HELPER =================
  Future<dynamic> _getRequest(String endpoint) async {
    try {
      final uri = Uri.parse("$baseUrl/$endpoint");
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      debugPrint("HTTP ERROR ${response.statusCode}: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("REQUEST ERROR: $e");
      return null;
    }
  }

  // ================= GPS HP =================
  Future<bool> _ambilGpsHp() async {
    try {
      bool serviceAktif = await Geolocator.isLocationServiceEnabled();
      if (!serviceAktif) {
        statusPesan = 'GPS HP tidak aktif, nyalakan GPS terlebih dahulu';
        notifyListeners();
        return false;
      }

      LocationPermission izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
        if (izin == LocationPermission.denied) {
          statusPesan = 'Izin lokasi ditolak';
          notifyListeners();
          return false;
        }
      }

      if (izin == LocationPermission.deniedForever) {
        statusPesan = 'Izin lokasi ditolak permanen, buka pengaturan HP';
        notifyListeners();
        await Geolocator.openAppSettings();
        return false;
      }

      statusPesan = 'Mengambil GPS...';
      notifyListeners();

      Position posisi = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      userLat = posisi.latitude;
      userLng = posisi.longitude;
      debugPrint("GPS HP: $userLat, $userLng");
      return true;

    } on TimeoutException {
      statusPesan = 'GPS timeout, coba lagi di tempat terbuka';
      notifyListeners();
      return false;
    } catch (e) {
      statusPesan = 'Gagal ambil GPS: $e';
      notifyListeners();
      return false;
    }
  }

  // ================= AMBIL LOKASI DOORLOCK =================
  Future<bool> _ambilLokasiDoorlock() async {
    try {
      final data = await _getRequest("get_location.php");

      if (data == null) {
        statusPesan = 'Gagal ambil lokasi doorlock';
        notifyListeners();
        return false;
      }

      doorlockLat = (data['lat'] as num).toDouble();
      doorlockLng = (data['lng'] as num).toDouble();
      debugPrint("DOORLOCK LOC: $doorlockLat, $doorlockLng");
      return true;
    } catch (e) {
      statusPesan = 'Gagal ambil lokasi doorlock: $e';
      notifyListeners();
      return false;
    }
  }

  // ================= MINTA LOKASI INTERNAL =================
  // Dipanggil dari updateLokasi() — tanpa guard isLoading
  Future<void> _mintaLokasiInternal() async {
    try {
      statusPesan = 'Meminta lokasi doorlock...';
      notifyListeners();

      final trigger = await _getRequest("request_location.php");
      if (trigger == null) {
        statusPesan = 'Gagal kirim trigger ke Arduino';
        return;
      }

      statusPesan = 'Menunggu Arduino mengirim lokasi...';
      notifyListeners();

      int percobaan = 0;
      while (percobaan < 15) {
        await Future.delayed(const Duration(seconds: 2));

        final data = await _getRequest("get_command.php");
        if (data != null && data['minta_lokasi'] == false) {
          statusPesan = 'Lokasi doorlock diterima';
          notifyListeners();
          break;
        }
        percobaan++;
      }

      if (percobaan >= 15) {
        statusPesan = 'Arduino tidak merespons, coba lagi';
        notifyListeners();
      }

    } catch (e) {
      statusPesan = 'Error: $e';
      notifyListeners();
    }
  }

  // ================= MINTA LOKASI EKSTERNAL =================
  // Dipanggil dari tombol Setting — dengan guard isLoading
  Future<void> mintaLokasiDoorlock() async {
    if (isLoading) return;

    isLoading = true;
    notifyListeners();

    await _mintaLokasiInternal();
    await _ambilLokasiDoorlock();

    isLoading = false;
    notifyListeners();
  }

  // ================= UPDATE LOKASI (BERANDA) =================
  Future<void> updateLokasi() async {
    if (isLoading) return;

    isLoading = true;
    sudahUpdate = false;
    statusPesan = 'Memulai update lokasi...';
    notifyListeners();

    try {
      // STEP 1: Ambil GPS HP
      final gpsOk = await _ambilGpsHp();
      if (!gpsOk) return;

      // STEP 2: Trigger Arduino + polling (internal, tanpa guard)
      await _mintaLokasiInternal();

      // STEP 3: Ambil lokasi doorlock terbaru
      final doorlockOk = await _ambilLokasiDoorlock();
      if (!doorlockOk) return;

      // STEP 4: Hitung haversine
      _hitungJarak();
      sudahUpdate = true;
      statusPesan = '';

      // STEP 5: Matikan fingerprint jika keluar radius
      if (!dalamRadius && fingerprintAktif) {
        await stopFingerprint();
      }

    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ================= FINGERPRINT START =================
  Future<void> startFingerprint() async {
    if (!sudahUpdate || !dalamRadius || fingerprintAktif) return;

    _fingerTimer?.cancel();
    fingerprintAktif = true;
    sisaFingerprint = durasiFingerprint;
    notifyListeners();

    await _kirimPerintahFingerprint(true);

    _fingerTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (sisaFingerprint <= 1) {
        t.cancel();
        stopFingerprint();
      } else {
        sisaFingerprint--;
        notifyListeners();
      }
    });
  }

  // ================= FINGERPRINT STOP =================
  Future<void> stopFingerprint() async {
    if (!fingerprintAktif) return;

    fingerprintAktif = false;
    sisaFingerprint = 0;
    _fingerTimer?.cancel();

    await _kirimPerintahFingerprint(false);

    notifyListeners();
  }

  // ================= KIRIM PERINTAH FINGERPRINT =================
  Future<void> _kirimPerintahFingerprint(bool aktif) async {
    try {
      final uri = Uri.parse(
        "$baseUrl/set_fingerprint.php?value=${aktif ? '1' : '0'}",
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint("FINGERPRINT ${aktif ? 'ON' : 'OFF'}: ${response.body}");
    } catch (e) {
      debugPrint("ERROR FINGERPRINT: $e");
    }
  }

  // ================= AMBIL HISTORY =================
  Future<List<Map<String, dynamic>>> ambilHistory() async {
    try {
      final uri = Uri.parse("$baseUrl/get_history.php");
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }

      return [];
    } catch (e) {
      debugPrint("ERROR HISTORY: $e");
      return [];
    }
  }
}
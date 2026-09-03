import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'doorlock_controller.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final c = Provider.of<DoorlockController>(context, listen: false);
      final hasil = await c.ambilHistory();
      setState(() {
        _data = hasil;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat data: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Akses'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadHistory,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Memuat riwayat...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Error
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    // Kosong
    if (_data.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: Colors.grey, size: 64),
            SizedBox(height: 12),
            Text(
              'Belum ada riwayat akses',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Riwayat akan muncul setelah ada akses fingerprint',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Data
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _data.length,
        itemBuilder: (context, index) {
          return _buildCard(_data[index]);
        },
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    // Parse waktu dari RTC Arduino
    final waktu = DateTime.tryParse(item['waktu_rtc'] ?? '')?.toLocal();
    final tanggal = waktu != null
        ? '${waktu.day.toString().padLeft(2, '0')}-'
          '${waktu.month.toString().padLeft(2, '0')}-'
          '${waktu.year}'
        : '-';
    final jam = waktu != null
        ? '${waktu.hour.toString().padLeft(2, '0')}:'
          '${waktu.minute.toString().padLeft(2, '0')}:'
          '${waktu.second.toString().padLeft(2, '0')}'
        : '-';

    final idJari  = item['id_jari'] as int?;
    final namaJari = item['nama_jari'] as String? ?? 'Tidak dikenal';
    final berhasil = item['berhasil'] as bool? ?? false;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ===== BARIS ATAS: TANGGAL + STATUS =====
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tanggal,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: berhasil
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: berhasil
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        berhasil ? Icons.check_circle : Icons.cancel,
                        size: 13,
                        color: berhasil ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        berhasil ? 'Berhasil' : 'Gagal',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: berhasil
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ===== BARIS BAWAH: WAKTU, USER, ID JARI =====
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                // WAKTU
                _kolom(
                  icon: Icons.access_time,
                  label: 'Waktu',
                  nilai: jam,
                ),

                // NAMA JARI
                _kolom(
                  icon: Icons.person,
                  label: 'Nama',
                  nilai: namaJari,
                ),

                // ID JARI
                _kolom(
                  icon: Icons.fingerprint,
                  label: 'ID Jari',
                  nilai: idJari != null ? '#$idJari' : '-',
                ),
                // _kolom(
                //  icon: Icons.social_distance,
                //   label: 'Jarak',
                //   nilai: item['jarak_meter'] != null
                //  ? '${(item['jarak_meter'] as num).toStringAsFixed(1)} m'
                //   : '-',
                //  ),

              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kolom({
    required IconData icon,
    required String label,
    required String nilai,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          nilai,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
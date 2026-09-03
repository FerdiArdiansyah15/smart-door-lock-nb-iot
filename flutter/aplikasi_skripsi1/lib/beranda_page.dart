import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'doorlock_controller.dart';

class BerandaPage extends StatefulWidget {
  const BerandaPage({super.key});

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  // Pilihan radius: 5 meter atau 50 meter
  double _radiusTerpilih = 5;

  @override
  Widget build(BuildContext context) {
    final c = Provider.of<DoorlockController>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beranda'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // const Text(
            //   'Doorlock Access System',
            //   textAlign: TextAlign.center,
            //   style: TextStyle(
            //     fontSize: 22,
            //     fontWeight: FontWeight.bold,
            //   ),
            // ),

            // const SizedBox(height: 24),

            // ================= LOKASI USER =================
            _infoCard(
              title: 'Lokasi Anda',
              content: Text(
                c.sudahUpdate
                    ? 'Lat: ${c.userLat.toStringAsFixed(6)}\n'
                      'Lng: ${c.userLng.toStringAsFixed(6)}'
                    : 'Belum diperbarui',
                style: TextStyle(
                  color: c.sudahUpdate ? Colors.black : Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ================= LOKASI DOORLOCK =================
            _infoCard(
              title: 'Lokasi Doorlock',
              content: Text(
                c.sudahUpdate
                    ? 'Lat: ${c.doorlockLat.toStringAsFixed(6)}\n'
                      'Lng: ${c.doorlockLng.toStringAsFixed(6)}'
                    : 'Belum diperbarui',
                style: TextStyle(
                  color: c.sudahUpdate ? Colors.black : Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ================= JARAK =================
            _infoCard(
              title: 'Jarak (Haversine)',
              content: Text(
                c.sudahUpdate
                    ? '${c.jarak.toStringAsFixed(2)} meter'
                    : '-',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ================= STATUS AKSES =================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: !c.sudahUpdate
                    ? Colors.grey.shade200
                    : (c.dalamRadius
                        ? Colors.green.shade50
                        : Colors.red.shade50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: !c.sudahUpdate
                      ? Colors.grey
                      : (c.dalamRadius ? Colors.green : Colors.red),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Status Akses',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !c.sudahUpdate
                        ? 'Silakan update lokasi'
                        : (c.dalamRadius
                            ? 'Dalam Radius ✓'
                            : 'Di Luar Radius ✗'),
                    style: TextStyle(
                      color: !c.sudahUpdate
                          ? Colors.grey
                          : (c.dalamRadius ? Colors.green : Colors.red),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ================= STATUS PESAN (loading/error) =================
            if (c.isLoading || c.statusPesan.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.isLoading
                      ? Colors.blue.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: c.isLoading
                        ? Colors.blue.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    if (c.isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (c.isLoading) const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.statusPesan,
                        style: TextStyle(
                          color: c.isLoading
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ================= PILIHAN RADIUS (kecil) =================
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Radius:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<double>(
                      value: 5,
                      groupValue: _radiusTerpilih,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) {
                        setState(() {
                          _radiusTerpilih = value!;
                        });
                        c.setRadius(_radiusTerpilih);
                      },
                    ),
                    const Text('5 m', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<double>(
                      value: 50,
                      groupValue: _radiusTerpilih,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) {
                        setState(() {
                          _radiusTerpilih = value!;
                        });
                        c.setRadius(_radiusTerpilih);
                      },
                    ),
                    const Text('50 m', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ================= BUTTON UPDATE LOKASI =================
            ElevatedButton.icon(
              onPressed: c.isLoading ? null : () => c.updateLokasi(),
              icon: c.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.my_location),
              label: Text(
                c.isLoading ? 'Memperbarui...' : 'Update Lokasi',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: c.isLoading ? Colors.grey : Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // ================= FINGERPRINT =================
            Center(
              child: Column(
                children: [

                  GestureDetector(
                    onTap: (!c.isLoading &&
                            c.sudahUpdate &&
                            c.dalamRadius &&
                            !c.fingerprintAktif)
                        ? () => c.startFingerprint()
                        : (c.fingerprintAktif
                            ? () => c.stopFingerprint()
                            : null),

                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.fingerprintAktif
                            ? Colors.green
                            : (!c.sudahUpdate || !c.dalamRadius || c.isLoading
                                ? Colors.grey
                                : Colors.blue),
                        boxShadow: c.fingerprintAktif
                            ? [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.5),
                                  blurRadius: 25,
                                  spreadRadius: 5,
                                ),
                              ]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.fingerprint,
                            color: Colors.white,
                            size: 50,
                          ),
                          if (c.fingerprintAktif)
                            Text(
                              '${c.sisaFingerprint}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    c.fingerprintAktif
                        ? 'Aktif — ${c.sisaFingerprint} detik (tap untuk matikan)'
                        : (!c.sudahUpdate
                            ? 'Silakan update lokasi dulu'
                            : (!c.dalamRadius
                                ? 'Di luar radius, tidak bisa aktifkan'
                                : (c.isLoading
                                    ? 'Menunggu...'
                                    : 'Tap untuk aktifkan fingerprint'))),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.fingerprintAktif
                          ? Colors.green
                          : (!c.sudahUpdate || !c.dalamRadius
                              ? Colors.red
                              : Colors.grey),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required Widget content,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            content,
          ],
        ),
      ),
    );
  }
}
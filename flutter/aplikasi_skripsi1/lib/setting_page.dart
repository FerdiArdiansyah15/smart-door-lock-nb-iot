import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'doorlock_controller.dart';
import 'theme_controller.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    final c = Provider.of<DoorlockController>(context);
    final theme = Provider.of<ThemeController>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Sistem'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          const SizedBox(height: 8),

          // ===== TAMPILAN =====
          _buildSectionTitle("Tampilan"),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text("Dark Mode"),
              subtitle: const Text("Ubah tampilan aplikasi"),
              value: theme.isDarkMode,
              onChanged: (value) {
                theme.changeTheme(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                      ? "Dark Mode Aktif"
                      : "Dark Mode Nonaktif",
                      ),
                      ),
                  );
              },
            ),
          ),

          const SizedBox(height: 24),

          // ===== DOORLOCK SYSTEM =====
          _buildSectionTitle("Doorlock System"),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Info lokasi doorlock saat ini
                ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.blue),
                  title: const Text("Lokasi Doorlock"),
                  subtitle: Text(
                    c.doorlockLat == 0 && c.doorlockLng == 0
                        ? "Belum tersinkronisasi"
                        : "Lat: ${c.doorlockLat.toStringAsFixed(6)}\n"
                          "Lng: ${c.doorlockLng.toStringAsFixed(6)}",
                    style: TextStyle(
                      color: c.doorlockLat == 0 ? Colors.grey : Colors.black87,
                    ),
                  ),
                  isThreeLine: c.doorlockLat != 0,
                ),

                // Status loading/pesan
                if (c.isLoading || c.statusPesan.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.isLoading
                            ? Colors.blue.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
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
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (c.isLoading) const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.statusPesan,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.isLoading
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Tombol update
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: c.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        c.isLoading
                            ? "Memperbarui..."
                            : "Update Lokasi Doorlock",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.isLoading
                            ? Colors.grey
                            : Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: c.isLoading
                          ? null
                          : () => _requestDoorlockLocation(context, c),
                    ),
                  ),
                ),

                const SizedBox(height: 4),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ===== INFO APLIKASI =====
          // _buildSectionTitle("Informasi"),

          // Card(
          //   shape: RoundedRectangleBorder(
          //     borderRadius: BorderRadius.circular(12),
          //   ),
          //   child: Column(
          //     children: [
          //       ListTile(
          //         leading: const Icon(Icons.info_outline, color: Colors.grey),
          //         title: const Text("Versi Aplikasi"),
          //         trailing: const Text(
          //           "1.0.0",
          //           style: TextStyle(color: Colors.grey),
          //         ),
          //       ),
          //       const Divider(height: 1),
          //       ListTile(
          //         leading: const Icon(Icons.router, color: Colors.grey),
          //         title: const Text("Status Koneksi"),
          //         trailing: Text(
          //           "Terhubung",
          //           style: TextStyle(
          //             color: Colors.green.shade600,
          //             fontWeight: FontWeight.w500,
          //           ),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

          // const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ===== LOGIC =====
  Future<void> _requestDoorlockLocation(
    BuildContext context,
    DoorlockController c,
  ) async {
    await c.mintaLokasiDoorlock();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(c.statusPesan.isEmpty
            ? "Lokasi doorlock berhasil diperbarui"
            : c.statusPesan),
        backgroundColor: c.statusPesan.contains('tidak') ||
                c.statusPesan.contains('Gagal')
            ? Colors.red
            : Colors.green,
      ),
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class NotificationPermissionService {
  static Future<bool> requestIfNeeded(BuildContext context) async {
    if (Platform.isIOS) return true;

    final status = await ph.Permission.notification.status;
    if (status.isGranted) return true;

    final result = await ph.Permission.notification.request();
    if (result.isGranted) return true;

    if (!context.mounted) return false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aktifkan Notifikasi'),
        content: const Text(
          'Aplikasi perlu izin notifikasi agar notifikasi live tracking dapat ditampilkan. '
          'Silakan aktifkan di pengaturan aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Nanti'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await ph.openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );

    return false;
  }
}

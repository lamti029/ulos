import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logger/logger.dart';

import 'background_isolate_facade.dart';

@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  final facade = BackgroundIsolateFacade(logger: Logger());
  return facade.start(service);
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // iOS background entry-point is handled by the background_service plugin.
  // We keep this simple to avoid duplicating background logic here.
  return true;
}

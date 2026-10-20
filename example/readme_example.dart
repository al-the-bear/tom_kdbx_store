/// The README's example, compiled.
library;

import 'package:tom_core_settings/tom_core_settings.dart';
import 'package:tom_core_storage/io.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

Future<void> main() async {
  const storage = TomLocalFileSystemStorage();
  final keys = TomKdbxKeyProvider();
  final container = await TomKdbxSettingsBootstrap(
    device: TomDeviceSettings(locator: 'device.yaml', storage: storage),
    secrets: TomInMemorySecretStore(),
    keys: keys,
    storage: storage,
    locator: 'settings.kdbx',
    namespace: 'myapp',
  ).ensure();

  final settings = await container.load();
  TomKdbxTokenStore(
    settings,
  ).put(const TomToken(host: 'github.com', secret: 'ghp_…', account: 'me'));
  settings.writeFragment('preferences', 'theme: dark\n');
  await container.save();
}

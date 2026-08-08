import 'file_upload_types.dart';

Future<String?> pickTextFile() async => null;

Future<PickedBinary?> pickBinaryFile() async => null;

void openDownload(String url) {}

void openExternal(String url) {}

String? loadStoredApiKey() => null;

void storeApiKey(String? key) {}

String? loadStoredSetting(String key) => null;

void storeSetting(String key, String? value) {}

String readLocationHash() => '';

void writeLocationHash(String hash) {}

void onHashChange(void Function(String hash) callback) {}

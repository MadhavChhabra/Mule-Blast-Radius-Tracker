import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'file_upload_types.dart';

Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.raml,.yaml,.yml,.json,.txt';
  input.click();
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.readAsText(files.first);
    reader.onLoadEnd.listen((_) => completer.complete(reader.result as String?));
    reader.onError.listen((_) => completer.complete(null));
  });
  return completer.future;
}

void openDownload(String url) {
  html.AnchorElement(href: url).click();
}

void openExternal(String url) {
  html.window.open(url, '_blank');
}

String readLocationHash() => html.window.location.hash;

void writeLocationHash(String hash) {
  if (html.window.location.hash != hash) {
    html.window.location.hash = hash;
  }
}

void onHashChange(void Function(String hash) callback) {
  html.window.onHashChange.listen((_) => callback(html.window.location.hash));
}

String? loadStoredApiKey() => html.window.localStorage['apiguard.apiKey'];

void storeApiKey(String? key) {
  if (key == null || key.isEmpty) {
    html.window.localStorage.remove('apiguard.apiKey');
  } else {
    html.window.localStorage['apiguard.apiKey'] = key;
  }
}

Future<PickedBinary?> pickBinaryFile() {
  final completer = Completer<PickedBinary?>();
  final input = html.FileUploadInputElement()..accept = '.zip';
  input.click();
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      final bytes = result is ByteBuffer ? result.asUint8List() : (result as Uint8List);
      completer.complete(PickedBinary(file.name, bytes));
    });
    reader.onError.listen((_) => completer.complete(null));
  });
  return completer.future;
}

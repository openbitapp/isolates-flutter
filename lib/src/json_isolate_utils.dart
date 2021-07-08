import 'package:gl_functional/gl_functional.dart';
import 'dart:convert';
import 'package:isolates/src/isolate.dart';

dynamic _jsonDecode(IsolateParameter<String> jsonToDecodeIsolateParam)
{
  final jsonRes = json.decode(jsonToDecodeIsolateParam.param);
  jsonToDecodeIsolateParam.sendPort?.send(jsonRes);
}

dynamic _jsonEncode(IsolateParameter<String> jsonToEncodeIsolateParam)
{
  final jsonRes = json.encode(jsonToEncodeIsolateParam.param);
  jsonToEncodeIsolateParam.sendPort?.send(jsonRes);
}

/// Esegue la decode json in un isolate
Future<Validation> decodeJsonInIsolate(String json, FromErrorMessage customMessageToError) 
          => IsolateManager.prepare(json, isolateEntryPoint: _jsonDecode, customMessageToError: customMessageToError).start();
/// Esegue l'encode di un json in un isolate
Future<Validation> encodeJsonInIsolate(String json, FromErrorMessage customMessageToError) 
          => IsolateManager.prepare(json, isolateEntryPoint: _jsonEncode, customMessageToError: customMessageToError).start();
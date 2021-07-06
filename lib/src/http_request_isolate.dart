import 'package:gl_functional/gl_functional.dart';
import 'package:meta/meta.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:isolates/src/isolate.dart';

String _getRequest (IsolateParameter<Map<String, dynamic>> requestParam) {  
  final uriOrUrl = requestParam.param['uriOrUrl'];
  
  http.get (uriOrUrl, headers: requestParam.param['headers'])
      .then((response) {
        if (response.statusCode == 200) {
          requestParam.sendPort.send(utf8.decode(response.bodyBytes));
        } else {
          throw BadResponseException(response.statusCode);
        }      
      });

  return '';
}

dynamic _jsonDecode(IsolateParameter<String> responseStringParam)
{
  final jsonRes = json.decode(responseStringParam.param);
  responseStringParam.sendPort.send(jsonRes);
}

/// Classe di base di una HttpRequest.
/// Ottiene il metodo `getAsyncResult` dalla classe [AsyncExceptionOrValue]
abstract class HttpIsolateRequestFactory {
  HttpIsolateRequestFactory._();

  /// L'`assert` all'interno del metodo viene richiamato solo nel Debug, \
  /// per essere sicuri che l'autority sia corretta ossia non inizi con http e che non contenga /
  static void _debugCheckAuthorityFormat(String authority) {
    assert(!authority.startsWith('http') && !authority.contains('/'),
        'authority NON deve iniziare con http o https e NON deve contenere alcun carattere /. Es.: www.microsoft.com');
  }

  static Uri _getUriFrom(
      {String authority,
      String unencodedPath,
      Map<String, String> queryParams,
      bool isHttps}) {
      _debugCheckAuthorityFormat(authority);

    return isHttps
        ? Uri.https(authority, unencodedPath, queryParams)
        : Uri.http(authority, unencodedPath, queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUriForRss(
      {@required String authority,
      String unencodedPath: '',
      Duration timeout: const Duration(seconds:30),
      bool isHttps : true,
      Map<String, String> queryParams: const <String, String>{}}) 
  {
    final headers = const {
        'Accept':
        'application/rss+xml, application/rdf+xml;q=0.8, application/atom+xml;q=0.6, application/xml;q=0.4, text/xml;q=0.4'
      };

    return fromUri(authority: authority, unencodedPath: unencodedPath, timeout: timeout, headers: headers, isHttps: isHttps, queryParams: queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUriForJson(
      {@required String authority,
      String unencodedPath: '',
      Duration timeout: const Duration(seconds:30),
      bool isHttps : true,
      Map<String, String> queryParams: const <String, String>{}}) 
  {
    final headers = const {
        'Accept':
        'application/json'
      };

    return fromUri(authority: authority, unencodedPath: unencodedPath, timeout: timeout, headers: headers, isHttps: isHttps, queryParams: queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUri(
      {@required String authority,
      String unencodedPath: '',
      Duration timeout: const Duration(seconds:30),
      Map<String, String> headers: const <String, String>{},
      bool isHttps : true,
      Map<String, String> queryParams: const <String, String>{}}) {
    {
      final uri = _getUriFrom(
                  authority: authority,
                  unencodedPath: unencodedPath,
                  queryParams: queryParams,
                  isHttps: isHttps);

      return _prepareRequest(uri, headers: headers, timeout:timeout);
    }
  }

  static IsolateManager<Map<String, dynamic>, String> fromUrl(String url, {Duration timeout:const Duration(seconds:30)}) {
    return _prepareRequest(url, timeout: timeout);
  }

  static IsolateManager<Map<String, dynamic>, String> _prepareRequest<T>(T uriOrUrl, 
                                            {Map<String, String> headers: const <String, String>{}, 
                                            Duration timeout:const Duration(seconds:30)}) 
  {
    return IsolateManager.prepare({'uriOrUrl': uriOrUrl, 'headers': headers}, isolateEntryPoint: _getRequest, timeout: timeout);
  }

  static Future<Validation> toJsonIsolate(String response) => IsolateManager.prepare(response, isolateEntryPoint: _jsonDecode).start();
}

extension Decoders on String {
  Future<Validation<T>> toJsonIsolate<T> () => IsolateManager.prepare(this, isolateEntryPoint: _jsonDecode).start();
}


import 'package:gl_functional/gl_functional.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:isolates/src/http_requests/request_methods.dart';
import 'package:isolates/src/isolate.dart';

String _getRequest (IsolateParameter<Map<String, dynamic>> requestParam) {  
  final uriOrUrl = requestParam.param['uriOrUrl'];
  final uri = _getUri(uriOrUrl);

  http.get (uri, headers: requestParam.param['headers'])
      .then((response) {
        if (response.statusCode == 200) {
          requestParam.sendPort?.send(utf8.decode(response.bodyBytes));
        } else {
          throw BadResponseException(response.statusCode);
        }      
      });

  return '';
}

String _postRequest (IsolateParameter<Map<String, dynamic>> requestParam) {  
  final uriOrUrl = requestParam.param['uriOrUrl'];
  final uri = _getUri(uriOrUrl);

  http.post(uri, headers: requestParam.param['headers'], body: requestParam.param['jsonBody'])
      .then((response) {
        if (response.statusCode == 200) {
          requestParam.sendPort?.send(utf8.decode(response.bodyBytes));
        } else {
          throw BadResponseException(response.statusCode);
        }      
      });

  return '';
}

Uri _getUri(dynamic uriOrUrl)
{
  Uri uri;
  if (uriOrUrl is String)
  {
    uri = Uri.parse(uriOrUrl);
  }
  else
    uri = uriOrUrl as Uri;

    return uri;
}

dynamic _jsonDecode(IsolateParameter<String> responseStringParam)
{
  final jsonRes = json.decode(responseStringParam.param);
  responseStringParam.sendPort?.send(jsonRes);
}

dynamic _jsonEncode(IsolateParameter<String> jsonToEncode)
{
  final jsonRes = json.encode(jsonToEncode);
  jsonToEncode.sendPort?.send(jsonRes);
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
      {String authority = '',
      String unencodedPath = '',
      Map<String, String> queryParams = const {},
      bool isHttps = true}) {
      _debugCheckAuthorityFormat(authority);

    return isHttps
        ? Uri.https(authority, unencodedPath, queryParams)
        : Uri.http(authority, unencodedPath, queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUriForRss(
      {required String authority,
      String unencodedPath: '',
      Duration timeout: const Duration(seconds:30),
      bool isHttps : true,
      Map<String, String> queryParams: const <String, String>{}}) 
  {
    final headers = const {
        'Accept':
        'application/rss+xml, application/rdf+xml;q=0.8, application/atom+xml;q=0.6, application/xml;q=0.4, text/xml;q=0.4'
      };

    return fromUri(authority: authority, unencodedPath: unencodedPath, timeout: timeout, additionalHeaders: headers, isHttps: isHttps, queryParams: queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUriForJson(
      {required String authority,
      String unencodedPath: '',
      Duration timeout: const Duration(seconds:30),
      bool isHttps : true,
      Map<String, String> queryParams: const {}}) 
  {
    final headers = const {
        'Accept':
        'application/json'
      };

    return fromUri(authority: authority, unencodedPath: unencodedPath, timeout: timeout, additionalHeaders: headers, isHttps: isHttps, queryParams: queryParams);
  }

  static IsolateManager<Map<String, dynamic>, String> fromUri(
      {required String authority,
      String unencodedPath: '',
      RequestMethod requestMethod = RequestMethod.get,
      Duration timeout: const Duration(seconds:30),
      Map<String, String> additionalHeaders: const {},
      bool isHttps : true,
      Map<String, String> queryParams: const {},
      Map<String, dynamic>? jsonBody}) {
    {
      final uri = _getUriFrom(
                  authority: authority,
                  unencodedPath: unencodedPath,
                  queryParams: queryParams,
                  isHttps: isHttps);

      var headers = {
        'Accept':
        'application/json'
      };

      if (requestMethod == RequestMethod.post)
      {
        headers = {'Content-Type': 'application/json; charset=UTF-8'};
      }

      headers.addAll(additionalHeaders);
      return _prepareRequest(uri, requestMethod: requestMethod, headers: headers, jsonBody: jsonBody, timeout:timeout);
    }
  }

  static IsolateManager<Map<String, dynamic>, String> fromUrl(String url, {Duration timeout:const Duration(seconds:30)}) {
    return _prepareRequest(url, timeout: timeout);
  }

  static IsolateManager<Map<String, dynamic>, String> _prepareRequest<T>(T uriOrUrl,               
                                                                        {RequestMethod requestMethod = RequestMethod.get,
                                                                          Map<String, String> headers: const <String, String>{}, 
                                                                          Duration timeout:const Duration(seconds:30),
                                                                          Map<String, dynamic>? jsonBody}) 
  {
    var isolateParams = {'uriOrUrl': uriOrUrl, 'headers': headers};
    if (jsonBody != null)    
    {
      isolateParams['jsonBody'] = json.encode(jsonBody);
    }

    var entryPoint = _getRequest;
    if (requestMethod == RequestMethod.post)
    {
      entryPoint = _postRequest;
    }

    return IsolateManager.prepare(isolateParams, isolateEntryPoint: entryPoint, timeout: timeout);    
  }

  static Future<Validation> toJsonIsolate(String response) => IsolateManager.prepare(response, isolateEntryPoint: _jsonDecode).start();
  static Future<Validation> encodeJson(String response) => IsolateManager.prepare(response, isolateEntryPoint: _jsonEncode).start();
}

extension Decoders on String {
  Future<Validation<T>> toJsonIsolate<T> () => IsolateManager.prepare(this, isolateEntryPoint: _jsonDecode).start() as Future<Validation<T>>;
  Future<Validation<T>> decodeJsonInIsolate<T> () => IsolateManager.prepare(this, isolateEntryPoint: _jsonEncode).start() as Future<Validation<T>>;
}


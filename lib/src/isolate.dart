import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:gl_functional/gl_functional.dart';

/// Classe da passare nell'isolate come parametro. Se si vogliono passare più parametri è necessario specificare
/// un `Map` come `T`
class IsolateParameter<T> {
  /// `SendPort` è il canale che utilizzerà la funzione nell'isolate per comunicare il risultato
  /// `SendPort` è un field della ReceivePort instanziata nella classe `IsolateHelper`.
  SendPort? sendPort;

  final T param;
  IsolateParameter(this.param);

  /// Costruttore privato che mi serve perché, visto che l'`IsolatePatameter` viene passato dall'esterno
  /// e che la SendPort viene fornita dall'`IsolateHelper`, non è possibile costruirlo in un solo passo
  /// (i.e. dall'esterno). Quindi quando l'`IsolateHelper` eseguirà uno spawn, utilizzerà la `_setPort` che a sua
  /// volta costruisce un nuovo `IsolateParameter` con la `SendPort`
  IsolateParameter._(this.param, {required SendPort sendPort}) : sendPort = sendPort;

  /// Utilizzata dall'`IsolateHelper` per costruire il parametro con la `SendPort`
  IsolateParameter<T> _setPort(SendPort sendPort) =>
      IsolateParameter._(param, sendPort: sendPort);
}

typedef Option<Fail> FromErrorMessage(String error);

/// Stati dell'isolate. Parte in `ready` (stato a cui non ritorna)
enum IsolateState { ready, running, killed, completed }

/// **T** è il tipo di parametro passato nell'`IsolateParameter`.
/// **R** è il tipo di dato passato alla SenPort dalla funzione eseguita nell'isolate.
/// Il tipo di dato deve essere un dato semplice e non complesso.
class IsolateHelper<T> {
  FromErrorMessage customMessageToError = (error) => None();  
  // Serve per trasformare le calback dei listen in un Future.
  final _completer = Completer<Validation>();

  final _receivePort = ReceivePort();
  final _errorPort = ReceivePort();
  Future<Isolate>? _isolate;
  IsolateState _state = IsolateState.ready;
  IsolateState get state => _state;

  /// Serve per tipizzare automaticamente l'IsolateHelper restituito.
  /// Negli Isolate la funzione solitamente restituisce un void ma qui, per tipizzarlo è
  /// necessario che la funzione restituisca il tipo di dato che l'entryPoint scrivera nella SendPort
  /// Il risultato restituito non verrà usato: serve solo per tipizzare!
  static IsolateHelper<T> spawn<T> (void Function(IsolateParameter<T>) entryPoint, 
                                          IsolateParameter<T> parameter,
                                          {required FromErrorMessage customMessageToError})
  {
    return IsolateHelper<T>._spawn(entryPoint, parameter, customMessageToError: customMessageToError);
  }
  /// Crea l'isolate in stato **paused**. Verrà riavviatonella `listen`
  /// Serve crearlo in pausa in modo che nella listen possiamo agganciarci alla receivePort
  /// e alla errorPort prima che l'isolate termini.
  IsolateHelper._spawn(void Function(IsolateParameter<T>) entryPoint,
      IsolateParameter<T> parameter,
      {required FromErrorMessage customMessageToError}) : customMessageToError = customMessageToError {
    _isolate = Isolate.spawn(
        entryPoint, parameter._setPort(_receivePort.sendPort),
        paused: true, onError: _errorPort.sendPort);
  }

  /// Testa se l'isolate è terminato
  bool get isEnded =>
      _state == IsolateState.completed || _state == IsolateState.killed;

  /// Controlla se è possibile mettersi in ascolto dell'isolate.
  /// Se qualcuno è già in ascolto oppure se ha terminato, ritorna un errore
  Validation<EmptyOption> checkState () {
    if (_state == IsolateState.running)
    {
      return AlreadyListeningError().toInvalid();
    }
    else if (isEnded)
    {
      return AlreadyListenedError().toInvalid();
    }

    return Valid (Empty);
  }

  /// Fa partire l'isolate e intercetta la risposta o l'eventuale errore.
  Future<Validation> listen() async {
    
    return checkState().fold(
      (failures) => failures.first.toInvalid().toFuture(), 
      (val) async {
          _state = IsolateState.running;

          // Ci mettianmo in ascolto del risultato dell'isolate
          _receivePort.listen((message) {
            _state = IsolateState.completed;
            _completer.complete(Valid(message));
            _close();
          });

          // Ci mettianmo in ascolto degli errori dell'Isolate
          _errorPort.listen((message) {
            _state = IsolateState.completed;
            _completer.complete(fromErrorMessage(message[0]).toInvalid());
            _close();
          });

          final i = await _isolate!;
          // Dobbiamo far partire l'Isolate che è stato creato in pausa per permettere
          // di ascoltare risultato e errori prima che si completi
          i.resume(i.pauseCapability!);
          // Il completer verrà completato nelle listen della _receivePort o della _errorPort
          return _completer.future;
      });
  }

  /// Ricostruisce l'eccezione o l'Error da un messaggio di errore.
  /// Serve perché gli errori restituiti dall'isolate sono stringhe
  Fail fromErrorMessage(String error) {
    return customMessageToError (error).fold(
      () {
        if (error.startsWith('SocketException')) {
          return SocketException(error).toFail();
        }

        if (error.startsWith('Timeout')) {
          return TimeoutException(error).toFail();
        }

        // if (error.startsWith('Bad response')) {
        //   return BadResponseException.fromString(error).toFail();
        // }

        if (error.startsWith('FormatException')) {
          return FormatException(error).toFail();
        }

        if (error.startsWith('HttpException')) {
          return HttpException(error).toFail();
        }

        if (!error.contains('Exception'))
        {
          return Error().toFail();
        }

        return Exception(error).toFail();
      }, 
      (some) => some);    
  }

  /// Termina l'isolate
  Future<void> kill() async {
    if (isEnded)
      return;

    _state = IsolateState.killed;  
    // Completiamo il Future emesso dalla listen
    _completer.complete(KilledError().toInvalid());
    
    _close();
    final i = await _isolate!;
    i.kill(priority: Isolate.immediate);
  }

  /// Chiude le porte dell'isolate (la receive e la error)
  void _close() {
    _receivePort.close();
    _errorPort.close();
  }
}

class ErrorWithMessage extends Error{
  final Option<String> message;

  ErrorWithMessage([String? message]) : message = message == null ? None<String>() : Some(message);

  @override
  String toString() => message.getOrElse('Error');
}

class AlreadyListeningError extends ErrorWithMessage
{
  AlreadyListeningError([String? message]) : super (message);

  @override
  String toString() => message.getOrElse('Already listening');
}

class AlreadyListenedError extends ErrorWithMessage
{
  AlreadyListenedError([String? message]) : super (message);

  @override
  String toString() => message.getOrElse('Already listened');
}

class KilledError extends ErrorWithMessage
{
  KilledError([String? message]) : super (message);

  @override
  String toString() => message.getOrElse('Killed');
}

/// Helper che semplifica la chiamata all'isolate manager
class IsolateManager<T> {
  final Duration _timeout;
  final IsolateHelper<T> _iHelper;

  IsolateManager._(this._iHelper, {Duration timeout: const Duration(seconds: 30)}) : _timeout = timeout;

  static IsolateManager<T> prepare<T> (T isolateInput, 
                                            {required void Function(IsolateParameter<T>) isolateEntryPoint, 
                                              required FromErrorMessage customMessageToError,
                                              Duration timeout: const Duration(seconds: 30)})
  {
    final isolateParam = IsolateParameter (isolateInput);
    final ih = IsolateHelper.spawn (isolateEntryPoint, isolateParam, customMessageToError: customMessageToError);

    return IsolateManager._(ih, timeout: timeout);
  } 

  /// Lancia l'isolate
  Future<Validation> start() {
    return _iHelper.listen()
                  .timeout(_timeout)
                  .catchError((e) {
                      if (e is Exception)
                      {
                        return e.toInvalid();
                      } 
                      else if (e is Error)
                      {
                        return e.toInvalid();
                      }
                  })                 
                  .then((result) async {
                      await _iHelper.kill();
                      return result;
                  });                
  }

  bool get isEnded => _iHelper.isEnded;

  /// Termina l'isolate
  Future<void> cancel() async => await _iHelper.kill();
}
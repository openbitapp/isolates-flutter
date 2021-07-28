import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:isolates/isolates.dart';

import 'package:functional_dart/functional_dart.dart';

String _isolateFunction (IsolateParameter<int> param)
{
  param.sendPort?.send('Hi ${param.param}, Hello from isolate!');
  return '';
}

String _isolateFunctionInError (IsolateParameter<int> param)
{
  throw ArgumentError('Invalid int');
}

String _isolateFunctionInException (IsolateParameter<int> param)
{
  throw Exception('Invalid int');
}

String _isolateFunctionVeryLong (IsolateParameter<int> param)
{
  for (var i = 0; i < param.param; i ++)
  {

  }

  return '';
}

void main() {
  test('TEST: IsolateHelper ', () async {
    final intP = 10;
    final ih = IsolateHelper.spawn(_isolateFunction, IsolateParameter(intP), customMessageToError: (e) => None());
    await ih.listen()
            .fold<void, String>((failures) => fail('Error not expected'), 
                          (val) => expect(val, 'Hi $intP, Hello from isolate!'));

    expect(ih.state, IsolateState.completed);

    final ihe = IsolateHelper.spawn(_isolateFunctionInError, IsolateParameter(intP), customMessageToError: (e) => None());
    await ihe.listen()
            .fold<void, String>((failures) => failures.first
                                                      .fold( 
                                                            (err) => expect(err, isA<Error>()), 
                                                            (exc) => fail('Error expected')),
                          (val) => fail('Error expected'));

    expect(ih.state, IsolateState.completed);

    final ihex = IsolateHelper.spawn(_isolateFunctionInException, IsolateParameter(intP), customMessageToError: (e) => None());
    await ihex.listen()
            .fold<void, String>((failures) => failures.first
                                                      .fold(
                                                            (err) => fail('Exception expected'), 
                                                            (exc) => expect(exc, isA<Exception>())),
                          (val) => fail('Error expected'));

    final ihVeryLong = IsolateHelper.spawn(_isolateFunctionVeryLong, IsolateParameter(200000), customMessageToError: (e) => None());
    expect(ihVeryLong.state, IsolateState.ready);

    ihVeryLong.listen();
    expect(ihVeryLong.state, IsolateState.running);

    await ihVeryLong.listen().fold((failures) => failures.first
                                                    .fold(
                                                          (err) => expect(err, isA<AlreadyListeningError>()), 
                                                          (exc) => fail('Error expected')), 
                              (val) => fail('Error expected'));

    await ihVeryLong.kill();
    expect(ihVeryLong.state, IsolateState.killed);
  });

  test('TEST: IsolateManager', () async {
    final imVeryLong = IsolateManager.prepare(200000, 
                                              customMessageToError: (e) => None(),
                                              isolateEntryPoint: _isolateFunctionVeryLong, 
                                              timeout:Duration(milliseconds:1));
    await imVeryLong.start()
                    .fold((failures) => failures.first
                                                  .fold(
                                                            (err) => fail('Exception expected'), 
                                                            (exc) => expect(exc, isA<TimeoutException>())), 
                            (val) => fail('Error expected'));

    imVeryLong.start()                           
              .fold((failures) => failures.first
                                          .fold(
                                                    (err) => expect(err, isA<AlreadyListenedError>()), 
                                                    (exc) => fail('Error expected')), 
                            (val) => fail('Error expected'));

    final imVeryLongII = IsolateManager.prepare(200000, isolateEntryPoint: _isolateFunctionVeryLong, customMessageToError: (e) => None());
    
    final fvlr = imVeryLongII.start();
    await imVeryLongII.cancel();
    await fvlr.fold((failures) => failures.first
                                                  .fold(
                                                            (err) => expect(err, isA<KilledError>()), 
                                                            (exc) => fail('Error expected')), 
                            (val) => fail('Error expected'));
  });

  test('TEST: HttpIsolateRequest', () async {
    
  });
}

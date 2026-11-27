import 'dart:async';
import 'dart:isolate';
import '../analyzer/text_analyzer.dart';
import '../index/bm25f_scorer.dart';
import '../index/inverted_index.dart';
import '../storage/sqlite_storage.dart';
import 'search_core.dart';

class _WorkerInitConfig {
  final SendPort replyPort;
  final String dbPath;
  final TextAnalyzer analyzer;
  final BM25FScorer scorer;

  const _WorkerInitConfig({
    required this.replyPort,
    required this.dbPath,
    required this.analyzer,
    required this.scorer,
  });
}

class _WorkerCommand {
  final int id;
  final String action;
  final dynamic payload;
  final SendPort replyPort;

  const _WorkerCommand({
    required this.id,
    required this.action,
    required this.payload,
    required this.replyPort,
  });
}

class _WorkerResponse {
  final int id;
  final dynamic result;
  final String? error;

  const _WorkerResponse({
    required this.id,
    this.result,
    this.error,
  });
}

/// Long-lived background Dart Isolate worker that handles heavy tokenization,
/// batch SQLite WAL writes, fuzzy scans, and BM25F ranking off the UI thread.
class IsolateWorker {
  final String dbPath;
  final TextAnalyzer analyzer;
  final BM25FScorer scorer;

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  int _nextId = 0;
  final Map<int, Completer<dynamic>> _pending = {};

  IsolateWorker({
    required this.dbPath,
    required this.analyzer,
    required this.scorer,
  });

  bool get isRunning => _isolate != null && _commandPort != null;

  /// Spawns the worker isolate and opens the SQLite WAL database connection inside it.
  Future<void> start() async {
    if (isRunning) return;

    final initPort = ReceivePort();
    _responsePort = ReceivePort();

    _responsePort!.listen((message) {
      if (message is _WorkerResponse) {
        final completer = _pending.remove(message.id);
        if (completer == null) return;
        if (message.error != null) {
          completer.completeError(StateError(message.error!));
        } else {
          completer.complete(message.result);
        }
      }
    });

    _isolate = await Isolate.spawn(
      _workerEntryPoint,
      _WorkerInitConfig(
        replyPort: initPort.sendPort,
        dbPath: dbPath,
        analyzer: analyzer,
        scorer: scorer,
      ),
    );

    final firstMsg = await initPort.first;
    initPort.close();

    if (firstMsg is SendPort) {
      _commandPort = firstMsg;
    } else {
      await stop();
      throw StateError('Failed to initialize IsolateWorker: $firstMsg');
    }
  }

  Future<T> _send<T>(String action, dynamic payload) async {
    if (!isRunning) {
      throw StateError('IsolateWorker is not started.');
    }
    final id = _nextId++;
    final completer = Completer<T>();
    _pending[id] = completer;

    _commandPort!.send(_WorkerCommand(
      id: id,
      action: action,
      payload: payload,
      replyPort: _responsePort!.sendPort,
    ));

    return completer.future;
  }

  /// Indexes documents on the background isolate inside a single SQLite transaction.
  Future<void> indexBatch(List<RawDocumentInput> inputs) {
    return _send<void>('indexBatch', inputs);
  }

  /// Removes a document on the background isolate.
  Future<void> remove(String docId) {
    return _send<void>('remove', docId);
  }

  /// Clears the entire index on the background isolate.
  Future<void> clear() {
    return _send<void>('clear', null);
  }

  /// Executes a search query on the background isolate.
  Future<RawSearchResult> search(RawSearchRequest request) {
    return _send<RawSearchResult>('search', request);
  }

  /// Closes the worker's SQLite connection and terminates the isolate cleanly.
  Future<void> stop() async {
    if (_commandPort != null) {
      try {
        await _send<void>('close', null);
      } catch (_) {
        // Ignore errors during teardown
      }
    }
    _responsePort?.close();
    _responsePort = null;
    _commandPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IsolateWorker stopped'));
      }
    }
    _pending.clear();
  }

  static Future<void> _workerEntryPoint(_WorkerInitConfig config) async {
    final storage = SqliteStorage(dbPath: config.dbPath);
    try {
      await storage.open();
    } catch (e) {
      config.replyPort.send(e.toString());
      return;
    }

    final executor = SearchCoreExecutor(
      storage: storage,
      analyzer: config.analyzer,
      scorer: config.scorer,
    );

    final commandPort = ReceivePort();
    config.replyPort.send(commandPort.sendPort);

    await for (final message in commandPort) {
      if (message is! _WorkerCommand) continue;

      try {
        dynamic result;
        switch (message.action) {
          case 'indexBatch':
            await executor.indexBatch(message.payload as List<RawDocumentInput>);
          case 'remove':
            await executor.remove(message.payload as String);
          case 'clear':
            await executor.clear();
          case 'search':
            result = await executor.executeSearch(message.payload as RawSearchRequest);
          case 'close':
            await storage.close();
            message.replyPort.send(_WorkerResponse(id: message.id));
            commandPort.close();
            return;
        }
        message.replyPort.send(_WorkerResponse(id: message.id, result: result));
      } catch (e) {
        message.replyPort.send(_WorkerResponse(
          id: message.id,
          error: e.toString(),
        ));
      }
    }
  }
}

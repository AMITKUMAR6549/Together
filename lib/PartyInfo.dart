import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PartyInfo {
  final String partyName;
  final String ip;
  final int port;
  DateTime lastSeen;

  PartyInfo({required this.partyName, required this.ip, required this.port})
      : lastSeen = DateTime.now();
}

class PartyDiscovery {
  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  final _partiesController = StreamController<List<PartyInfo>>.broadcast();
  final Map<String, PartyInfo> _discoveredParties = {};

  Stream<List<PartyInfo>> get partiesStream => _partiesController.stream;

  Future<void> startListening() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45454);
    _socket?.broadcastEnabled = true;

    _subscription = _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket?.receive();
        if (dg != null) {
          try {
            final data = utf8.decode(dg.data);
            final json = jsonDecode(data) as Map<String, dynamic>;
            final name = json['partyName'] as String;
            final ip = json['ip'] as String;
            final port = json['port'] as int;

            _discoveredParties['$ip:$port'] = PartyInfo(partyName: name, ip: ip, port: port);

            // Clean up stale parties older than 6 seconds
            final now = DateTime.now();
            _discoveredParties.removeWhere((_, info) => now.difference(info.lastSeen).inSeconds > 6);

            _partiesController.add(_discoveredParties.values.toList());
          } catch (_) {}
        }
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _socket?.close();
    _socket = null;
    _discoveredParties.clear();
  }
}
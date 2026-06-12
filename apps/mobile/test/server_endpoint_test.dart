import 'package:dems_mobile/core/server_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerEndpoint.fromForm', () {
    test('construye http con IP y puerto', () {
      final e = ServerEndpoint.fromForm(
        https: false,
        host: '192.168.1.100',
        port: '8080',
      );
      expect(e?.baseUrl, 'http://192.168.1.100:8080');
    });

    test('construye https sin puerto (default del esquema)', () {
      final e = ServerEndpoint.fromForm(
        https: true,
        host: 'dems.eddndev.work',
        port: '',
      );
      expect(e?.baseUrl, 'https://dems.eddndev.work');
    });

    test('normaliza espacios y mayúsculas en el host', () {
      final e = ServerEndpoint.fromForm(
        https: false,
        host: '  DEMS.Local ',
        port: ' 8080 ',
      );
      expect(e?.baseUrl, 'http://dems.local:8080');
    });

    test('rechaza host vacío, con esquema, con ruta o con puerto embebido', () {
      for (final host in [
        '',
        '   ',
        'http://192.168.1.100',
        '192.168.1.100/api',
        '192.168.1.100:8080',
        'host con espacios',
        'user@host',
      ]) {
        expect(
          ServerEndpoint.fromForm(https: false, host: host, port: ''),
          isNull,
          reason: 'host "$host" debería ser inválido',
        );
      }
    });

    test('rechaza puertos fuera de rango o no numéricos', () {
      for (final port in ['0', '65536', '-1', 'abc', '80.5']) {
        expect(
          ServerEndpoint.fromForm(https: false, host: '10.0.0.5', port: port),
          isNull,
          reason: 'puerto "$port" debería ser inválido',
        );
      }
    });
  });

  group('ServerEndpoint.tryParse', () {
    test('round-trip de una URL con puerto', () {
      final e = ServerEndpoint.tryParse('http://10.0.2.2:8080');
      expect(e?.https, false);
      expect(e?.host, '10.0.2.2');
      expect(e?.port, 8080);
      expect(e?.baseUrl, 'http://10.0.2.2:8080');
    });

    test('omite el puerto default del esquema', () {
      expect(
        ServerEndpoint.tryParse('https://dems.local:443')?.baseUrl,
        'https://dems.local',
      );
      expect(
        ServerEndpoint.tryParse('http://dems.local:80')?.baseUrl,
        'http://dems.local',
      );
    });

    test('rechaza esquemas no http(s) y basura', () {
      expect(ServerEndpoint.tryParse('ftp://host'), isNull);
      expect(ServerEndpoint.tryParse('no es una url'), isNull);
      expect(ServerEndpoint.tryParse(''), isNull);
    });
  });

  group('validadores de formulario', () {
    test('validateHost acepta IPv4 y hostnames', () {
      expect(ServerEndpoint.validateHost('192.168.0.10'), isNull);
      expect(ServerEndpoint.validateHost('servidor-dems.local'), isNull);
    });

    test('validatePort acepta vacío (usa default del esquema)', () {
      expect(ServerEndpoint.validatePort(''), isNull);
      expect(ServerEndpoint.validatePort('  '), isNull);
      expect(ServerEndpoint.validatePort('8080'), isNull);
    });
  });
}

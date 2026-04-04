import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardResumo {
  DashboardResumo({
    required this.totalDiario,
    required this.totalMensal,
    required this.totalAnual,
    required this.serieDiaria,
    required this.serieSemanal,
    required this.serieMensal,
    required this.porMotorista,
    required this.porVeiculo,
    required this.porCombustivel,
  });

  final double totalDiario;
  final double totalMensal;
  final double totalAnual;

  final Map<String, double> serieDiaria;
  final Map<String, double> serieSemanal;
  final Map<String, double> serieMensal;
  final Map<String, double> porMotorista;
  final Map<String, double> porVeiculo;
  final Map<String, double> porCombustivel;
}

class DashboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.replaceAll(',', '.').trim();
      return double.tryParse(normalized) ?? 0;
    }
    return 0;
  }

  Stream<double> streamTotalDiario() {
    DateTime hoje = DateTime.now();
    DateTime inicioDia = DateTime(hoje.year, hoje.month, hoje.day);
    return _db.collection('abastecimentos')
        .where('data_hora', isGreaterThanOrEqualTo: inicioDia)
        .snapshots()
        .map((snap) {
          double total = 0;
          for (var doc in snap.docs) {
            total += _toDouble(doc['valor_total'] ?? doc['valor']);
          }
          return total;
        });
  }

  Stream<Map<String, double>> streamDadosGrafico() {
    return _db.collection('abastecimentos').snapshots().map((snap) {
      double gasolina = 0;
      double etanol = 0;
      for (var doc in snap.docs) {
        String tipo = (doc['combustivel'] ?? doc['tipo_combustivel'] ?? '').toString();
        double valor = _toDouble(doc['valor_total'] ?? doc['valor']);
        if (tipo == 'Gasolina') {
          gasolina += valor;
        } else if (tipo == 'Etanol' || tipo == 'Álcool' || tipo == 'Alcool') {
          etanol += valor;
        }
      }
      return {'Gasolina': gasolina, 'Etanol': etanol};
    });
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _dateKey(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  String _monthKey(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    return '${dt.year}-$m';
  }

  DateTime _startOfWeek(DateTime dt) {
    final normalized = DateTime(dt.year, dt.month, dt.day);
    final diff = normalized.weekday - DateTime.monday;
    return normalized.subtract(Duration(days: diff < 0 ? 6 : diff));
  }

  String _weekKey(DateTime dt) {
    final start = _startOfWeek(dt);
    final m = start.month.toString().padLeft(2, '0');
    final d = start.day.toString().padLeft(2, '0');
    return '${start.year}-$m-$d';
  }

  void _sum(Map<String, double> target, String key, double value) {
    target[key] = (target[key] ?? 0) + value;
  }

  Stream<DashboardResumo> streamResumoDashboard() {
    return _db.collection('abastecimentos').snapshots().map((snap) {
      final agora = DateTime.now();

      double totalDiario = 0;
      double totalMensal = 0;
      double totalAnual = 0;

      final serieDiaria = <String, double>{};
      final serieSemanal = <String, double>{};
      final serieMensal = <String, double>{};
      final porMotorista = <String, double>{};
      final porVeiculo = <String, double>{};
      final porCombustivel = <String, double>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final valor = _toDouble(data['valor_total'] ?? data['valor']);
        final dataHora = _toDate(data['data_hora']) ?? DateTime.fromMillisecondsSinceEpoch(0);

        if (dataHora.year == agora.year && dataHora.month == agora.month && dataHora.day == agora.day) {
          totalDiario += valor;
        }
        if (dataHora.year == agora.year && dataHora.month == agora.month) {
          totalMensal += valor;
        }
        if (dataHora.year == agora.year) {
          totalAnual += valor;
        }

        _sum(serieDiaria, _dateKey(dataHora), valor);
        _sum(serieSemanal, _weekKey(dataHora), valor);
        _sum(serieMensal, _monthKey(dataHora), valor);

        final motorista = (data['motorista'] ?? 'Não informado').toString().trim();
        final veiculo = (data['placa'] ?? data['veiculo'] ?? 'Não informado').toString().trim();
        final combustivel = (data['combustivel'] ?? data['tipo_combustivel'] ?? 'Não informado').toString().trim();

        _sum(porMotorista, motorista.isEmpty ? 'Não informado' : motorista, valor);
        _sum(porVeiculo, veiculo.isEmpty ? 'Não informado' : veiculo, valor);
        _sum(porCombustivel, combustivel.isEmpty ? 'Não informado' : combustivel, valor);
      }

      return DashboardResumo(
        totalDiario: totalDiario,
        totalMensal: totalMensal,
        totalAnual: totalAnual,
        serieDiaria: serieDiaria,
        serieSemanal: serieSemanal,
        serieMensal: serieMensal,
        porMotorista: porMotorista,
        porVeiculo: porVeiculo,
        porCombustivel: porCombustivel,
      );
    });
  }
}

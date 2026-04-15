/// Valor monetário em reais por extenso (pt-BR), até centenas de milhões.
String valorRealPorExtenso(double valor) {
  if (valor.isNaN || valor.isInfinite) return '';
  final neg = valor < 0;
  var v = (valor * 100).round().abs();
  final centavos = v % 100;
  v ~/= 100;
  if (v == 0 && centavos == 0) {
    return neg ? 'menos zero real' : 'zero real';
  }
  final parteInt = _extensoGrupo(v);
  final sb = StringBuffer();
  if (neg) sb.write('menos ');
  if (v > 0) {
    sb.write(parteInt);
    sb.write(v == 1 ? ' real' : ' reais');
  }
  if (centavos > 0) {
    if (v > 0) sb.write(' e ');
    sb.write(_extensoGrupo(centavos));
    sb.write(centavos == 1 ? ' centavo' : ' centavos');
  }
  return sb.toString();
}

String _extensoGrupo(int n) {
  if (n == 0) return 'zero';
  if (n < 20) return _u20[n];
  if (n < 100) {
    final d = n ~/ 10;
    final u = n % 10;
    if (u == 0) return _dezenas[d];
    return '${_dezenas[d]} e ${_u20[u]}';
  }
  if (n < 1000) {
    final c = n ~/ 100;
    final r = n % 100;
    if (c == 1 && r == 0) return 'cem';
    if (c == 1) return 'cento e ${_extensoGrupo(r)}';
    if (r == 0) return _centenas[c];
    return '${_centenas[c]} e ${_extensoGrupo(r)}';
  }
  if (n < 1e6) {
    final mil = n ~/ 1000;
    final r = n % 1000;
    final mStr = mil == 1 ? 'mil' : '${_extensoGrupo(mil)} mil';
    if (r == 0) return mStr;
    if (r < 100) return '$mStr e ${_extensoGrupo(r)}';
    return '$mStr, ${_extensoGrupo(r)}';
  }
  if (n < 1e9) {
    final mi = n ~/ 1000000;
    final r = n % 1000000;
    final miStr =
        mi == 1 ? 'um milhão' : '${_extensoGrupo(mi)} milhões';
    if (r == 0) return miStr;
    return '$miStr e ${_extensoGrupo(r)}';
  }
  return n.toString();
}

const _u20 = [
  'zero',
  'um',
  'dois',
  'três',
  'quatro',
  'cinco',
  'seis',
  'sete',
  'oito',
  'nove',
  'dez',
  'onze',
  'doze',
  'treze',
  'quatorze',
  'quinze',
  'dezesseis',
  'dezessete',
  'dezoito',
  'dezenove',
];

const _dezenas = [
  '',
  '',
  'vinte',
  'trinta',
  'quarenta',
  'cinquenta',
  'sessenta',
  'setenta',
  'oitenta',
  'noventa',
];

const _centenas = [
  '',
  '',
  'duzentos',
  'trezentos',
  'quatrocentos',
  'quinhentos',
  'seiscentos',
  'setecentos',
  'oitocentos',
  'novecentos',
];

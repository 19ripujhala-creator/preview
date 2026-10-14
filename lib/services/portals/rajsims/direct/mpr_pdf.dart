/// Complete calculations and original field coordinates from mpr_pdf.py.
/// Rendering consumes this plan; the original template is never reconstructed.
library;

import 'dart:math' as math;

class MprPdfError implements Exception {
  const MprPdfError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _s(Object? v) => v == null
    ? 'None'
    : v == true
    ? 'True'
    : v == false
    ? 'False'
    : v.toString();
bool _present(Object? v) =>
    v != null &&
    v != false &&
    v != 0 &&
    v != '' &&
    !(v is List && v.isEmpty) &&
    !(v is Map && v.isEmpty);
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
const mprGroups = ['pre_primary', 'primary', 'upper_primary'];

/// Python Decimal arithmetic, including operand quantum, half-even round(),
/// and ROUND_HALF_UP monetary amounts. Inputs remain exact base-ten numbers.
class MprNumber {
  const MprNumber._(this.coefficient, this.scale);
  final BigInt coefficient;
  final int scale;
  static final zero = MprNumber._(BigInt.zero, 0);
  static BigInt _ten(int n) => BigInt.from(10).pow(n);
  factory MprNumber.parse(Object value) {
    final s = _s(value).trim().replaceAll('_', ''),
        m = RegExp(r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$')
            .firstMatch(s);
    if (m == null || (m[2] ?? '').isEmpty && (m[3] ?? '').isEmpty)
      throw const MprPdfError('A report number is invalid.');
    final exp = int.tryParse(m[4] ?? '0');
    if (exp == null || exp.abs() > 10000)
      throw const MprPdfError('A report number is invalid.');
    var n = BigInt.parse('${m[2] ?? ''}${m[3] ?? ''}');
    if (m[1] == '-') n = -n;
    return MprNumber._(n, (m[3]?.length ?? 0) - exp);
  }
  bool get isNegative => coefficient.isNegative;
  bool get isInteger => scale <= 0 || coefficient % _ten(scale) == BigInt.zero;
  bool get isZero => coefficient == BigInt.zero;
  int toInt() =>
      (scale >= 0 ? coefficient ~/ _ten(scale) : coefficient * _ten(-scale))
          .toInt();
  MprNumber _precision() {
    final digits = coefficient.abs().toString().length;
    if (digits <= 28) return this;
    return quantize(scale - (digits - 28));
  }

  MprNumber operator +(MprNumber other) {
    final q = math.max(scale, other.scale);
    return MprNumber._(
      coefficient * _ten(q - scale) + other.coefficient * _ten(q - other.scale),
      q,
    )._precision();
  }

  MprNumber operator -(MprNumber other) =>
      this + MprNumber._(-other.coefficient, other.scale);
  MprNumber operator *(MprNumber other) => MprNumber._(
    coefficient * other.coefficient,
    scale + other.scale,
  )._precision();
  MprNumber operator /(MprNumber other) {
    if (other.isZero) throw const MprPdfError('Division by zero.');
    var n = coefficient.abs(),
        d = other.coefficient.abs(),
        q = n ~/ d,
        r = n % d,
        places = 0;
    while (r != BigInt.zero && q.toString().length < 28) {
      r *= BigInt.from(10);
      q = q * BigInt.from(10) + r ~/ d;
      r %= d;
      places++;
    }
    if (r != BigInt.zero &&
        (r * BigInt.two > d || r * BigInt.two == d && q.isOdd))
      q += BigInt.one;
    if (isNegative != other.isNegative) q = -q;
    return MprNumber._(q, scale - other.scale + places)._precision();
  }

  MprNumber quantize(int target, {bool halfUp = false}) {
    if (target >= scale)
      return MprNumber._(coefficient * _ten(target - scale), target);
    final den = _ten(scale - target), abs = coefficient.abs();
    var q = abs ~/ den;
    final twice = (abs % den) * BigInt.two;
    if (twice > den || twice == den && (halfUp || q.isOdd)) q += BigInt.one;
    return MprNumber._(isNegative ? -q : q, target);
  }

  @override
  String toString() {
    final sign = isNegative ? '-' : '',
        digits = coefficient.abs().toString(),
        adjusted = digits.length - 1 - scale;
    if (scale < 0 || adjusted < -6) {
      final mantissa = digits.length == 1
          ? digits
          : '${digits[0]}.${digits.substring(1)}';
      return '$sign${mantissa}E${adjusted >= 0 ? '+' : ''}$adjusted';
    }
    if (scale == 0) return '$sign$digits';
    final p = digits.padLeft(scale + 1, '0');
    return '$sign${p.substring(0, p.length - scale)}.${p.substring(p.length - scale)}';
  }
}

MprNumber? mprNumber(Object? value, {bool integer = false}) {
  if (value == null || _s(value).trim().isEmpty) return null;
  if (RegExp(
    r'^[+-]?(?:s?nan|inf(?:inity)?)$',
    caseSensitive: false,
  ).hasMatch(_s(value).trim()))
    throw const MprPdfError(
      'Report counts must be non-negative whole numbers.',
    );
  final n = MprNumber.parse(value);
  if (n.isNegative || integer && !n.isInteger)
    throw const MprPdfError(
      'Report counts must be non-negative whole numbers.',
    );
  return n;
}

int? mprAmount(Object? value) {
  final n = mprNumber(value);
  return n?.quantize(0, halfUp: true).toInt();
}

String? mprPersonName(Object? value) {
  if (value == null) return null;
  final s = _s(value).trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  if (s.runes.any((c) => c > 127)) return s;
  return s
      .split(' ')
      .map((v) => '${v[0].toUpperCase()}${v.substring(1).toLowerCase()}')
      .join(' ');
}

class MprPdfPlan {
  MprPdfPlan(this.commands);
  final List<Map<String, dynamic>> commands;
  Map<String, dynamic> toJson() => {'commands': commands};
}

class _PlanBuilder {
  final commands = <Map<String, dynamic>>[];
  void cell(
    Object? value,
    num x,
    num y,
    num width, {
    num height = 10,
    String align = 'center',
    bool erase = false,
  }) {
    if (value == null || _s(value).trim().isEmpty) return;
    final s = _s(value).trim();
    if (s.runes.any((c) => c > 127 && (c < 0x900 || c > 0x97f)))
      throw const MprPdfError(
        'Report text supports English and Hindi letters.',
      );
    if (s.runes.length > 200)
      throw const MprPdfError('Report text is too long.');
    commands.add({
      'type': 'cell',
      'text': s,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'align': align,
      'erase': erase,
    });
  }

  void rect(
    num x,
    num y,
    num width,
    num height, {
    bool fill = false,
    bool stroke = false,
    List<num> color = const [0, 0, 0],
    num lineWidth = 1,
    List<num> dash = const [],
    int dashPhase = 0,
  }) => commands.add({
    'type': 'rect',
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'fill': fill,
    'stroke': stroke,
    'color': color,
    'line_width': lineWidth,
    'dash': dash,
    'dash_phase': dashPhase,
  });
  void line(
    num x1,
    num y1,
    num x2,
    num y2, {
    num width = .7,
    bool round = false,
  }) => commands.add({
    'type': 'line',
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'line_width': width,
    'round': round,
  });
  void tick(
    Object? value,
    Map<String, (double, double, double)> positions, {
    double lineWidth = .98,
  }) {
    final p = positions[value];
    if (p == null) return;
    final (x, y, raw) = p;
    final size = raw * 1.13;
    line(
      x,
      1008 - (y + size * .50),
      x + size * .30,
      1008 - (y + size * .76),
      width: lineWidth,
      round: true,
    );
    line(
      x + size * .30,
      1008 - (y + size * .76),
      x + size,
      1008 - (y + size * .16),
      width: lineWidth,
      round: true,
    );
  }
}

MprPdfPlan buildMprPdfPlan(Map<String, dynamic> payload) {
  final school = _map(payload['school']),
      monthly = _map(payload['monthly']),
      values = _map(payload['values']);
  if (school['success'] != true ||
      school['complete'] != true ||
      monthly['success'] != true ||
      monthly['complete'] != true)
    throw const MprPdfError(
      'Verified school and complete monthly meal data are required.',
    );
  if (!RegExp(r'^[0-9]{11}$').hasMatch(_s(school['udise'] ?? '')))
    throw const MprPdfError('Verified UDISE is required.');
  int asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(_s(v)) ??
        (throw const MprPdfError('Report month is invalid.'));
  }

  final year = asInt(monthly['year']), month = asInt(monthly['month']);
  if (year < 2000 || year > 2100 || month < 1 || month > 12)
    throw const MprPdfError('Report month is invalid.');
  final groups = _map(school['groups']),
      shown = mprGroups
          .where((g) => (_map(_map(groups[g])['total'])['total'] as num) > 0)
          .toList();
  if (shown.isEmpty) shown.add('primary');
  final b = _PlanBuilder();
  Object? val(String key) => values[key];
  MprNumber? numeric(String key, {bool integer = false}) =>
      mprNumber(val(key), integer: integer);
  void table(
    List<List<String>> keys,
    List<(double, double)> xs,
    List<double> ys,
  ) {
    for (var r = 0; r < math.min(keys.length, ys.length); r++) {
      for (var c = 0; c < math.min(keys[r].length, xs.length); c++) {
        b.cell(numeric(keys[r][c]), xs[c].$1, ys[r], xs[c].$2);
      }
    }
  }

  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  b.cell('${months[month]} $year', 272, 23, 155, height: 16, erase: true);
  b.cell(val('dispatch'), 470, 50.7, 31, height: 11.7, erase: true);
  b.cell(val('report_date'), 527, 50.7, 52, height: 11.7, erase: true);
  b.cell(school['udise'], 107, 63, 128, height: 13);
  b.cell(school['school_name'], 330, 63, 249, height: 13);
  String? detail(String key, [Set<String>? allowed]) {
    final raw = val('school_detail_$key');
    if (raw == null || _s(raw).trim().isEmpty) return null;
    final text = _s(raw).trim();
    if (allowed != null && !allowed.contains(text))
      throw MprPdfError('Invalid school detail: $key.');
    return text;
  }

  final kitchen = detail('kitchen_shed', {
        'Complete',
        'Incomplete',
        'Repairable',
        'N.A.',
      }),
      gas = detail('gas_connection', {'YES-SBC', 'YES-DBC', 'NO'}),
      utensils = detail('utensils', {'Sufficient', 'Un-Sufficient'}),
      drinking = detail('drinking_water', {'Y', 'N'}),
      fire = detail('fire_extinguisher', {'Y', 'N'}),
      weighing = detail('weighing_machine', {'Y', 'N'}),
      heightMeasure = detail('height_measurement', {'Y', 'N'}),
      handWash = detail('hand_washing', {'Y', 'N'}),
      electricity = detail('electricity', {'Y', 'N'}),
      toilet = detail('toilet_status', {
        'Complete',
        'Incomplete',
        'Repairable',
        'N.A.',
      });
  b.tick(kitchen, {
    'Complete': (153.5, 81, 4.4),
    'Incomplete': (194.5, 81, 4.4),
    'Repairable': (239.5, 81, 4.4),
    'N.A.': (283.5, 81, 4.4),
  });
  if (gas == 'YES-SBC' || gas == 'YES-DBC') {
    b.tick(gas, {
      'YES-SBC': (193.2, 89.5, 5),
      'YES-DBC': (257.4, 89.5, 5),
    }, lineWidth: 1.28);
  } else if (gas == 'NO') {
    b.cell('NO', 291, 86, 18, height: 10.5, erase: true);
    b.tick('NO', {'NO': (284, 91, 3.8)});
  }
  b.tick(utensils, {
    'Sufficient': (151.4, 99.5, 5),
    'Un-Sufficient': (192.2, 99.5, 5),
  }, lineWidth: 1.28);
  b.tick(drinking, {'Y': (211, 111, 4.2), 'N': (236, 111, 4.2)});
  b.tick(fire, {'Y': (211, 121, 4.2), 'N': (236, 121, 4.2)});
  b.tick(weighing, {'Y': (455, 81, 4.2), 'N': (483, 81, 4.2)});
  b.tick(heightMeasure, {'Y': (455, 91, 4.2), 'N': (483, 91, 4.2)});
  b.tick(handWash, {'Y': (455, 101, 4.2), 'N': (483, 101, 4.2)});
  b.tick(electricity, {'Y': (455, 111, 4.2), 'N': (483, 111, 4.2)});
  b.tick(toilet, {
    'Complete': (365, 118.8, 5.5),
    'Incomplete': (405, 118.8, 5.5),
    'Repairable': (449, 118.8, 5.5),
    'N.A.': (495, 118.8, 5.5),
  }, lineWidth: 1.38);
  void toiletCount(Object? value, num x, num w) {
    if (value == null) return;
    const y = 115.5, h = 11.5;
    b.rect(x + 1, 1008 - y - h + 1, w - 2, h - 2, fill: true, color: [1, 1, 1]);
    b.rect(
      x,
      1008 - y - h,
      w,
      h,
      stroke: true,
      color: [0, 0, 1],
      lineWidth: .5,
      dash: [1],
      dashPhase: 1,
    );
    b.cell(value, x, y - .1, w, height: h + .2);
  }

  toiletCount(numeric('school_detail_toilet_boys', integer: true), 526, 28);
  toiletCount(numeric('school_detail_toilet_girls', integer: true), 554, 25);
  const xs = [
    (108.0, 25.0),
    (133.0, 25.0),
    (158.0, 21.0),
    (179.0, 29.0),
    (208.0, 30.0),
    (238.0, 34.0),
    (272.0, 35.0),
    (307.0, 29.0),
    (336.0, 28.0),
    (364.0, 37.0),
    (401.0, 31.0),
    (432.0, 16.0),
    (448.0, 25.0),
    (473.0, 25.0),
    (498.0, 80.0),
  ];
  final totals = {
    for (final k in ['sc', 'st', 'obc_sbc', 'general', 'total'])
      k: {
        for (final f in ['boys', 'girls', 'total']) f: 0,
      },
  };
  for (var i = 0; i < mprGroups.length; i++) {
    final group = mprGroups[i],
        source = _map(groups[group]),
        cats = {
          for (final k in ['sc', 'st', 'general', 'total']) k: _map(source[k]),
        };
    cats['obc_sbc'] = {
      for (final f in ['boys', 'girls', 'total'])
        f: (_map(source['obc'])[f] as num) + (_map(source['sbc'])[f] as num),
    };
    final row = <int>[];
    for (final cat in ['sc', 'st', 'obc_sbc', 'general', 'total']) {
      for (final f in ['boys', 'girls', 'total']) {
        final n = mprNumber(cats[cat]![f], integer: true)!.toInt();
        row.add(n);
        totals[cat]![f] = totals[cat]![f]! + n;
      }
    }
    if (shown.contains(group)) {
      for (var j = 0; j < row.length; j++)
        b.cell(row[j], xs[j].$1, [160, 171.5, 183][i], xs[j].$2, height: 11);
    }
  }
  final totalRow = [
    for (final k in ['sc', 'st', 'obc_sbc', 'general', 'total'])
      for (final f in ['boys', 'girls', 'total']) totals[k]![f],
  ];
  for (var j = 0; j < totalRow.length; j++)
    b.cell(totalRow[j], xs[j].$1, 194.5, xs[j].$2, height: 11);
  final mealGroups = _map(payload['meal_groups']);
  const mealCols = [
    (212.0, 59.0, 400.0, 48.0),
    (271.0, 57.0, 448.0, 48.0),
    (328.0, 71.0, 496.0, 56.0),
  ];
  for (var i = 0; i < 3; i++) {
    final group = mprGroups[i];
    if (!shown.contains(group)) continue;
    final (mx, mw, kx, kw) = mealCols[i];
    final served = _map(mealGroups[group]);
    for (final (value, y) in [
      (numeric('working_days', integer: true), 237),
      (served['served_days'], 247.5),
      (served['total_meals'], 258),
      (numeric('attendance_$group', integer: true), 269),
    ]) {
      b.cell(value, mx, y, mw, height: 10.5);
    }
    final attendance = numeric('attendance_$group', integer: true),
        days = numeric('working_days', integer: true);
    var avg = numeric('average_$group');
    if (avg == null && attendance != null && days != null && !days.isZero)
      avg = (attendance / days).quantize(2);
    b.cell(avg, mx, 279.5, mw, height: 10.5);
    b.cell(numeric('working_days', integer: true), kx, 237, kw, height: 10.5);
    b.cell(
      numeric('milk_days_$group', integer: true),
      kx,
      247.5,
      kw,
      height: 10.5,
    );
    b.cell(
      numeric('milk_count_$group', integer: true),
      kx,
      258,
      kw,
      height: 10.5,
    );
  }
  if (!_present(val('cook1_name')) || !{'M', 'F'}.contains(val('cook1_gender')))
    throw const MprPdfError('Cook 1 name and gender are required.');
  const cookFields = [
    ('name', 71.0, 140.0),
    ('gender', 212.0, 25.0),
    ('social', 237.0, 70.0),
    ('bpl', 307.0, 21.0),
    ('eshram', 328.0, 35.0),
    ('payment', 363.0, 62.0),
    ('honorarium', 425.0, 48.0),
    ('from', 473.0, 57.0),
    ('till', 530.0, 48.0),
  ];
  for (final (prefix, y) in [
    ('cook1', 333),
    ('cook2', 345),
    ('cook3', 356.5),
    ('helper', 368.5),
  ]) {
    final name = val('${prefix}_name'), gender = val('${prefix}_gender');
    if (prefix.startsWith('cook') &&
        _present(name) &&
        !{'M', 'F'}.contains(gender))
      throw const MprPdfError('Cook gender is required.');
    for (final (key, x, w) in cookFields) {
      var v = val('${prefix}_$key');
      if (key == 'name') v = mprPersonName(v);
      if (key == 'honorarium') v = _present(name) ? mprAmount(v) : null;
      final erase =
          {'gender', 'social', 'bpl', 'eshram', 'payment'}.contains(key) &&
          _present(v);
      b.cell(
        v,
        prefix == 'helper' && key == 'name' ? 134 : x,
        y,
        prefix == 'helper' && key == 'name' ? 77 : w,
        height: 11,
        erase: erase,
      );
    }
  }
  final expenditure = <int?>[];
  for (var i = 0; i < 3; i++) {
    final group = mprGroups[i];
    if (!shown.contains(group)) {
      expenditure.add(null);
      continue;
    }
    final meals = _map(mealGroups[group])['total_meals'],
        rate = numeric('cooking_rate_$group');
    if (meals != null && rate == null)
      throw const MprPdfError(
        'Cooking rate is required for each meal category.',
      );
    final exp = meals != null && rate != null
        ? mprAmount(MprNumber.parse(meals) * rate)
        : null;
    expenditure.add(exp);
    b.cell(exp, 157, [436, 447.5, 459][i], 55, height: 11);
  }
  final expValues = expenditure.whereType<int>().toList();
  b.cell(
    expValues.isEmpty ? null : expValues.reduce((a, b) => a + b),
    157,
    471,
    55,
    height: 23,
  );
  const cols = [(307.0, 56.0), (363.0, 61.0), (424.0, 75.0), (499.0, 79.0)];
  table(
    [
      for (final prefix in ['cch', 'mme'])
        [
          for (final h in ['opening', 'received', 'expenditure', 'closing'])
            '${prefix}_$h',
        ],
    ],
    cols,
    [412, 423],
  );
  table(
    [
      for (final r in ['all', 'interest', 'total'])
        [
          for (final h in ['opening', 'received', 'expenditure', 'closing'])
            'bank_${r}_$h',
        ],
    ],
    cols,
    [469.5, 482, 494.5],
  );
  final active = mprGroups
      .where((g) => (_map(_map(groups[g])['total'])['total'] as num) > 0)
      .toList();
  const stockCols = [(71.0, 37.0), (108.0, 70.0), (178.0, 59.0), (237.0, 71.0)],
      riceCols = [(363.5, 37.0), (400.5, 70.0), (470.5, 59.0), (529.5, 49.5)];
  for (final raw in monthly['stock'] as List) {
    final item = _map(raw), product = _s(item['product_name']).toLowerCase();
    if (!{'wheat', 'rice'}.contains(product))
      throw const MprPdfError('Unsupported food grain in monthly stock.');
    final productCols = product == 'wheat' ? stockCols : riceCols;
    for (final y in [
      if (active.length == 1)
        {
          'pre_primary': 541.0,
          'primary': 553.5,
          'upper_primary': 566.0,
        }[active.first]!,
      578.5,
    ]) {
      for (var j = 0; j < 4; j++) {
        b.cell(
          mprNumber(item[['opening', 'received', 'outward', 'closing'][j]]),
          productCols[j].$1,
          y - .1,
          productCols[j].$2,
          height: 12.8,
        );
      }
    }
  }
  final powderTotals = List.generate(4, (_) => <MprNumber>[]);
  const headings = ['opening', 'received', 'consumption', 'closing'];
  for (var i = 0; i < 3; i++) {
    final group = mprGroups[i], y = [623.0, 635.0, 647.0][i];
    if (!shown.contains(group)) continue;
    final opening = numeric('powder_${group}_opening'),
        received = numeric('powder_${group}_received'),
        count = numeric('milk_count_$group', integer: true),
        grams = numeric('powder_rate_$group');
    var consumption = numeric('powder_${group}_consumption');
    if (consumption == null && count != null && grams != null)
      consumption = count * grams / MprNumber.parse(1000);
    var closing = numeric('powder_${group}_closing');
    if (closing == null &&
        opening != null &&
        received != null &&
        consumption != null) {
      closing = opening + received - consumption;
      if (closing.isNegative)
        throw const MprPdfError('Milk powder consumption exceeds stock.');
    }
    final row = [opening, received, consumption, closing];
    for (var j = 0; j < 4; j++) {
      b.cell(row[j], stockCols[j].$1, y, stockCols[j].$2, height: 12);
      if (row[j] != null) powderTotals[j].add(row[j]!);
    }
    for (var j = 0; j < 4; j++)
      b.cell(
        mprAmount(val('sugar_${group}_${headings[j]}')),
        stockCols[j].$1 + 292.5,
        y,
        stockCols[j].$2,
        height: 12,
      );
    b.cell(numeric('sugar_kg_$group'), 364, y + 93, 84, height: 12);
  }
  for (var j = 0; j < 4; j++)
    b.cell(
      powderTotals[j].isEmpty ? null : powderTotals[j].reduce((a, b) => a + b),
      stockCols[j].$1,
      659,
      stockCols[j].$2,
      height: 12,
    );
  const sugarCols = [
    (108.0, 49.0),
    (157.0, 56.0),
    (213.0, 58.0),
    (271.0, 57.0),
  ];
  for (var j = 0; j < 4; j++) {
    final h = headings[j];
    final (x, w) = sugarCols[j];
    final sugar = [for (final g in mprGroups) mprAmount(val('sugar_${g}_$h'))],
        valid = sugar.whereType<int>().toList(),
        total = valid.isEmpty ? null : valid.reduce((a, b) => a + b);
    b.cell(mprAmount(total), x, 704, w, height: 12.5);
    b.cell(
      mprAmount(total),
      stockCols[j].$1 + 292.5,
      659,
      stockCols[j].$2,
      height: 12,
    );
    final entries = <int?>[total];
    for (final (prefix, y) in [('milk_helper', 716.5), ('gas', 729.0)]) {
      final n = mprAmount(val('${prefix}_$h'));
      entries.add(n);
      b.cell(n, x, y, w, height: 12.5);
    }
    final sum = entries.whereType<int>().toList();
    b.cell(
      sum.isEmpty ? null : mprAmount(sum.reduce((a, b) => a + b)),
      x,
      753.5,
      w,
      height: 12.5,
    );
  }
  final sugarKg = [for (final g in mprGroups) numeric('sugar_kg_$g')]
      .whereType<MprNumber>()
      .toList();
  b.cell(
    sugarKg.isEmpty ? null : sugarKg.reduce((a, b) => a + b),
    364,
    753.5,
    84,
    height: 12,
  );
  final viffs = _map(payload['viffs']),
      verified = viffs['entry_available'] == true && viffs['locked'] == true;
  final boys = verified ? viffs['boys'] : val('viffs_boys'),
      girls = verified ? viffs['girls'] : val('viffs_girls');
  b.cell(mprNumber(boys, integer: true), 364, 777, 62, height: 10.5);
  b.cell(mprNumber(girls, integer: true), 364, 787.5, 62, height: 10.5);
  b.rect(468.3, 1008 - 808.7, 109, 9.2, fill: true, color: [1, 1, 1]);
  b.rect(488.5, 1008 - 819.2, 88.8, 9, fill: true, color: [1, 1, 1]);
  b.cell(
    mprPersonName(val('checked_name')),
    468.5,
    797.7,
    108.5,
    height: 11.8,
    erase: true,
  );
  b.cell(val('checked_mobile'), 488.5, 808.8, 88.5, height: 11.2, erase: true);
  final inspection = val('inspection');
  if (inspection == 'Yes' || inspection == 'No') {
    final x = inspection == 'Yes' ? 273 : 303;
    b.line(x, 1008 - 831, x + 11, 1008 - 831);
    b.line(x + 3, 1008 - 819, x + 5, 1008 - 821);
    b.line(x + 5, 1008 - 821, x + 9, 1008 - 816);
    if (inspection == 'Yes') {
      for (var i = 1; i <= 4; i++) {
        final y = [841, 850.5, 860, 869.5][i - 1];
        b.cell(
          mprPersonName(val('inspection_${i}_name')),
          232,
          y,
          193,
          height: 9.8,
        );
        b.cell(
          numeric('inspection_${i}_count', integer: true),
          425,
          y,
          153,
          height: 9.8,
        );
      }
    }
  }
  b.cell(mprPersonName(val('incharge_name')), 272, 918, 92, height: 12);
  b.cell(val('incharge_mobile'), 272, 930, 92, height: 14);
  return MprPdfPlan(b.commands);
}

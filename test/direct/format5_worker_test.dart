import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/format5_worker.dart';

void main() {
  final endpoint = Uri.parse(
    'https://rajshaladarpan.rajasthan.gov.in/SD1/Home/School/SchoolStudentProfiles_New.aspx',
  );
  const name = r'ctl00$ContentPlaceHolder1$grdStudentProfile$ctl02$';
  const prefix = 'ContentPlaceHolder1_grdStudentProfile_';

  String form({
    required bool edit,
    String mobile = '9000000000',
    bool success = false,
  }) =>
      '''
    <html><body><form id="form1" action="./SchoolStudentProfiles_New.aspx">
      <input type="hidden" name="__VIEWSTATE" value="state123" />
      <input type="hidden" name="__EVENTVALIDATION" value="event456" />
      <div id="UpdatePanel1"></div>
      <div id="ContentPlaceHolder1_UpdPanel">
        ${success ? '<div class="alert alert-success">Success : Student profile has been updated successfully.</div>' : ''}
        <select name="ctl00\$ContentPlaceHolder1\$ddlSession" id="ddlSession">
          <option value="2026-27" selected="selected">2026-27</option>
        </select>
        <select name="ctl00\$ContentPlaceHolder1\$ddlClass" id="ContentPlaceHolder1_ddlClass">
          <option value="1" selected="selected">1</option>
        </select>
        <select name="ctl00\$ContentPlaceHolder1\$ddlSection" id="ContentPlaceHolder1_ddlSection">
          <option value="1" selected="selected">A</option>
        </select>
        <input type="submit" name="ctl00\$ContentPlaceHolder1\$btnSearch" id="ContentPlaceHolder1_btnSearch" value="Show" />
        <table id="ContentPlaceHolder1_grdStudentProfile"><tr><td>
          ${edit ? '''
            <input id="${prefix}txtSnicid_Edit_0" name="${name}txtSnicid_Edit" value="00001" disabled="disabled" />
            <input id="${prefix}txtSRNO_Edit_0" name="${name}txtSRNO_Edit" value="19" />
            <input id="${prefix}txtMobile_edit_0" name="${name}txtMobile_edit" value="$mobile" />
            <select name="${name}ddlCategory_Edit" id="${prefix}ddlCategory_Edit_0">
              <option value="2" selected="selected">ST</option>
              <option value="5">OBC</option>
            </select>
            <input type="image" id="${prefix}btnUpdate_0" name="${name}btnUpdate" />
          ''' : '''
            <span id="${prefix}lblSnicid_0">00001</span>
            <span id="${prefix}lblSRNO_0">19</span>
            <span id="${prefix}lblName_0">Sample Student</span>
            <span id="${prefix}lblCategory_0">ST</span>
            <span id="${prefix}lblMobile_0">$mobile</span>
            <input type="image" id="${prefix}btnEdit_0" name="${name}btnEdit" />
          '''}
        </td></tr></table>
      </div>
    </form></body></html>''';

  String delta(bool edit, String mobile, {bool success = false}) {
    final full = form(edit: edit, mobile: mobile, success: success);
    // The fixture's UpdatePanel contains the portal's complete panel fragment.
    final a =
        full.indexOf('<div id="ContentPlaceHolder1_UpdPanel">') +
        '<div id="ContentPlaceHolder1_UpdPanel">'.length;
    final b = full.indexOf('</div>\n    </form>');
    final content = full.substring(a, b);
    String frame(String type, String id, String payload) =>
        '${payload.length}|$type|$id|$payload|';
    return frame('updatePanel', 'ContentPlaceHolder1_UpdPanel', content) +
        frame('hiddenField', '__VIEWSTATE', 'freshstate') +
        frame('hiddenField', '__EVENTVALIDATION', 'freshevent');
  }

  Future<
    ({
      Format5Worker worker,
      List<Map<String, Object?>?> requests,
      void Function(Duration) advance,
      void Function() changeSession,
    })
  >
  prepared() async {
    var time = DateTime.utc(2026, 10, 25);
    var identity = 'session-1';
    String? editing;
    final requests = <Map<String, Object?>?>[];
    String page() {
      if (editing != null) {
        return form(edit: true).replaceAll('00001', editing!);
      }
      final full = form(edit: false);
      final a = full.indexOf('<tr>'), b = full.indexOf('</tr>') + 5;
      final second = full
          .substring(a, b)
          .replaceAll('_0', '_1')
          .replaceAll('00001', '00002')
          .replaceAll('ctl02', 'ctl03');
      return full.replaceRange(b, b, second);
    }

    final worker = Format5Worker(
      request:
          (
            url, {
            fields,
            referer,
            mutation = false,
            timeout = const Duration(seconds: 30),
          }) async {
            requests.add(fields == null ? null : Map.of(fields));
            if (fields == null) editing = null;
            if (mutation) {
              throw const Format5Error(
                'SAVE_UNCONFIRMED',
                'Original uncertain response',
                attempted: true,
              );
            }
            if (fields != null &&
                fields.keys.any((key) => key.endsWith('btnEdit.x'))) {
              editing =
                  fields.keys.any(
                    (key) => key.contains('ctl03') && key.endsWith('btnEdit.x'),
                  )
                  ? '00002'
                  : '00001';
            }
            return (url: url, status: 200, html: page());
          },
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      schoolId: () => 'school-1',
      sessionIdentity: () => identity,
      check: () {},
      now: () => time,
    );
    await worker.open();
    await worker.list('2026-27', '1', '1');
    await worker.edit('00001');
    return (
      worker: worker,
      requests: requests,
      advance: (duration) => time = time.add(duration),
      changeSession: () => identity = 'session-2',
    );
  }

  test('same untouched Edit form is reused for 30 seconds without extending its lifetime', () async {
    final f = await prepared();
    final before = f.requests.length;
    final cached = await f.worker.edit('00001');
    expect(f.requests.length, before);
    expect((cached['mobile'] as Map)['value'], '9000000000');
    (cached['mobile'] as Map)['value'] = 'caller-only';
    f.advance(const Duration(seconds: 29));
    expect(
      ((await f.worker.edit('00001'))['mobile'] as Map)['value'],
      '9000000000',
    );
    expect(f.requests.length, before);
    f.advance(const Duration(seconds: 1));
    expect((await f.worker.edit('00001'))['success'], isTrue);
    expect(f.requests.length, before + 3);
    expect(
      f.requests.whereType<Map<String, Object?>>().any(
        (fields) => fields.keys.any((key) => key.endsWith('btnUpdate.x')),
      ),
      isFalse,
    );
  });
  test('a different student gets fresh form state and session changes cannot reuse Edit', () async {
    final f = await prepared();
    final before = f.requests.length;
    expect((await f.worker.edit('00002'))['nic_id'], '00002');
    expect(f.requests.length, before + 3);
    f.changeSession();
    await expectLater(
      f.worker.edit('00002'),
      throwsA(
        isA<Format5Error>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    expect(f.requests.length, before + 3);
  });
  test('refreshing the list invalidates the prepared Edit form', () async {
    final f = await prepared();
    await f.worker.list('2026-27', '1', '1');
    final before = f.requests.length;
    await f.worker.edit('00001');
    expect(f.requests.length, before + 1);
  });
  test(
    'even a pre-submit validation failure invalidates the reusable form',
    () async {
      final f = await prepared();
      await expectLater(
        f.worker.save('00001', sr: '19', category: '2', mobile: 'invalid'),
        throwsA(isA<Format5Error>()),
      );
      final before = f.requests.length;
      await f.worker.edit('00001');
      expect(f.requests.length, before + 3);
    },
  );
  test(
    'uncertain Update is never reused or automatically sent a second time',
    () async {
      final f = await prepared();
      await expectLater(
        f.worker.save('00001', sr: '19', category: '2', mobile: '9111111111'),
        throwsA(isA<Format5Error>()),
      );
      final before = f.requests.length;
      await f.worker.edit('00001');
      expect(f.requests.length, before + 3);
      expect(
        f.requests.whereType<Map<String, Object?>>().where(
          (fields) => fields.keys.any((key) => key.endsWith('btnUpdate.x')),
        ),
        hasLength(1),
      );
    },
  );
  test(
    'backward clock changes discard rather than prolong the prepared form',
    () async {
      final f = await prepared();
      final before = f.requests.length;
      f.advance(const Duration(seconds: -1));
      await f.worker.edit('00001');
      expect(f.requests.length, before + 3);
    },
  );

  test('fresh open recovers a renewed same-school identity and invalidates the old Edit form', () async {
    final f = await prepared();
    f.changeSession();
    final requestsBefore = f.requests.length;
    expect((await f.worker.open())['success'], true);
    expect(f.requests.length, requestsBefore + 1);
    await expectLater(
      f.worker.save('00001', sr: '19', category: '2', mobile: '9111111111'),
      throwsA(isA<Format5Error>()),
    );
    expect(f.requests.length, requestsBefore + 1);
    await f.worker.list('2026-27', '1', '1');
    expect((await f.worker.edit('00001'))['success'], true);
    expect(
      f.requests.whereType<Map<String, Object?>>().any(
        (fields) => fields.keys.any((k) => k.endsWith('btnUpdate.x')),
      ),
      false,
    );
  });
  test('same-school cookie renewal during a fresh GET adopts only the returned fresh page', () async {
    var identity = 'before';
    var requests = 0;
    final worker = Format5Worker(
      request:
          (
            url, {
            fields,
            referer,
            mutation = false,
            timeout = const Duration(seconds: 30),
          }) async {
            requests++;
            expect(fields, isNull);
            expect(mutation, false);
            identity = 'after-$requests';
            return (url: url, status: 200, html: form(edit: false));
          },
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      schoolId: () => 'school-1',
      sessionIdentity: () => identity,
      check: () {},
    );
    expect((await worker.open())['success'], true);
    expect((await worker.open())['success'], true);
    expect(requests, 2, reason: 'No extra GET loop or automatic POST');
  });
  test(
    'an existing worker cannot transfer to another school on reopen',
    () async {
      var owner = 'school-1';
      var requests = 0;
      final worker = Format5Worker(
        request:
            (
              url, {
              fields,
              referer,
              mutation = false,
              timeout = const Duration(seconds: 30),
            }) async {
              requests++;
              return (url: url, status: 200, html: form(edit: false));
            },
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => owner,
        sessionIdentity: () => owner,
        check: () {},
      );
      await worker.open();
      owner = 'school-2';
      await expectLater(
        worker.open(),
        throwsA(
          isA<Format5Error>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      expect(requests, 1);
    },
  );
  test(
    'school switch while the GET is in flight still rejects its response',
    () async {
      var owner = 'school-1';
      final worker = Format5Worker(
        request:
            (
              url, {
              fields,
              referer,
              mutation = false,
              timeout = const Duration(seconds: 30),
            }) async {
              owner = 'school-2';
              return (url: url, status: 200, html: form(edit: false));
            },
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => owner,
        sessionIdentity: () => owner,
        check: () {},
      );
      await expectLater(
        worker.open(),
        throwsA(
          isA<Format5Error>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
    },
  );
  test(
    'cookie renewal does not relax the identity guard on stateful Show',
    () async {
      var identity = 'original';
      var posts = 0;
      final worker = Format5Worker(
        request:
            (
              url, {
              fields,
              referer,
              mutation = false,
              timeout = const Duration(seconds: 30),
            }) async {
              if (fields != null) {
                posts++;
                identity = 'renewed';
              }
              return (url: url, status: 200, html: form(edit: false));
            },
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => 'school-1',
        sessionIdentity: () => identity,
        check: () {},
      );
      await worker.open();
      await expectLater(
        worker.list('2026-27', '1', '1'),
        throwsA(
          isA<Format5Error>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      expect(posts, 1);
      expect((await worker.open())['success'], true);
    },
  );
  test('a failed fresh GET cannot authorize an old Update', () async {
    var fail = false;
    final worker = Format5Worker(
      request:
          (
            url, {
            fields,
            referer,
            mutation = false,
            timeout = const Duration(seconds: 30),
          }) async {
            expect(mutation, false);
            return (
              url: url,
              status: fail ? 500 : 200,
              html: form(
                edit: fields?.keys.any((k) => k.endsWith('btnEdit.x')) == true,
              ),
            );
          },
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      schoolId: () => 'school-1',
      sessionIdentity: () => 'identity',
      check: () {},
    );
    await worker.open();
    await worker.list('2026-27', '1', '1');
    await worker.edit('00001');
    fail = true;
    await expectLater(worker.open(), throwsA(isA<Format5Error>()));
    await expectLater(
      worker.save('00001', sr: '19', category: '2', mobile: '9111111111'),
      throwsA(isA<Format5Error>()),
    );
  });

  test('Format-5 uses only its own state, read / edit / single update and fresh re-read', () async {
    var updateCount = 0;
    var storedMobile = '9000000000';
    Map<String, Object?>? submitted;
    final worker = Format5Worker(
      request:
          (
            url, {
            fields,
            referer,
            mutation = false,
            timeout = const Duration(seconds: 30),
          }) async {
            expect(url, endpoint);
            if (fields == null) {
              return (
                url: url,
                status: 200,
                html: form(edit: false, mobile: storedMobile),
              );
            }
            if (fields.containsKey('${name}btnUpdate.x')) {
              expect(mutation, isTrue);
              updateCount++;
              submitted = fields;
              storedMobile = '${fields['${name}txtMobile_edit']}';
              return (
                url: url,
                status: 200,
                html: delta(false, storedMobile, success: true),
              );
            }
            if (fields.containsKey('${name}btnEdit.x')) {
              expect(mutation, isFalse);
              return (url: url, status: 200, html: delta(true, storedMobile));
            }
            expect(
              fields.containsKey(r'ctl00$ContentPlaceHolder1$btnSearch'),
              isTrue,
            );
            return (
              url: url,
              status: 200,
              html: form(edit: false, mobile: storedMobile),
            );
          },
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      schoolId: () => 'school-1',
      sessionIdentity: () => 'session-1',
      check: () {},
    );
    final opened = await worker.open();
    expect(opened['success'], isTrue);
    expect((opened['students'] as List).length, 1);
    expect((await worker.list('2026-27', '1', '1'))['success'], isTrue);
    final edit = await worker.edit('00001');
    expect((edit['sr_no'] as Map)['enabled'], isTrue);
    final saved = await worker.save(
      '00001',
      sr: '19',
      category: '2',
      mobile: '9111111111',
    );
    expect(updateCount, 1);
    expect(saved['success'], isTrue);
    expect(saved['verified'], isTrue);
    expect('${saved['message']}', contains('updated successfully'));
    expect(submitted?['__ASYNCPOST'], 'true');
    expect(
      submitted?[r'ctl00$ScriptManager1'],
      '${r'ctl00$ContentPlaceHolder1$UpdPanel'}|${name}btnUpdate',
    );
    expect(submitted?['__VIEWSTATE'], 'freshstate');
    expect(submitted?['__EVENTVALIDATION'], 'freshevent');
    await expectLater(
      worker.save('00001', sr: '19', category: '2', mobile: '9111111111'),
      throwsA(isA<Format5Error>()),
    );
    expect(updateCount, 1);
  });
}

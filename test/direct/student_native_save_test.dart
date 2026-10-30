import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'student_ajax_test.dart' show AjaxPortal, delta, frame;
import 'student_worker_test.dart' show date, students, FakeAuth;
import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';
class NativeSavePortal extends AjaxPortal {
  @override String entry() {
    final doc = html.parse(super.entry());
    final form = doc.querySelector('form')!;
    if (!saved) {
      doc.getElementById('s1_0')!.attributes.remove('checked');
      doc.getElementById('s1_1')!.attributes['checked'] = 'checked';
    }
    form.append(dom.Element.tag('span')..id='ContentPlaceHolder1_lblentrySection'..text='1A');
    form.append(dom.Element.tag('span')..id='ContentPlaceHolder1_lbldateofAtt'..text=date);
    var n=0;
    for(final row in form.querySelectorAll('tr').where((r)=>r.querySelector('input[type=radio]')!=null)) {
      row.querySelector('td')!.append(dom.Element.tag('input')..attributes.addAll({
        'type':'hidden','name':'ctl00\$ContentPlaceHolder1\$grd_studentlist\$ctl0${++n}\$hdn_StudentProfileId',
        'value':'${1000+n}'}));
      row.querySelector('td')!.append(dom.Element.tag('input')..attributes.addAll({
        'type':'hidden','name':'old$n\$hdnIsPresent','value':'2'}));
    }
    return doc.outerHtml;
  }
  @override Future<AttendanceHttpReply> request(Uri url, {Map<String,Object?>? fields,Uri? referer,bool mutation=false}) async {
    if(mutation) {
      expect(fields!['__ASYNCPOST'],'true');
      expect(fields[r'ctl00$ScriptManager1'], r'ctl00$ContentPlaceHolder1$upPnl|ctl00$ContentPlaceHolder1$btnsubmit');
      expect(fields[r'old1$hdnIsPresent'],'2'); // Preserve native hidden baseline.
    }
    final reply=await super.request(url,fields:fields,referer:referer,mutation:mutation);
    if(!mutation || reply.status!=200) return reply;
    final panel=html.parse(reply.html).getElementById('ContentPlaceHolder1_upPnl')!;
    return (url:reply.url,status:200,html:delta(panel.innerHtml,state:'SAVE_STATE',event:'SAVE_EVENTS')+
      frame('scriptStartupBlock','ScriptContentNoTags',"openModal('Attendance Marked Successfully');"));
  }
}
class PreparingAuth extends FakeAuth {
  PreparingAuth(super.portal);
  int revision = 0;
  @override String get schoolSessionIdentity => 'one/session';
  @override Object? get schoolIdleActivityStamp => (portal.requests.length, revision);
}
class PreparingPortal extends NativeSavePortal {
  Completer<void>? gate;
  bool blocked = false;
  @override Future<AttendanceHttpReply> request(Uri url, {Map<String,Object?>? fields,Uri? referer,bool mutation=false}) async {
    final waiting = gate;
    if (!mutation && waiting != null && fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      gate = null; blocked = true; await waiting.future;
    }
    return super.request(url, fields: fields, referer: referer, mutation: mutation);
  }
}
void main() {
  test('old AJAX startup alerts are removed before a later response is merged', () {
    final doc = html.parse('<form><div id="ContentPlaceHolder1_upPnl">old</div></form>');
    final first = StudentAttendanceWorker.mergeResponse(doc, delta('saved') +
      frame('scriptStartupBlock','ScriptContentNoTags', "openModal('Attendance Marked Successfully');"));
    expect(first.querySelectorAll('script[data-attendance-response]'), hasLength(1));
    final second = StudentAttendanceWorker.mergeResponse(first, delta('new class'));
    expect(second.querySelectorAll('script[data-attendance-response]'), isEmpty);
    expect(first.querySelectorAll('script[data-attendance-response]'), hasLength(1));
  });

  late NativeSavePortal p;
  late StudentAttendanceWorker w;
  var stamp=0, identity='school/session';
  var now=Duration.zero;
  setUp(() {
    p=NativeSavePortal();stamp=0;identity='school/session';now=Duration.zero;
    w=StudentAttendanceWorker(request:(url,{fields,referer,mutation=false}) async {
      stamp++;
      try{return await p.request(url,fields:fields,referer:referer,mutation:mutation);}
      finally{stamp++;}
    },baseUrl:()=>Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity:()=>identity,activityStamp:()=>stamp,formElapsed:()=>now,
      indiaNow:()=>DateTime(2026,10,10));
  });
  Future<Map<String,dynamic>> read()=>w.fetchStudentAttendanceList(classId:'1',attendanceDate:date,section:'1A');
  Future<Map<String,dynamic>> save()=>w.saveStudentAttendance(classId:'1',attendanceDate:date,section:'1A',students:students,userConfirmed:true);
  test('native loaded form saves with exactly Submit and independent Entry, no Back or Show',()async {
    expect((await read())['success'],true);
    final n=p.requests.length;
    final result=await save();
    expect(result['success'],true);expect(result['attendance_verified'],true);
    expect(result['portal_message'],'Attendance Marked Successfully');
    expect(p.requests.length-n,2);
    expect(p.requests[n]['mutation'],true);
    expect((p.requests[n+1]['fields'] as Map)['__READ_ONLY_ACTION'],'CLASS_ENTRY');
    expect((p.requests[n+1]['fields'] as Map)['__VIEWSTATE'],'SAVE_STATE');
    expect(result['verified_students'],hasLength(2));expect(p.saves,1);
  });
  for(final reason in ['traffic','session','expiry','clock regression']) {
    test('$reason makes Save use fresh preflight',()async {
      await read();
      if(reason=='traffic')stamp++;
      if(reason=='session')identity='school/new';
      if(reason=='expiry')now=const Duration(seconds:45);
      if(reason=='clock regression')now=const Duration(seconds:-1);
      final n=p.requests.length;await save();
      expect(p.requests[n]['mutation'],false);expect(p.saves,1);
    });
  }
  test('uncertain Submit never replays',()async {
    await read();p.timeoutSave=true;
    final r=await save();expect(r['submission_attempted'],true);
    expect(r['attendance_verified'],false);expect(p.saves,1);
  });
  test('mutating returned display data cannot change held roster identity',()async {
    final r=await read();(r['students'] as List).first['srNo']='wrong';
    expect((await save())['success'],true);expect(p.saves,1);
  });
  test('preparing a current native form sends no extra requests', () async {
    await read(); final n = p.requests.length;
    await w.prepareStudentAttendanceSave(classId: '1', attendanceDate: date, section: '1A');
    expect(p.requests.length, n); expect(p.saves, 0);
  });
  test('confirmation preparation absorbs stale-form read before Submit', () async {
    await read(); stamp++;
    await w.prepareStudentAttendanceSave(classId: '1', attendanceDate: date, section: '1A');
    expect(p.saves, 0);
    final n = p.requests.length;
    final result = await save();
    expect(result['attendance_verified'], true);
    expect(p.requests.length - n, 2);
    expect(p.requests[n]['mutation'], true); expect(p.saves, 1);
  });
  test('cancelling after preparation never submits attendance', () async {
    await read(); stamp++;
    await w.prepareStudentAttendanceSave(classId: '1', attendanceDate: date, section: '1A');
    expect(p.saves, 0);
    expect(p.requests.every((r) => r['mutation'] == false), true);
  });
  test('traffic after preparation still forces safe Save preflight', () async {
    await read(); stamp++;
    await w.prepareStudentAttendanceSave(classId: '1', attendanceDate: date, section: '1A');
    stamp++; final n = p.requests.length;
    expect((await save())['success'], true);
    expect(p.requests[n]['mutation'], false); expect(p.saves, 1);
  });
  test('service serializes a later read behind optional preparation', () async {
    final portal = PreparingPortal(); final auth = PreparingAuth(portal);
    final service = DirectStudentAttendanceService(auth);
    expect((await service.fetchStudentsResponse(classId: '1', date: date, section: '1A'))['success'], true);
    auth.revision++;
    final gate = Completer<void>(); portal.gate = gate;
    final preparation = service.prepareSave(classId: '1', date: date, section: '1A');
    for (var i=0; i<20 && !portal.blocked; i++) { await Future<void>.delayed(Duration.zero); }
    expect(portal.blocked, true);
    final n = portal.requests.length;
    final later = service.fetchStudentsResponse(classId: '1', date: date, section: '1A');
    await Future<void>.delayed(Duration.zero);
    expect(portal.requests.length, n);
    gate.complete(); await preparation;
    expect((await later)['success'], true); expect(portal.saves, 0);
  });
  test('explicit confirmation remains required',()async {
    await read();final n=p.requests.length;
    final r=await w.saveStudentAttendance(classId:'1',attendanceDate:date,students:students,userConfirmed:false);
    expect(r['submission_attempted'],false);expect(p.requests.length,n);
  });
  test('no-change Pending Submit consumes returned Done summary directly without extra Show', () async {
    p.saved = true;
    expect((await read())['success'], true);
    final n = p.requests.length;
    final result = await save();
    expect(result['success'], true);
    expect(result['attendance_verified'], true);
    expect(p.requests.length - n, 2);
    expect(p.requests[n]['mutation'], true);
    expect((p.requests[n + 1]['fields'] as Map)['__READ_ONLY_ACTION'], 'CLASS_ENTRY');
    expect(p.saves, 1);
  });
  test('status change from Present to Absent preserves portal hdnIsPresent baseline', () async {
    expect((await read())['success'], true);
    final flipped = <Map<String, Object?>>[
      {'srNo': '00101', 'serialNo': 1, 'name': 'Alice', 'status': 'Absent'},
      {'srNo': '102', 'serialNo': 2, 'name': 'Bob', 'status': 'Absent'},
    ];
    final result = await w.saveStudentAttendance(
      classId: '1',
      attendanceDate: date,
      section: '1A',
      students: flipped,
      userConfirmed: true,
    );
    expect(result['submission_attempted'], true);
    final saveReq = p.requests.singleWhere((r) => r['mutation'] == true)['fields'] as Map;
    expect(saveReq[r'old1$hdnIsPresent'], '2');
    expect(saveReq[r'old2$hdnIsPresent'], '2');
    expect(p.saves, 1);
  });
}

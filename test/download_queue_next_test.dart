import 'dart:convert';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/data/models.dart';
import 'package:reelbox/media/download_service.dart';
import 'package:reelbox/state/app_state.dart';

void main() {
  test('direct task uses pinned real multipart API and persists current source identity', () {
    final task = createDirectDownloadTask(
      id:'parallel', title: const TitleRecord(id:6,title:'Fixture',type:'serie'),
      source:const MediaSource(url:'https://example.test/video.mp4',quality:'720p',type:'mp4'),
      episode:const EpisodeRecord(id:9,title:'Episode'),
      preferences:AppSettings(parallelDownloads:4,downloadNotifications:false),
    );
    expect(task, isA<ParallelDownloadTask>());
    expect((task as ParallelDownloadTask).chunks,4);
    expect(task.allowPause,isTrue);
    final metadata=jsonDecode(task.metaData) as Map;
    expect(metadata['sourceType'],'mp4');
    expect(metadata['episodeId'],9);
    expect(metadata['titleKind'],'serie');
    expect(metadata['downloadNotifications'],false);
    expect(Task.createFromJson(task.toJson()),isA<ParallelDownloadTask>());
  });
  test('excluded legacy tasks are canceled without deleting completed files or records', () async {
    final task=DownloadTask(taskId:'legacy',url:'https://example.test/a.mp4',
      metaData:jsonEncode({'titleId':7,'title':'Melody Box','titleKind':'movie','downloadNotifications':true}));
    final canceled=<String>[];
    await retireExcludedDownload(TaskRecord(task,TaskStatus.running,0,0),cancel:(id)async {canceled.add(id);return true;});
    expect(canceled,['legacy']);
    canceled.clear();
    await retireExcludedDownload(TaskRecord(task,TaskStatus.complete,1,100),cancel:(id)async {canceled.add(id);return true;});
    expect(canceled,isEmpty);
    expect(DownloadEntry.fromTask(task,taskStatus:TaskStatus.complete).visible,false);
  });
  test('retry retains old failed record until replacement enqueue succeeds', () async {
    final old=DownloadTask(taskId:'old',url:'https://example.test/video.mp4');
    final next=old.copyWith(taskId:'new',filename:'new.mp4');
    final events=<String>[];
    await expectLater(replaceFailedDownload(old,next,
      enqueue:(task)async { events.add('enqueue'); return false; },
      deleteRecord:(id)async {events.add('delete:$id');}),throwsStateError);
    expect(events,['enqueue']);
    events.clear();
    await replaceFailedDownload(old,next,
      enqueue:(task)async {events.add('enqueue'); return true;},
      deleteRecord:(id)async {events.add('delete:$id');});
    expect(events,['enqueue','delete:old']);
  });
}

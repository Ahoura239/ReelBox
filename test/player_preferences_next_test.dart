import 'package:flutter_test/flutter_test.dart';
import 'package:reelbox/media/media_helpers.dart';
import 'package:reelbox/state/app_state.dart';

void main() {
  test('startup dispatch applies rate/audio but does not overwrite system volume by default', () async {
    final calls = <String>[];
    await applyPlayerOptions(AppSettings(playbackSpeed:1.75,audioOnly:true,playerVolume:.9),
      rate:(v) async => calls.add('rate:$v'), audioOnly:(v) async => calls.add('audio:$v'), volume:(v) async => calls.add('volume:$v'));
    expect(calls,['rate:1.75','audio:true']);
    await applyPlayerOptions(AppSettings(rememberVolume:true,playerVolume:.2),
      rate:(v) async {}, audioOnly:(v) async {}, volume:(v) async => calls.add('volume:$v'));
    expect(calls.last,'volume:0.2');
  });
  test('subtitle reset only resets subtitle fields; complete player reset preserves library preferences', () {
    final settings = AppSettings(locale:'fa',theme:'light',skipSeconds:30,subtitleEnabled:false,subtitleFontFamily:'serif',subtitleFontSize:35,subtitleDelay:2,audioDelay:3,videoFit:'cover',audioOnly:true,playbackSpeed:1.75,backgroundAudio:true,externalPlayerPackage:'org.videolan.vlc');
    final sub = resetSubtitleSettings(settings);
    expect(sub.subtitleEnabled,true); expect(sub.subtitleFontFamily,'sans-serif');
    expect(sub.subtitleFontSize,24); expect(sub.subtitleDelay,0);
    expect(sub.audioDelay,3); expect(sub.playbackSpeed,1.75); expect(sub.locale,'fa');
    final all = resetPlayerSettings(settings);
    expect(all.videoFit,'contain'); expect(all.audioOnly,false); expect(all.playbackSpeed,1);
    expect(all.audioDelay,0); expect(all.backgroundAudio,false); expect(all.skipSeconds,10);
    expect(all.locale,'fa'); expect(all.theme,'light');
  });
}

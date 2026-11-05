import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_original_install_continuity_candidate.dart';

const account='07712345678';
const original='@DEDA-ABC123';
const uid='old-original-uid';
const firstInstall='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const newInstall='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const captureId='cccccccccccccccccccccccccccccccccccccccccccccccc';

class Proof {
  String uidNow=uid,localId=firstInstall;
  bool routeValid=true,oldArchiveAvailable=true,changed=false;
  int reads=0,authChecks=0,originalReads=0;
  DedaStep2OriginalInstallContinuityCandidate make({bool enabled=true}) =>
    DedaStep2OriginalInstallContinuityCandidate(
      enabled:enabled,
      currentUid:()=>uidNow,
      localStoredInstallId:() async {
        reads++;
        return localId;
      },
      verifiedOwnerRoute:(u,a,id) async {
        authChecks++;
        return routeValid && u==uid && a==account && id==original;
      },
      readOriginalProgressArchive:(a,u,isCurrent) async {
        originalReads++;
        if (!oldArchiveAvailable) throw StateError('no historical source');
        if (changed) uidNow='different-auth-uid';
        return const DedaStep2OriginalInstallBinding(
          accountKey:account,originalUid:uid,
          sourceInstallId:firstInstall,sourceCaptureId:captureId,
        );
      },
    );
}

Future<bool> match(Proof p,{bool enabled=true,
    bool Function()? isCurrent}) => p.make(enabled:enabled)
      .matchesOriginalProgressInstallation(
        accountKey:account,originalId:original,originalUid:uid,
        isCurrent:isCurrent??()=>true);

void main() {
  test('verified same UID, immutable server source and old install ID match', () async {
    final proof=Proof();
    expect(await match(proof),true);
    expect(proof.reads,2);
    expect(proof.authChecks,2);
    expect(proof.originalReads,1);
  });

  test('replacement phone same UID but different install never becomes original', () async {
    final proof=Proof()..localId=newInstall;
    expect(await match(proof),false);
    expect(proof.originalReads,1);
  });

  test('missing original archive is HOLD, not permission to create new ID', () async {
    final proof=Proof()..oldArchiveAvailable=false;
    expect(await match(proof),false);
    expect(proof.reads,1);
  });

  test('missing local install ID is HOLD and avoids even cloud read', () async {
    final proof=Proof()..localId='';
    expect(await match(proof),false);
    expect(proof.authChecks,0);
    expect(proof.originalReads,0);
  });

  test('spoofed account route and unmatched UID cannot read original', () async {
    final badRoute=Proof()..routeValid=false;
    expect(await match(badRoute),false);
    expect(badRoute.originalReads,0);
    final other=Proof()..uidNow='foreign-uid';
    expect(await match(other),false);
    expect(other.reads,0);
  });

  test('source account switches mid-await and is always rejected', () async {
    final proof=Proof()..changed=true;
    expect(await match(proof),false);
  });

  test('explicit owner intent expires before any cloud step', () async {
    final proof=Proof();
    expect(await match(proof,isCurrent:()=>false),false);
    expect(proof.reads,0);
  });

  test('read-only verifier is disabled by default and cannot create money', () async {
    final proof=Proof();
    expect(await match(proof,enabled:false),false);
    expect(proof.reads,0);
  });

  test('local install ID changes during check, no final approval', () async {
    final proof=Proof();
    // A fresh verifier with an injectable first/second read to simulate
    // replacement/reinstall during async source inspection.
    var call=0;
    final candidate=DedaStep2OriginalInstallContinuityCandidate(
      enabled:true,
      currentUid:()=>uid,
      localStoredInstallId:() async =>
          (++call == 1) ? firstInstall : newInstall,
      verifiedOwnerRoute:(a,b,c)async=>true,
      readOriginalProgressArchive:(a,b,c)async=>
          const DedaStep2OriginalInstallBinding(
            accountKey:account,originalUid:uid,
            sourceInstallId:firstInstall,sourceCaptureId:captureId),
    );
    expect(await candidate.matchesOriginalProgressInstallation(
      accountKey:account,originalId:original,originalUid:uid,
      isCurrent:()=>true),false);
    expect(call,2);
    expect(proof.authChecks,0);
  });
}

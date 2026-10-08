import 'dart:math' as math;

import 'package:d_iraq_ludo/deda_geo_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Iraq 5km window covers near and excludes far points', () {
    final w = DedaGeoWindow.around(
      latitude: 31.99, longitude: 44.93, radiusMeters: 5000);
    expect(w.longitudeRanges.length, 1);
    expect(w.includes(latitude: 31.99, longitude: 44.93), true);
    expect(w.includes(latitude: 32.0, longitude: 44.93), true);
    expect(w.includes(latitude: 35.0, longitude: 44.93), false);
    expect(w.includes(latitude: 31.99, longitude: 50.0), false);
  });

  test('Conservative envelope retains 2900m points in Iraq', () {
    for (final (lat, lon) in <(double,double)>[
      (31.99,44.93), (35.48,44.39), (29.98,48.49), (36.19,44.01)]) {
      final w=DedaGeoWindow.around(
        latitude: lat, longitude: lon, radiusMeters: 3000);
      expect(w.includes(
        latitude: lat+2900/111195, longitude: lon), true);
      expect(w.includes(
        latitude: lat, longitude: lon+2900/(111195*math.cos(lat*math.pi/180))), true);
    }
  });

  test('Both dateline splits retain both nearby sides', () {
    final east=DedaGeoWindow.around(
      latitude: 0, longitude: 179.99, radiusMeters: 7000);
    expect(east.longitudeRanges.length, 2);
    expect(east.includes(latitude: 0,longitude: 179.995),true);
    expect(east.includes(latitude: 0,longitude: -179.995),true);
    expect(east.includes(latitude: 0,longitude: 0),false);
    final west=DedaGeoWindow.around(
      latitude: -4,longitude: -179.99,radiusMeters: 8000);
    expect(west.longitudeRanges.length,2);
    expect(west.includes(latitude:-4,longitude:179.99),true);
    expect(west.includes(latitude:-4,longitude:-179.99),true);
  });

  test('Invalid radius, NaN, lat/lon rejected', () {
    for(final radius in <double>[-1,0,100001,double.nan]){
      expect(()=>DedaGeoWindow.around(
        latitude:31.99,longitude:44.93,radiusMeters:radius),
        throwsArgumentError);
    }
    expect(()=>DedaGeoWindow.around(
      latitude:91,longitude:44,radiusMeters:3000),throwsArgumentError);
    expect(()=>DedaGeoWindow.around(
      latitude:31,longitude:181,radiusMeters:3000),throwsArgumentError);
  });

  test('Cursors can retrieve well beyond 500 places without silent loss',
    () async {
    final stored=List<int>.generate(1251,(i)=>i);
    final result=await dedaCollectGeoPages<int>(
      budget:const DedaGeoQueryBudget(
        pageSize:100,maxPagesPerLongitudeRange:20),
      loadPage:(size,after) async {
        final start=(after??-1)+1;
        if(start>=stored.length) return <int>[];
        final end=start+size>stored.length?stored.length:start+size;
        return stored.sublist(start,end);
      },
    );
    expect(result.complete,true);
    expect(result.items.length,1251);
    expect(result.items[501],501);
  });

  test('Crowded region transparently declares incomplete results',() async {
    final result=await dedaCollectGeoPages<int>(
      budget:const DedaGeoQueryBudget(
        pageSize:10,maxPagesPerLongitudeRange:2),
      loadPage:(size,after) async {
        final start=(after??-1)+1;
        return List<int>.generate(size,(i)=>start+i);
      },
    );
    expect(result.complete,false);
    expect(result.items.length,20);
  });

  test('Exactly full last page is not silently assumed complete',() async {
    final stored=List<int>.generate(20,(i)=>i);
    final result=await dedaCollectGeoPages<int>(
      budget:const DedaGeoQueryBudget(
        pageSize:10,maxPagesPerLongitudeRange:2),
      loadPage:(size,after) async {
        final start=(after??-1)+1;
        return stored.sublist(start,start+size);
      },
    );
    expect(result.complete,false);
    expect(result.items.length,20);
  });

  test('Corrupt oversized pages rejected',() async {
    await expectLater(dedaCollectGeoPages<int>(
      budget:const DedaGeoQueryBudget(pageSize:10),
      loadPage:(size,after) async =>List<int>.filled(11,0)),
      throwsStateError);
  });
}

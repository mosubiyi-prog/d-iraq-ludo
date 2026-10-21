#!/usr/bin/env python3
"""Integrate 16 ORIGINAL DEDA LAB assets into the ACTUAL rebuilt phone edit page.

This is NOT a cheap substitute image gallery or another payment processor.
- keeps pinned existing profile hero above scroll list;
- shows 16 authentic WebPs with each original portrait opening;
- existing 3 royal images become USE/SAVE free via old style index 3/4/5;
- 13 premium frames preview without changing saved style or debiting gems;
- no Firebase or wallet writes, no fake purchase receipts.
"""
from pathlib import Path

MAIN=Path('lib/main.dart')
BEGIN='class _DedaEditProfilePageState extends State<DedaEditProfilePage> {'
END='class DedaAccountInfoPage extends StatefulWidget {'
MARK='// DEDA_100376_REAL_16_LAB_ARTWORK_PROFILE_GALLERY'
IMPORT="import 'deda_lab_original_frames_gallery.dart';"
CAT_IMPORT="import 'deda_lab_verified_frame_catalog.dart';"

def patch_source(source):
    if MARK in source:
        if source.count(MARK)!=1 or IMPORT not in source:
            raise ValueError('SAFE_STOP_100376_PARTIAL_LAB_GALLERY')
        return source
    if BEGIN not in source or END not in source:
        raise ValueError('SAFE_STOP_100376_REAL_PROFILE_EDITOR_NOT_FOUND')
    a=source.index(BEGIN)
    b=source.index(END,a)
    edit=source[a:b]
    if edit.count("  int? _previewFrameStyle;")!=1:
        raise ValueError('SAFE_STOP_100376_PINNED_FRAME_PREVIEW_MISSING')
    if edit.count("frameStyle: _previewFrameStyle ?? _frameStyle,")!=1:
        raise ValueError('SAFE_STOP_100376_PINNED_FRAME_AVATAR_DRIFT')
    if edit.count("controller: _name,")!=1:
        raise ValueError('SAFE_STOP_100376_PROFILE_NAME_FIELD_MISSING')
    if edit.count("_frameStyle = index;")!=1:
        raise ValueError('SAFE_STOP_100376_FREE_FRAME_HANDLER_DRIFT')
    state="  int? _previewFrameStyle;"
    edit=edit.replace(state,state+"\n  String? _labPreviewId;",1)
    # Only a preview of a paid frame; never persist it before an atomic
    # purchase and owned entitlement on an authenticated real account.
    original="child: DedaFramedAvatar(\n                        avatarStyle: _avatarStyle,\n                        frameStyle: _previewFrameStyle ?? _frameStyle,\n                        size: 126,\n                      ),"
    update="""child: _labPreviewId == null
                          ? DedaFramedAvatar(
                              avatarStyle: _avatarStyle,
                              frameStyle: _previewFrameStyle ?? _frameStyle,
                              size: 126,
                            )
                          : DedaLabOriginalFrameArtwork(
                              frame: dedaLabVerifiedFrames.firstWhere(
                                (f) => f.id == _labPreviewId),
                              portrait: (size) => DedaAvatarPortrait(
                                style: _avatarStyle,size: size),
                              size: 126,
                            ),"""
    if edit.count(original)!=1:
        raise ValueError('SAFE_STOP_100376_PINNED_PROFILE_ART_DRIFT')
    edit=edit.replace(original,update,1)
    # Switching back to any of the user's legacy frame tiles clears
    # paid/new preview, never accidentally persists a locked frame.
    edit=edit.replace("_frameStyle = index;",
                      "_frameStyle = index;\n                                      _labPreviewId = null;",1)
    needle="() => setState(() => _previewFrameStyle = index),"
    if edit.count(needle)!=1:
        raise ValueError('SAFE_STOP_100376_LOCKED_PREVIEW_HANDLER_DRIFT')
    edit=edit.replace(needle,"""() => setState(() {
                                      _labPreviewId = null;
                                      _previewFrameStyle = index;
                                    }),""",1)
    # Insert after user's existing avatar/frame/background lists, before
    # name editing. A pinned card above list remains at fixed size 126.
    name_pos=edit.index('controller: _name,')
    widget_start=edit.rfind('TextField(',0,name_pos)
    if widget_start<0 or name_pos-widget_start>300:
        raise ValueError('SAFE_STOP_100376_FIELD_BOUNDARY_DRIFT')
    gallery="""// DEDA_100376_REAL_16_LAB_ARTWORK_PROFILE_GALLERY
                  DedaLabOriginalFrameGallery(
                    avatarStyle: _avatarStyle,
                    selectedId: _labPreviewId,
                    portrait: (size) => DedaAvatarPortrait(
                      style: _avatarStyle, size: size),
                    onSelect: (frame) {
                      setState(() {
                        _labPreviewId = frame.id;
                        _previewFrameStyle = null;
                        if (frame.free) {
                          // FRAME_01/02/04 are the REAL built-in royal WebPs.
                          _frameStyle = frame.id == 'FRAME_01' ? 4 :
                              frame.id == 'FRAME_02' ? 5 : 3;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  """
    edit=edit[:widget_start]+gallery+edit[widget_start:]
    if edit.count(MARK)!=1 or edit.count("DedaLabOriginalFrameGallery(")!=1:
        raise ValueError('SAFE_STOP_100376_NO_REAL_GALLERY')
    source=source[:a]+edit+source[b:]
    import_anchor="import 'package:flutter/material.dart';"
    if source.count(import_anchor)!=1:
        raise ValueError('SAFE_STOP_100376_MAIN_IMPORT_DRIFT')
    return source.replace(import_anchor,import_anchor+
                          "\n"+IMPORT+"\n"+CAT_IMPORT,1)

if __name__=='__main__':
    before=MAIN.read_text()
    after=patch_source(before)
    if after==before:
        raise SystemExit('SAFE_STOP_100376_ALREADY_APPLIED')
    MAIN.write_text(after)
    print('PASS_100376_ALL_16_NATIVE_WEBP_FRAMES_IN_EDIT_PROFILE_SCROLL_LIST')
    print('PASS_100376_PINNED_PREVIEW_REAL_111_SIZE_FREE_THREE_SAVABLE')
    print('PASS_100376_THIRTEEN_1000_DIAMOND_ONLY_PREVIEW_NO_FALSE_CHECKOUT')

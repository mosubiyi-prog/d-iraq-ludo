"""Change read-only inventory paths; keep buyOnce, price and debit byte-exact."""
from pathlib import Path
from bind_auth_runtime import body_range


def bind_source(source):
    if 'DEDA_OWNED_FRAME_READER_BOUND_V1' in source:
        raise ValueError('Owned frame reader already bound')
    edits=[]
    for name,body in [
        ('isOwned',"\n    return DedaOwnedFrameReader(DedaFirebaseOwnedFrameReadIo(), frameIds: paidFrameIds).isOwned(originalId, frameId);\n  "),
        ('verifiedOwnedFrameIds',"\n    return DedaOwnedFrameReader(DedaFirebaseOwnedFrameReadIo(), frameIds: paidFrameIds).owned(originalId);\n  ")]:
        a,b,_,_=body_range(source,name)
        edits.append((a+1,b,body))
    for a,b,text in sorted(edits,reverse=True):source=source[:a]+text+source[b:]
    return "// DEDA_OWNED_FRAME_READER_BOUND_V1\nimport 'deda_owned_frame_reader.dart';\n"+source


def bind(output):
    p=Path(output)/'lib/deda_lab_frame_secure_checkout.dart'
    p.write_text(bind_source(p.read_text()))

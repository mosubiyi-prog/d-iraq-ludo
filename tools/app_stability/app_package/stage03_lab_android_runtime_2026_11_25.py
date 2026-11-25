"""Real Android SDK on disposable CI emulator only, existing lab account."""
import os
import time
from stage02_lab_android_runtime_2026_11_25 import adb, start, stop, tap, wait_node, credential, PACKAGE

def run():
    password=os.environ.pop('LAB_PASSWORD','')
    if len(password)<16: raise ValueError('dedicated lab secret required')
    adb('install','-r',os.environ['STAGE02_APK'])
    def fresh():
        if b'Success' not in adb('shell','pm','clear',PACKAGE): raise RuntimeError('disposable clear failed')
        start()
        wait_node('SIGNED_OUT_NO_ADMISSION')
        credential(password)
        tap('LOGIN_EXISTING')
        wait_node('UID_MATCHED_SERVER_UNVERIFIED')
    def either(labels,timeout=90):
        from stage02_lab_android_runtime_2026_11_25 import ui
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            try:
                for node in ui().iter('node'):
                    v=node.get('text','')+' '+node.get('content-desc','')
                    for label in labels:
                        if label in v: return label
            except Exception: pass
            time.sleep(1)
        raise RuntimeError('storage state absent')
    try:
        fresh()
        tap('RESTORE_STORAGE')
        initial=either(('RESTORE_V2_OK','RESTORE_V3_OK','BLOCKED_STORAGE'))
        if initial=='BLOCKED_STORAGE': raise RuntimeError('initial restore blocked')
        print('PASS_ANDROID_DART_RESTORE_EXISTING_SYNTHETIC',flush=True)
        tap('BACKUP_STORAGE')
        result=either(('BACKUP_V3_CONFIRMED','EXACT_V3_ALREADY_PRESENT_NO_WRITE','BLOCKED_STORAGE'))
        if result=='BLOCKED_STORAGE': raise RuntimeError('backup blocked')
        print('PASS_ANDROID_DART_'+result,flush=True)
        stop()
        start()
        wait_node('UID_MATCHED_SERVER_UNVERIFIED')
        tap('RESTORE_STORAGE')
        wait_node('RESTORE_V3_OK',timeout=90)
        print('PASS_ANDROID_DART_PROCESS_RESTART_RESTORE',flush=True)
        # Only disposable emulator data, never owner's handset; same account.
        fresh()
        tap('RESTORE_STORAGE')
        wait_node('RESTORE_V3_OK',timeout=90)
        print('PASS_ANDROID_DART_EMPTY_LOCAL_STORAGE_SAME_UID_RESTORE',flush=True)
        print('EMULATOR_REAL_BACKEND_NO_FULL_APP_NO_FINANCIAL_AUTHORITY',flush=True)
    finally:
        adb('uninstall',PACKAGE)

if __name__=='__main__':
    try: run()
    except Exception as exc:
        print('BLOCK_ANDROID_STAGE03',type(exc).__name__,flush=True)
        raise SystemExit(1) from None

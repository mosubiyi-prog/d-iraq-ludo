"""Exercise the real Android Auth SDK, not an emulated Firebase server.
No secret in APK, command line, logs or artifacts. No production app launch.
"""
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = 'com.deda.qa.uiddevice'


def adb(*args, data=None):
    result = subprocess.run(['adb',*args],input=data,stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,timeout=45,check=False)
    if result.returncode:
        raise RuntimeError('adb failed')
    return result.stdout


def ui():
    adb('shell','uiautomator','dump','/sdcard/deda-stage02-window.xml')
    return ET.fromstring(adb('shell','cat','/sdcard/deda-stage02-window.xml'))


def wait_node(label, timeout=65):
    end = time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            for node in ui().iter('node'):
                if label in (node.get('text','')+' '+node.get('content-desc','')):
                    return node
        except (RuntimeError, ET.ParseError, subprocess.TimeoutExpired):
            pass
        time.sleep(1)
    raise RuntimeError('expected UI state absent: '+label)


def tap(label):
    node=wait_node(label)
    nums=list(map(int,re.findall(r'\d+',node.get('bounds',''))))
    if len(nums)!=4:
        raise RuntimeError('invalid UI bounds')
    adb('shell','input','tap',str((nums[0]+nums[2])//2),str((nums[1]+nums[3])//2))


def start():
    adb('shell','am','start','-n',PACKAGE+'/.MainActivity')
    wait_node('ALL_SECTIONS_HELD')


def stop():
    adb('shell','am','force-stop',PACKAGE)


def credential(value):
    # stdin only, never arguments, output, APK, or source file.
    adb('shell','-T',"run-as "+PACKAGE+" sh -c 'umask 077; mkdir -p files; cat > files/stage02-qa-password'",
        data=value.encode())


def network(enabled):
    adb('shell','cmd','connectivity','airplane-mode','disable' if enabled else 'enable')
    adb('shell','svc','wifi','enable' if enabled else 'disable')
    adb('shell','svc','data','enable' if enabled else 'disable')


def run():
    password=os.environ.pop('LAB_PASSWORD','')
    if len(password)<16:
        raise ValueError('dedicated test secret required')
    apk=os.environ['STAGE02_APK']
    adb('install','-r',apk)
    try:
        adb('shell','pm','clear',PACKAGE)
        start()
        wait_node('SIGNED_OUT_NO_ADMISSION')
        credential('wrong-stage02-test-'+os.urandom(16).hex())
        tap('LOGIN_EXISTING')
        wait_node('LOGIN_REJECTED_NO_ADMISSION')
        print('PASS_ANDROID_WRONG_PASSWORD_NO_ADMISSION',flush=True)
        credential(password)
        tap('LOGIN_EXISTING')
        wait_node('UID_MATCHED_SERVER_UNVERIFIED')
        tap('VERIFY_SERVER')
        wait_node('UID_SERVER_VERIFIED')
        print('PASS_ANDROID_AUTH_SDK_PINNED_UID_SERVER_VERIFIED',flush=True)
        stop()
        start()
        wait_node('UID_MATCHED_SERVER_UNVERIFIED')
        tap('VERIFY_SERVER')
        wait_node('UID_SERVER_VERIFIED')
        print('PASS_ANDROID_PROCESS_RESTART_SAME_UID_NO_RELOGIN',flush=True)
        stop()
        network(False)
        time.sleep(4)
        start()
        wait_node('UID_MATCHED_SERVER_UNVERIFIED')
        tap('VERIFY_SERVER')
        wait_node('UID_RETAINED_SERVER_UNAVAILABLE')
        print('PASS_ANDROID_OFFLINE_RESTART_UID_RETAINED_SERVER_UNVERIFIED',flush=True)
        network(True)
        time.sleep(8)
        tap('VERIFY_SERVER')
        wait_node('UID_SERVER_VERIFIED',timeout=90)
        print('PASS_ANDROID_RECONNECT_SAME_UID_NO_RELOGIN',flush=True)
        print('AUTH_ONLY_RUNTIME_NO_FIRESTORE_NO_SECTIONS_NO_PRODUCTION',flush=True)
    finally:
        try:
            network(True)
        finally:
            adb('uninstall',PACKAGE)


if __name__=='__main__':
    try:
        run()
    except Exception as exc:
        # Never dump screen, SDK logs, tokens or password.
        print('BLOCK_ANDROID_STAGE02',type(exc).__name__,
              str(exc) if isinstance(exc,RuntimeError) else '',flush=True)
        raise SystemExit(1) from None

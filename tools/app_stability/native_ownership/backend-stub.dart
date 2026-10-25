// Only the canonical-ID derivation required by unused purchase dependencies.
// No Firebase, auth mutation, wallet, grant or purchase operation is provided.
class DedaBackend {
  static String personalShareIdForPhone(String phone) {
    const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final key=phone.replaceAll(RegExp(r'[^0-9]'),'');
    if(key.length<9) return '';
    var value=(int.parse(key.substring(key.length-9))+314159265)%1000000000;
    final result=List.filled(6,'A');
    for(var i=5;i>=0;i--){result[i]=alphabet[value%32];value~/=32;}
    return '@DEDA-${result.join()}';
  }
}

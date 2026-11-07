// DEDA 100439 isolated recovery UI protocol. Zero timers or fake progress.
// Only completed, verified external I/O steps may advance this indicator.
enum DedaGoogleRecoveryStage {
  accountChosen,
  googleTokenReceived,
  existingGoogleProviderResolved,
  firebaseOriginalUidSignedIn,
  originalUserReadFromServer,
  ownerDocumentsReadFromServer,
  originalOwnerVerified,
}

typedef DedaGoogleRecoveryProgress = void Function(DedaGoogleRecoveryStage stage);

// The current Google login verifies IDENTITY only; it MUST NOT return
// fullAccountRestored until a separate guardian result explicitly authorizes
// all restored domains and the final completion gate.
enum DedaGoogleRecoveryOutcome {
  cancelled,
  identityVerifiedOnly,
  fullAccountRestored,
}

class DedaGoogleRecoveryProgressPolicy {
  const DedaGoogleRecoveryProgressPolicy._();

  static int percent(DedaGoogleRecoveryStage stage) {
    switch (stage) {
      case DedaGoogleRecoveryStage.accountChosen:
        return 10;
      case DedaGoogleRecoveryStage.googleTokenReceived:
        return 25;
      case DedaGoogleRecoveryStage.existingGoogleProviderResolved:
        return 40;
      case DedaGoogleRecoveryStage.firebaseOriginalUidSignedIn:
        return 55;
      case DedaGoogleRecoveryStage.originalUserReadFromServer:
        return 65;
      case DedaGoogleRecoveryStage.ownerDocumentsReadFromServer:
        return 75;
      case DedaGoogleRecoveryStage.originalOwnerVerified:
        return 85;
    }
  }

  static String label(DedaGoogleRecoveryStage stage) {
    switch (stage) {
      case DedaGoogleRecoveryStage.accountChosen:
        return 'تم اختيار حساب جوجل';
      case DedaGoogleRecoveryStage.googleTokenReceived:
        return 'تم التحقق من استجابة جوجل';
      case DedaGoogleRecoveryStage.existingGoogleProviderResolved:
        return 'تأكد ارتباط جوجل بحساب موجود';
      case DedaGoogleRecoveryStage.firebaseOriginalUidSignedIn:
        return 'تم تسجيل الدخول بمعرف الحساب الأصلي';
      case DedaGoogleRecoveryStage.originalUserReadFromServer:
        return 'جارٍ مطابقة حساب ديدا الأصلي';
      case DedaGoogleRecoveryStage.ownerDocumentsReadFromServer:
        return 'جارٍ مراجعة سجل الحساب والآيدي';
      case DedaGoogleRecoveryStage.originalOwnerVerified:
        return 'الهوية مؤكدة، استرجاع الممتلكات لم يكتمل';
    }
  }

  static bool isSafeStep(int previous, DedaGoogleRecoveryStage next) =>
      percent(next) > previous && percent(next) < 100;
}

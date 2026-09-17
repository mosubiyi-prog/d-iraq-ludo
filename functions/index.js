const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {randomInt} = require("node:crypto");

initializeApp();

async function notifyTokens(tokens, title, body, type, requestId) {
  const uniqueTokens = [...new Set(tokens)].filter(Boolean).slice(0, 500);
  if (uniqueTokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens: uniqueTokens,
    notification: {title, body},
    data: {type, requestId},
    android: {priority: "high"},
  });
}

async function notifyAdmins(title, body, type, requestId) {
  const admins = await getFirestore()
      .collection("admins")
      .where("active", "==", true)
      .get();
  const tokens = [];
  admins.forEach((document) => {
    const values = document.data().fcmTokens;
    if (Array.isArray(values)) tokens.push(...values);
  });
  await notifyTokens(tokens, title, body, type, requestId);
}

async function notifyOwner(ownerUid, title, body, requestId, type = "place_result") {
  if (!ownerUid) return;
  const user = await getFirestore().collection("users").doc(ownerUid).get();
  if (!user.exists) return;
  const values = user.data().fcmTokens;
  const tokens = Array.isArray(values) ? values : [];
  await notifyTokens(tokens, title, body, type, requestId);
}

function normalizeName(value) {
  return String(value || "")
      .trim()
      .replace(/\s+/g, " ")
      .toLowerCase();
}

exports.onSupportRequestCreated = onDocumentCreated(
    "support_requests/{requestId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;
      await notifyAdmins(
          "رسالة دعم جديدة في DEDA",
          data.name || "طلب دعم جديد",
          "support",
          event.params.requestId,
      );
    },
);

// DEDA 10-point fixes v1: notify users when support is handled or replied to.
exports.onSupportRequestUpdated = onDocumentUpdated(
    "support_requests/{requestId}",
    async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;
      if (before.status === after.status && before.adminReply === after.adminReply) return;

      let title = "تحديث من دعم DEDA";
      let body = "تم تحديث حالة رسالتك لدى فريق DEDA.";
      if (after.status === "in_progress") {
        body = "رسالتك قيد المعالجة لدى فريق DEDA.";
      } else if (after.status === "replied") {
        title = "رد جديد من دعم DEDA";
        body = after.adminReply || "لديك رد جديد من فريق DEDA.";
      } else if (after.status === "closed") {
        title = "تم إغلاق طلب الدعم في DEDA";
        body = after.adminReply || "تمت معالجة طلب الدعم وإغلاقه.";
      }
      await notifyOwner(
          after.ownerUid,
          title,
          body,
          event.params.requestId,
          "support_result",
      );
    },
);

exports.onPlaceRequestCreated = onDocumentCreated(
    "place_requests/{requestId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;
      await notifyAdmins(
          "طلب مكان جديد في DEDA",
          data.placeName || "مكان جديد للمراجعة",
          "place",
          event.params.requestId,
      );
    },
);

exports.onPlaceRequestUpdated = onDocumentUpdated(
    "place_requests/{requestId}",
    async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after || before.status === after.status) return;

      let title = "تحديث طلب المكان في DEDA";
      let body = `تم تحديث حالة ${after.placeName || "المكان"}.`;
      if (after.status === "approved") {
        title = "تم اعتماد مكانك في DEDA";
        body = after.approvalMessage || `تم اعتماد: ${after.placeName || "المكان"}`;
      } else if (after.status === "needs_changes") {
        title = "طلب المكان يحتاج تعديل";
        body = after.decisionNote || "يرجى فتح إدارة مكاني والاطلاع على المطلوب ثم إعادة الإرسال.";
      } else if (after.status === "rejected") {
        title = "نتيجة مراجعة طلب المكان";
        body = after.decisionNote || "تعذر اعتماد طلب المكان حالياً.";
      } else if (after.status === "reviewing") {
        title = "طلب مكانك قيد المراجعة";
        body = `بدأت إدارة DEDA مراجعة ${after.placeName || "المكان"}.`;
      }

      await notifyOwner(
          after.ownerUid,
          title,
          body,
          event.params.requestId,
      );
    },
);

exports.onRecoveryRequestCreated = onDocumentCreated(
    "recovery_requests/{requestId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const firestore = getFirestore();
      const requestRef = event.data.ref;
      const accountKey = String(data.accountKey || "").trim();
      let accountFound = false;
      let sameDevice = false;
      let nameMatches = false;
      let riskLevel = "review";

      try {
        const directory = await firestore
            .collection("deda_account_directory")
            .doc(accountKey)
            .get();
        if (directory.exists && directory.data().active === true) {
          const authEmail = String(directory.data().authEmail || "").trim();
          if (authEmail) {
            const userRecord = await getAuth().getUserByEmail(authEmail);
            const profile = await firestore.collection("users").doc(userRecord.uid).get();
            const profileData = profile.exists ? profile.data() : {};
            const trusted = Array.isArray(profileData.trustedInstallIds) ?
              profileData.trustedInstallIds : [];
            sameDevice = trusted.includes(String(data.requesterInstallId || ""));
            nameMatches = normalizeName(profileData.name) === normalizeName(data.fullName);
            accountFound = true;
            riskLevel = sameDevice && nameMatches ? "low" : "review";
          }
        }
      } catch (_) {
        riskLevel = "review";
      }

      await requestRef.update({
        accountFound,
        sameDevice,
        nameMatches,
        riskLevel,
        status: riskLevel === "low" ? "new" : "review",
        checkedAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });

      await notifyAdmins(
          "طلب استرجاع دخول جديد في DEDA",
          data.fullName || data.phone || "طلب استرجاع",
          "recovery",
          event.params.requestId,
      );
    },
);

exports.onRecoveryRequestUpdated = onDocumentUpdated(
    "recovery_requests/{requestId}",
    async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;
      if (before.status === after.status) return;
      if (after.status !== "approved") return;

      const firestore = getFirestore();
      const requestRef = event.data.after.ref;
      const accountKey = String(after.accountKey || "").trim();
      const requesterUid = String(after.requesterUid || "").trim();

      try {
        const directory = await firestore
            .collection("deda_account_directory")
            .doc(accountKey)
            .get();
        if (!directory.exists || directory.data().active !== true) {
          throw new Error("account-directory-missing");
        }

        const authEmail = String(directory.data().authEmail || "").trim();
        if (!authEmail) throw new Error("auth-email-missing");
        const userRecord = await getAuth().getUserByEmail(authEmail);
        const pin = String(randomInt(100000, 1000000));
        await getAuth().updateUser(userRecord.uid, {password: pin});

        const now = Date.now();
        await firestore
            .collection("recovery_secrets")
            .doc(event.params.requestId)
            .set({
              requesterUid,
              pin,
              createdAt: Timestamp.fromMillis(now),
              expiresAt: Timestamp.fromMillis(now + (30 * 60 * 1000)),
            });

        await requestRef.update({
          status: "ready",
          resolvedAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
          processingError: null,
        });
      } catch (error) {
        await requestRef.update({
          status: "error",
          updatedAt: Timestamp.now(),
          processingError: String(error && error.message ? error.message : "recovery-failed"),
        });
      }
    },
);

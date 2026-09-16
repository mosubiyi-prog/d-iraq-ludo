const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

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

async function notifyOwner(ownerUid, title, body, requestId) {
  if (!ownerUid) return;
  const user = await getFirestore().collection("users").doc(ownerUid).get();
  if (!user.exists) return;
  const values = user.data().fcmTokens;
  const tokens = Array.isArray(values) ? values : [];
  await notifyTokens(tokens, title, body, "place_result", requestId);
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

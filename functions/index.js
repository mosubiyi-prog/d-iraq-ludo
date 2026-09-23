const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
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

async function notifyAdmins(title, body, type, requestId, options = {}) {
  const admins = await getFirestore()
      .collection("admins")
      .where("active", "==", true)
      .get();
  const tokens = [];
  admins.forEach((document) => {
    const data = document.data() || {};
    if (normalizedAdminStatus(data) !== "active") return;
    const role = normalizedAdminRole(data);
    if (options.permission &&
        !adminDocumentHasPermission(data, options.permission)) return;
    if (options.allowProvinceAgent === false && role === "province_agent") {
      return;
    }
    if (role === "province_agent" && options.governorate) {
      if (String(data.governorate || "").trim() !==
          String(options.governorate || "").trim()) return;
    }
    const values = data.fcmTokens;
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
          {permission: "supportRead", allowProvinceAgent: false},
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
          {
            permission: "viewPlaceRequests",
            governorate: data.governorate,
          },
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
          {permission: "supportRead", allowProvinceAgent: false},
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


const ADMIN_ROLES = new Set([
  "general_manager",
  "deputy_manager",
  "employee",
  "province_agent",
]);

const ADMIN_STATUSES = new Set([
  "active",
  "temporarily_stopped",
  "disabled",
]);

const ADMIN_PERMISSION_KEYS = [
  "supportRead",
  "supportReply",
  "viewPlaceRequests",
  "reviewPlaceRequests",
  "approvePlaces",
  "rejectPlaces",
  "viewUsers",
  "viewReports",
  "manageReports",
  "viewGovernorates",
  "viewAudit",
];

function legacyGeneralManagerRole(role) {
  return ["manager", "director", "admin", "general_manager"].includes(
      String(role || "").trim().toLowerCase(),
  );
}

function normalizedAdminRole(data) {
  const raw = String((data && (data.role || data.jobTitle)) || "")
      .trim()
      .toLowerCase();
  if (legacyGeneralManagerRole(raw) || raw === "") return "general_manager";
  if (["assistant", "assistant_manager", "assistant-manager", "deputy_manager"]
      .includes(raw)) return "deputy_manager";
  if (["employee", "staff"].includes(raw)) return "employee";
  if (["province_agent", "governorate_agent", "agent"].includes(raw)) {
    return "province_agent";
  }
  return raw;
}

function normalizedAdminStatus(data) {
  if (!data) return "disabled";
  const raw = String(data.status || "").trim().toLowerCase();
  if (ADMIN_STATUSES.has(raw)) return raw;
  return data.active === true ? "active" : "disabled";
}

function adminDocumentHasPermission(data, permission) {
  if (normalizedAdminRole(data) === "general_manager") return true;
  const permissions = data && typeof data.permissions === "object" ?
    data.permissions : {};
  return permissions[permission] === true;
}

function defaultPermissions(role) {
  const all = Object.fromEntries(ADMIN_PERMISSION_KEYS.map((key) => [key, true]));
  if (role === "general_manager") return all;
  if (role === "deputy_manager") {
    return {
      ...all,
      manageReports: true,
    };
  }
  if (role === "province_agent") {
    return {
      supportRead: false,
      supportReply: false,
      viewPlaceRequests: true,
      reviewPlaceRequests: true,
      approvePlaces: false,
      rejectPlaces: false,
      viewUsers: false,
      viewReports: false,
      manageReports: false,
      viewGovernorates: true,
      viewAudit: false,
    };
  }
  return Object.fromEntries(ADMIN_PERMISSION_KEYS.map((key) => [key, false]));
}

function normalizePermissions(role, value) {
  const defaults = defaultPermissions(role);
  const input = value && typeof value === "object" ? value : {};
  const result = {};
  for (const key of ADMIN_PERMISSION_KEYS) {
    result[key] = role === "general_manager" ? true : input[key] === true;
    if (!(key in input) && role !== "general_manager") {
      result[key] = defaults[key] === true;
    }
  }
  if (role === "province_agent") {
    result.supportRead = false;
    result.supportReply = false;
    result.viewUsers = false;
    result.viewReports = false;
    result.viewAudit = false;
    result.manageReports = false;
  }
  if (result.supportReply) result.supportRead = true;
  if (result.reviewPlaceRequests || result.approvePlaces || result.rejectPlaces) {
    result.viewPlaceRequests = true;
  }
  if (result.manageReports) result.viewReports = true;
  return result;
}

async function requireActiveAdmin(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "admin-sign-in-required");
  }
  const firestore = getFirestore();
  const ref = firestore.collection("admins").doc(request.auth.uid);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "admin-not-found");
  }
  const data = snapshot.data() || {};
  if (data.active !== true || normalizedAdminStatus(data) !== "active") {
    throw new HttpsError("permission-denied", "admin-not-active");
  }
  return {
    uid: request.auth.uid,
    ref,
    data,
    role: normalizedAdminRole(data),
    name: String(data.displayName || data.name || request.auth.token.email || "DEDA Admin")
        .trim(),
  };
}

async function requireGeneralManager(request) {
  const actor = await requireActiveAdmin(request);
  if (actor.role !== "general_manager") {
    throw new HttpsError("permission-denied", "general-manager-required");
  }
  return actor;
}

function adminAuditData(actor, action, extra = {}) {
  return {
    action,
    adminUid: actor.uid,
    adminName: actor.name,
    adminRole: actor.role,
    createdAt: Timestamp.now(),
    ...extra,
  };
}

async function writeAdminAudit(actor, action, extra = {}) {
  await getFirestore()
      .collection("admin_audit")
      .add(adminAuditData(actor, action, extra));
}

async function countOtherActiveGeneralManagers(excludedUid) {
  const snapshot = await getFirestore().collection("admins").get();
  let count = 0;
  snapshot.forEach((document) => {
    if (document.id === excludedUid) return;
    const data = document.data() || {};
    if (data.active === true &&
        normalizedAdminStatus(data) === "active" &&
        normalizedAdminRole(data) === "general_manager") {
      count += 1;
    }
  });
  return count;
}

function cleanText(value, maxLength = 200) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function temporaryPassword() {
  return String(randomInt(10000000, 100000000));
}

async function nextAdminId() {
  const firestore = getFirestore();
  const counterRef = firestore.collection("system_counters").doc("admin_members");
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(counterRef);
    const current = snapshot.exists ? Number(snapshot.data().value || 0) : 0;
    const next = current + 1;
    transaction.set(counterRef, {
      value: next,
      updatedAt: Timestamp.now(),
    }, {merge: true});
    return "DEDA-ADM-" + String(next).padStart(6, "0");
  });
}

exports.ensureCurrentAdminProfile = onCall(async (request) => {
  const actor = await requireActiveAdmin(request);
  const current = actor.data || {};
  const role = actor.role;
  const status = normalizedAdminStatus(current);
  const permissions = normalizePermissions(role, current.permissions);
  let adminId = cleanText(current.adminId, 40);

  if (!adminId) {
    adminId = await nextAdminId();
  }

  const displayName = cleanText(
      current.displayName ||
      current.name ||
      request.auth.token.name ||
      request.auth.token.email ||
      "DEDA Admin",
      120,
  );
  const email = cleanEmail(
      current.email || request.auth.token.email || "",
  );
  const now = Timestamp.now();

  const update = {
    adminId,
    displayName,
    email,
    role,
    status,
    active: status === "active",
    permissions,
    department: cleanText(current.department, 80),
    governorate: role === "province_agent" ?
      cleanText(current.governorate, 80) : "",
    updatedAt: now,
  };

  if (!current.createdAt) {
    update.createdAt = now;
    update.createdByUid = actor.uid;
    update.createdByName = displayName;
  }
  if (!current.permissionsUpdatedAt) {
    update.permissionsUpdatedAt = now;
    update.permissionsUpdatedByUid = actor.uid;
    update.permissionsUpdatedByName = displayName;
  }

  await actor.ref.set(update, {merge: true});

  if (!current.adminId ||
      normalizedAdminRole(current.role || current.jobTitle) !== role ||
      normalizedAdminStatus(current) !== status) {
    await writeAdminAudit(actor, "admin_profile_normalized", {
      targetAdminUid: actor.uid,
      targetAdminId: adminId,
      targetAdminName: displayName,
      targetAdminRole: role,
    });
  }

  return {
    uid: actor.uid,
    ...current,
    ...update,
  };
});

exports.createAdminMember = onCall(async (request) => {
  const actor = await requireGeneralManager(request);
  const input = request.data || {};
  const displayName = cleanText(input.displayName, 120);
  const email = cleanEmail(input.email);
  const phone = cleanText(input.phone, 30);
  const department = cleanText(input.department, 80);
  const role = cleanText(input.role, 40).toLowerCase();
  const governorate = cleanText(input.governorate, 80);

  if (!displayName) {
    throw new HttpsError("invalid-argument", "display-name-required");
  }
  if (!email || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "valid-email-required");
  }
  if (!department) {
    throw new HttpsError("invalid-argument", "department-required");
  }
  if (!ADMIN_ROLES.has(role)) {
    throw new HttpsError("invalid-argument", "invalid-admin-role");
  }
  if (role === "province_agent" && !governorate) {
    throw new HttpsError("invalid-argument", "governorate-required");
  }

  const password = temporaryPassword();
  let userRecord;
  try {
    userRecord = await getAuth().createUser({
      email,
      password,
      displayName,
      disabled: false,
    });
  } catch (error) {
    if (String(error && error.code || "").includes("email-already-exists")) {
      throw new HttpsError("already-exists", "email-already-exists");
    }
    throw error;
  }

  const adminId = await nextAdminId();
  const permissions = normalizePermissions(role, input.permissions);
  const now = Timestamp.now();

  try {
    const firestore = getFirestore();
    const batch = firestore.batch();
    const adminRef = firestore.collection("admins").doc(userRecord.uid);
    const auditRef = firestore.collection("admin_audit").doc();

    batch.set(adminRef, {
      adminId,
      displayName,
      email,
      phone,
      department,
      role,
      governorate: role === "province_agent" ? governorate : "",
      status: "active",
      active: true,
      permissions,
      mustChangePassword: true,
      createdAt: now,
      updatedAt: now,
      createdByUid: actor.uid,
      createdByName: actor.name,
      permissionsUpdatedAt: now,
      permissionsUpdatedByUid: actor.uid,
      permissionsUpdatedByName: actor.name,
      lastSeenAt: null,
      firstLoginCompletedAt: null,
    });

    batch.set(auditRef, adminAuditData(actor, "admin_member_created", {
      targetAdminUid: userRecord.uid,
      targetAdminId: adminId,
      targetAdminName: displayName,
      targetAdminRole: role,
      targetGovernorate: role === "province_agent" ? governorate : null,
    }));

    await batch.commit();
  } catch (error) {
    try {
      await getAuth().deleteUser(userRecord.uid);
    } catch (_) {}
    throw error;
  }

  return {
    uid: userRecord.uid,
    adminId,
    email,
    temporaryPassword: password,
    mustChangePassword: true,
  };
});

exports.updateAdminMember = onCall(async (request) => {
  const actor = await requireGeneralManager(request);
  const input = request.data || {};
  const targetUid = cleanText(input.uid, 160);
  const reason = cleanText(input.reason, 500);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "target-admin-required");
  }

  const firestore = getFirestore();
  const ref = firestore.collection("admins").doc(targetUid);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "admin-member-not-found");
  }
  const current = snapshot.data() || {};
  const oldRole = normalizedAdminRole(current);
  const oldStatus = normalizedAdminStatus(current);

  const role = input.role == null ?
    oldRole : cleanText(input.role, 40).toLowerCase();
  const status = input.status == null ?
    oldStatus : cleanText(input.status, 40).toLowerCase();
  const displayName = input.displayName == null ?
    cleanText(current.displayName || current.name, 120) :
    cleanText(input.displayName, 120);
  const phone = input.phone == null ?
    cleanText(current.phone, 30) : cleanText(input.phone, 30);
  const department = input.department == null ?
    cleanText(current.department, 80) : cleanText(input.department, 80);
  const governorate = input.governorate == null ?
    cleanText(current.governorate, 80) : cleanText(input.governorate, 80);
  const permissions = input.permissions == null ?
    normalizePermissions(role, current.permissions) :
    normalizePermissions(role, input.permissions);

  if (!ADMIN_ROLES.has(role)) {
    throw new HttpsError("invalid-argument", "invalid-admin-role");
  }
  if (!ADMIN_STATUSES.has(status)) {
    throw new HttpsError("invalid-argument", "invalid-admin-status");
  }
  if (!displayName) {
    throw new HttpsError("invalid-argument", "display-name-required");
  }
  if (!department) {
    throw new HttpsError("invalid-argument", "department-required");
  }
  if (role === "province_agent" && !governorate) {
    throw new HttpsError("invalid-argument", "governorate-required");
  }

  const roleChanged = role !== oldRole;
  const statusChanged = status !== oldStatus;
  const permissionsChanged =
      JSON.stringify(permissions) !== JSON.stringify(
          normalizePermissions(oldRole, current.permissions),
      );
  if ((roleChanged || statusChanged || permissionsChanged) && !reason) {
    throw new HttpsError("invalid-argument", "reason-required");
  }

  const removingGeneralManager =
      oldRole === "general_manager" &&
      oldStatus === "active" &&
      (role !== "general_manager" || status !== "active");
  if (removingGeneralManager) {
    const remaining = await countOtherActiveGeneralManagers(targetUid);
    if (remaining < 1) {
      throw new HttpsError("failed-precondition", "last-general-manager");
    }
  }

  if (targetUid === actor.uid && status !== "active") {
    throw new HttpsError("failed-precondition", "cannot-stop-current-session");
  }

  const now = Timestamp.now();
  const update = {
    displayName,
    phone,
    department,
    role,
    governorate: role === "province_agent" ? governorate : "",
    status,
    active: status === "active",
    permissions,
    updatedAt: now,
    updatedByUid: actor.uid,
    updatedByName: actor.name,
  };
  if (permissionsChanged) {
    update.permissionsUpdatedAt = now;
    update.permissionsUpdatedByUid = actor.uid;
    update.permissionsUpdatedByName = actor.name;
  }
  if (statusChanged) {
    update.statusUpdatedAt = now;
    update.statusUpdatedByUid = actor.uid;
    update.statusUpdatedByName = actor.name;
    update.statusReason = reason;
  }

  const previousAuthDisabled = oldStatus === "disabled";
  let authUpdated = false;
  try {
    await getAuth().updateUser(targetUid, {
      displayName,
      disabled: status === "disabled",
    });
    authUpdated = true;

    const batch = firestore.batch();
    const auditRef = firestore.collection("admin_audit").doc();
    batch.set(ref, update, {merge: true});
    batch.set(auditRef, adminAuditData(actor, "admin_member_updated", {
      targetAdminUid: targetUid,
      targetAdminId: current.adminId || null,
      targetAdminName: displayName,
      oldRole,
      newRole: role,
      oldStatus,
      newStatus: status,
      permissionsChanged,
      reason: reason || null,
    }));
    await batch.commit();
  } catch (error) {
    if (authUpdated) {
      try {
        await getAuth().updateUser(targetUid, {
          displayName: cleanText(
              current.displayName || current.name || "",
              120,
          ),
          disabled: previousAuthDisabled,
        });
      } catch (_) {}
    }
    throw error;
  }

  if (status !== "active") {
    try {
      await getAuth().revokeRefreshTokens(targetUid);
    } catch (_) {}
  }

  return {success: true};
});

exports.revokeAdminMemberSessions = onCall(async (request) => {
  const actor = await requireGeneralManager(request);
  const targetUid = cleanText((request.data || {}).uid, 160);
  const reason = cleanText((request.data || {}).reason, 500);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "target-admin-required");
  }
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason-required");
  }

  const target = await getFirestore().collection("admins").doc(targetUid).get();
  if (!target.exists) {
    throw new HttpsError("not-found", "admin-member-not-found");
  }

  await getAuth().revokeRefreshTokens(targetUid);
  await writeAdminAudit(actor, "admin_sessions_revoked", {
    targetAdminUid: targetUid,
    targetAdminId: target.data().adminId || null,
    targetAdminName: target.data().displayName || target.data().name || "",
    reason,
  });
  return {success: true};
});

exports.resetAdminTemporaryPassword = onCall(async (request) => {
  const actor = await requireGeneralManager(request);
  const targetUid = cleanText((request.data || {}).uid, 160);
  const reason = cleanText((request.data || {}).reason, 500);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "target-admin-required");
  }
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason-required");
  }

  const targetRef = getFirestore().collection("admins").doc(targetUid);
  const target = await targetRef.get();
  if (!target.exists) {
    throw new HttpsError("not-found", "admin-member-not-found");
  }
  if (normalizedAdminStatus(target.data()) !== "active") {
    throw new HttpsError("failed-precondition", "admin-not-active");
  }

  const password = temporaryPassword();
  await getAuth().updateUser(targetUid, {password});
  await getAuth().revokeRefreshTokens(targetUid);
  await targetRef.set({
    mustChangePassword: true,
    updatedAt: Timestamp.now(),
  }, {merge: true});
  await writeAdminAudit(actor, "admin_temporary_password_reset", {
    targetAdminUid: targetUid,
    targetAdminId: target.data().adminId || null,
    targetAdminName: target.data().displayName || target.data().name || "",
    reason,
  });
  return {temporaryPassword: password};
});

exports.completeAdminFirstLogin = onCall(async (request) => {
  const actor = await requireActiveAdmin(request);
  const now = Timestamp.now();
  await actor.ref.set({
    mustChangePassword: false,
    firstLoginCompletedAt: now,
    lastSeenAt: now,
    updatedAt: now,
  }, {merge: true});
  await writeAdminAudit(actor, "admin_first_login_completed", {
    targetAdminUid: actor.uid,
    targetAdminName: actor.name,
  });
  return {success: true};
});

exports.deleteAdminMember = onCall(async (request) => {
  const actor = await requireGeneralManager(request);
  const input = request.data || {};
  const targetUid = cleanText(input.uid, 160);
  const reason = cleanText(input.reason, 500);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "target-admin-required");
  }
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason-required");
  }
  if (targetUid === actor.uid) {
    throw new HttpsError("failed-precondition", "cannot-delete-current-admin");
  }

  const firestore = getFirestore();
  const ref = firestore.collection("admins").doc(targetUid);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "admin-member-not-found");
  }
  const data = snapshot.data() || {};
  if (normalizedAdminRole(data) === "general_manager" &&
      normalizedAdminStatus(data) === "active") {
    const remaining = await countOtherActiveGeneralManagers(targetUid);
    if (remaining < 1) {
      throw new HttpsError("failed-precondition", "last-general-manager");
    }
  }

  const batch = firestore.batch();
  const auditRef = firestore.collection("admin_audit").doc();
  const historyRef = firestore.collection("admin_history").doc(targetUid);

  batch.set(auditRef, adminAuditData(actor, "admin_member_deleted", {
    targetAdminUid: targetUid,
    targetAdminId: data.adminId || null,
    targetAdminName: data.displayName || data.name || "",
    targetAdminRole: normalizedAdminRole(data),
    reason,
  }));
  batch.set(historyRef, {
    ...data,
    deletedAt: Timestamp.now(),
    deletedByUid: actor.uid,
    deletedByName: actor.name,
    deleteReason: reason,
  }, {merge: true});
  batch.delete(ref);
  await batch.commit();

  try {
    await getAuth().deleteUser(targetUid);
  } catch (_) {}
  return {success: true};
});

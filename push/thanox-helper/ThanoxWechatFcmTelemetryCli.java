package com.codex.wechatpush;

import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;

import java.lang.reflect.Method;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Raw-Binder client locked to the reviewed Thanox 8.6 AIDL order. */
public final class ThanoxWechatFcmTelemetryCli {
    private static final String SERVICE_NAME = "tv_input";
    private static final String ITHANOS = "github.tornaco.android.thanos.core.IThanos";
    private static final String IPROFILE = "github.tornaco.android.thanos.core.profile.IProfileManager";
    private static final String ICALLBACK = "github.tornaco.android.thanos.core.profile.IRuleAddCallback";

    private static final int ITHANOS_GET_PROFILE_MANAGER = 11;
    private static final int ITHANOS_WHO_ARE_YOU = 20;

    private static final int PROFILE_DELETE_RULE = 4;
    private static final int PROFILE_GET_ENABLED_RULES = 11;
    private static final int PROFILE_ENABLE_RULE_BY_NAME = 40;
    private static final int PROFILE_DISABLE_RULE_BY_NAME = 41;
    private static final int PROFILE_SET_ENABLED = 12;
    private static final int PROFILE_IS_ENABLED = 13;
    private static final int PROFILE_SET_PUSH_ENABLED = 23;
    private static final int PROFILE_IS_PUSH_ENABLED = 24;
    private static final int PROFILE_SET_SHELL_SU_INSTALLED = 25;
    private static final int PROFILE_IS_SHELL_SU_INSTALLED = 26;
    private static final int PROFILE_ADD_IF_NOT_EXISTS = 34;
    private static final int PROFILE_EXECUTE_ACTION = 48;
    private static final int PROFILE_GET_RULE_BY_NAME = 52;

    private static final String TELEMETRY_RULE_NAME = "Codex WeChat FCM Transport Telemetry";
    private static final String RECLAIM_RULE_NAME = "Codex WeChat FCM Nonstop Reclaimer";
    private static final String POST_USE_RECLAIM_RULE_NAME =
            "Codex WeChat Post-Use Nonstop Reclaimer";
    private static final String TELEMETRY_RULE_JSON = "[{"
            + "\"name\":\"" + TELEMETRY_RULE_NAME + "\","
            + "\"description\":\"Append only receive time and the fixed WeChat package name; never record payload or notification content.\","
            + "\"priority\":1,\"delay\":0,"
            + "\"condition\":\"fcmPushMessageArrived == true && pkgName == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"io.writeAppend(\\\"wechat_fcm_transport.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm\\\\n\\\");\"]"
            + "}]";
    private static final String LEGACY_RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After an FCM delivery grace period, kill only WeChat background processes when WeChat is neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":150000,"
            + "\"condition\":\"fcmPushMessageArrived == true && pkgName == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { thanos.activityManager.killBackgroundProcesses(\\\"com.tencent.mm\\\"); io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=attempted\\\\n\\\"); } else { io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String LEGACY_POST_USE_RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + POST_USE_RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After WeChat leaves the foreground, kill only its background processes after a grace period when it is still neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":150000,"
            + "\"condition\":\"frontPkgChanged == true && from == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { thanos.activityManager.killBackgroundProcesses(\\\"com.tencent.mm\\\"); io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=attempted\\\\n\\\"); } else { io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String SH_RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After an FCM delivery grace period, run Android am kill for WeChat only when it is neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":150000,"
            + "\"condition\":\"fcmPushMessageArrived == true && pkgName == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { sh.exe(\\\"am kill com.tencent.mm\\\"); io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_attempted\\\\n\\\"); } else { io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String SH_POST_USE_RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + POST_USE_RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After WeChat leaves the foreground, run Android am kill after a grace period only when it is still neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":150000,"
            + "\"condition\":\"frontPkgChanged == true && from == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { sh.exe(\\\"am kill com.tencent.mm\\\"); io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_attempted\\\\n\\\"); } else { io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After an FCM delivery grace period, run Android am kill for WeChat only when it is neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":30000,"
            + "\"condition\":\"fcmPushMessageArrived == true && pkgName == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { result = su.exe(\\\"am kill com.tencent.mm\\\"); if (result != null && result.getCode() == 0) { io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_ok\\\\n\\\"); } else { io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_failed\\\\n\\\"); } } else { io.writeAppend(\\\"wechat_fcm_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String POST_USE_RECLAIM_RULE_JSON = "[{"
            + "\"name\":\"" + POST_USE_RECLAIM_RULE_NAME + "\","
            + "\"description\":\"After WeChat leaves the foreground, run Android am kill after a grace period only when it is still neither foreground nor holding audio focus; never force-stop.\","
            + "\"priority\":1,\"delay\":30000,"
            + "\"condition\":\"frontPkgChanged == true && from == \\\"com.tencent.mm\\\"\","
            + "\"actions\":[\"if (!thanos.activityManager.isAppForeground(\\\"com.tencent.mm\\\") && !thanos.audioManager.hasAudioFocus(\\\"com.tencent.mm\\\")) { result = su.exe(\\\"am kill com.tencent.mm\\\"); if (result != null && result.getCode() == 0) { io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_ok\\\\n\\\"); } else { io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=am_kill_failed\\\\n\\\"); } } else { io.writeAppend(\\\"wechat_post_use_reclaim.log\\\", \\\"epoch_ms=\\\" + System.currentTimeMillis() + \\\" package=com.tencent.mm outcome=skipped_active\\\\n\\\"); }\"]"
            + "}]";
    private static final String RECLAIM_RULE_JSON_150_SECONDS =
            RECLAIM_RULE_JSON.replace("\"delay\":30000", "\"delay\":150000");
    private static final String POST_USE_RECLAIM_RULE_JSON_150_SECONDS =
            POST_USE_RECLAIM_RULE_JSON.replace("\"delay\":30000", "\"delay\":150000");
    private static final String RECLAIM_SMOKE_ACTION =
            "if (!thanos.activityManager.isAppForeground(\"com.tencent.mm\") "
            + "&& !thanos.audioManager.hasAudioFocus(\"com.tencent.mm\")) { "
            + "result = su.exe(\"am kill com.tencent.mm\"); "
            + "if (result != null && result.getCode() == 0) { "
            + "io.writeAppend(\"wechat_reclaim_smoke.log\", \"epoch_ms=\" "
            + "+ System.currentTimeMillis() + \" package=com.tencent.mm outcome=am_kill_ok\\n\"); "
            + "} else { io.writeAppend(\"wechat_reclaim_smoke.log\", \"epoch_ms=\" "
            + "+ System.currentTimeMillis() + \" package=com.tencent.mm outcome=am_kill_failed\\n\"); "
            + "} } else { io.writeAppend(\"wechat_reclaim_smoke.log\", \"epoch_ms=\" "
            + "+ System.currentTimeMillis() + \" package=com.tencent.mm outcome=skipped_active\\n\"); }";

    private ThanoxWechatFcmTelemetryCli() {}

    public static void main(String[] args) {
        try {
            if (args.length == 0) {
                throw new IllegalArgumentException(
                        "Expected audit, execute-reclaim-smoke, apply, apply-reclaim, apply-post-use-reclaim, upgrade-reclaimers, remove, remove-reclaim, or remove-post-use-reclaim.");
            }
            IBinder root = getService(SERVICE_NAME);
            require(root != null, "Thanox Binder service is unavailable.");
            require(ITHANOS.equals(root.getInterfaceDescriptor()), "Unexpected root descriptor.");
            String identity = readString(root, ITHANOS, ITHANOS_WHO_ARE_YOU);
            require(identity != null && identity.contains("Thanox"), "Thanox identity check failed.");
            IBinder profile = readBinder(root, ITHANOS, ITHANOS_GET_PROFILE_MANAGER);
            require(profile != null && IPROFILE.equals(profile.getInterfaceDescriptor()),
                    "Profile Binder service is unavailable.");

            String command = args[0].toLowerCase(Locale.ROOT);
            if ("audit".equals(command)) {
                printState(readState(profile));
                return;
            }
            if ("execute-reclaim-smoke".equals(command)) {
                State state = readState(profile);
                require(state.enabledRuleCount == 3 && state.reclaimUsesAmKill
                                && state.postUseReclaimUsesAmKill
                                && state.reclaimDelayMs == 30000
                                && state.postUseReclaimDelayMs == 30000
                                && state.shellSuSupportInstalled,
                        "Guarded SU reclaimers are not the active bounded rule set.");
                executeAction(profile, RECLAIM_SMOKE_ACTION);
                Thread.sleep(500L);
                printState(readState(profile));
                return;
            }
            if ("apply".equals(command)) {
                State before = readState(profile);
                try {
                    AddCallback callback = new AddCallback();
                    addIfNotExists(profile, callback, TELEMETRY_RULE_JSON);
                    require(callback.await(), "Rule-add callback timed out.");
                    require(callback.succeeded, "Rule validation failed with code " + callback.errorCode + ".");
                    if (!before.profileEnabled) {
                        setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, true);
                    }
                    if (!before.pushEnabled) {
                        setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, true);
                    }
                    enableRuleByName(profile, TELEMETRY_RULE_NAME);
                    State after = readState(profile);
                    require(after.ruleExists && after.ruleEnabled
                                    && after.profileEnabled && after.pushEnabled,
                            "Telemetry postcondition failed.");
                    printStateWithBefore(after, before);
                    return;
                } catch (Throwable failure) {
                    restoreGlobals(profile, before);
                    throw failure;
                }
            }
            if ("apply-reclaim".equals(command)) {
                State before = readState(profile);
                require(before.ruleExists && before.ruleEnabled,
                        "Transport telemetry must be enabled before reclamation.");
                try {
                    if (!before.shellSuSupportInstalled) {
                        setBoolean(profile, IPROFILE,
                                PROFILE_SET_SHELL_SU_INSTALLED, true);
                    }
                    AddCallback callback = new AddCallback();
                    addIfNotExists(profile, callback, RECLAIM_RULE_JSON);
                    require(callback.await(), "Reclaimer rule-add callback timed out.");
                    require(callback.succeeded,
                            "Reclaimer rule validation failed with code "
                                    + callback.errorCode + ".");
                    if (!before.profileEnabled) {
                        setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, true);
                    }
                    if (!before.pushEnabled) {
                        setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, true);
                    }
                    enableRuleByName(profile, RECLAIM_RULE_NAME);
                    State after = readState(profile);
                    require(after.reclaimRuleExists && after.reclaimRuleEnabled
                                    && after.reclaimDelayMs == 30000
                                    && after.profileEnabled && after.pushEnabled,
                            "Reclaimer postcondition failed.");
                    printStateWithBefore(after, before);
                    return;
                } catch (Throwable failure) {
                    restoreGlobals(profile, before);
                    throw failure;
                }
            }
            if ("apply-post-use-reclaim".equals(command)) {
                State before = readState(profile);
                require(before.ruleExists && before.ruleEnabled,
                        "Transport telemetry must be enabled before post-use reclamation.");
                try {
                    if (!before.shellSuSupportInstalled) {
                        setBoolean(profile, IPROFILE,
                                PROFILE_SET_SHELL_SU_INSTALLED, true);
                    }
                    AddCallback callback = new AddCallback();
                    addIfNotExists(profile, callback, POST_USE_RECLAIM_RULE_JSON);
                    require(callback.await(), "Rule-add callback timed out.");
                    require(callback.succeeded,
                            "Post-use reclaimer validation failed with code "
                                    + callback.errorCode + ".");
                    if (!before.profileEnabled) {
                        setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, true);
                    }
                    enableRuleByName(profile, POST_USE_RECLAIM_RULE_NAME);
                    State after = readState(profile);
                    require(after.postUseReclaimRuleExists
                                    && after.postUseReclaimRuleEnabled
                                    && after.postUseReclaimDelayMs == 30000
                                    && after.profileEnabled,
                            "Post-use reclaimer postcondition failed.");
                    printStateWithBefore(after, before);
                    return;
                } catch (Throwable failure) {
                    restoreGlobals(profile, before);
                    throw failure;
                }
            }
            if ("upgrade-reclaimers".equals(command)) {
                State before = readState(profile);
                require(before.ruleExists && before.ruleEnabled,
                        "Transport telemetry must be enabled before reclaimer upgrade.");
                require(before.reclaimRuleExists && before.postUseReclaimRuleExists,
                        "Both legacy reclaimers must exist before upgrade.");
                require(before.enabledRuleCount == 3,
                        "Reclaimer upgrade requires exactly three enabled Profile rules.");
                require(before.reclaimUsesAmKill == before.postUseReclaimUsesAmKill,
                        "Refusing a partial reclaimer upgrade.");
                if (before.reclaimUsesAmKill
                        && before.reclaimDelayMs == 30000
                        && before.postUseReclaimDelayMs == 30000) {
                    if (!before.shellSuSupportInstalled) {
                        setBoolean(profile, IPROFILE,
                                PROFILE_SET_SHELL_SU_INSTALLED, true);
                    }
                    enableRuleByName(profile, RECLAIM_RULE_NAME);
                    enableRuleByName(profile, POST_USE_RECLAIM_RULE_NAME);
                    printStateWithBefore(readState(profile), before);
                    return;
                }
                require(before.reclaimUsesUnprivilegedSh
                                == before.postUseReclaimUsesUnprivilegedSh,
                        "Refusing mismatched legacy reclaimer implementations.");
                String restoreReclaimJson;
                String restorePostUseJson;
                if (before.reclaimUsesAmKill) {
                    require(before.reclaimDelayMs == before.postUseReclaimDelayMs,
                            "Refusing mismatched reclaimer delays.");
                    require(before.reclaimDelayMs == 150000,
                            "Refusing an unreviewed SU reclaimer delay.");
                    restoreReclaimJson = RECLAIM_RULE_JSON_150_SECONDS;
                    restorePostUseJson = POST_USE_RECLAIM_RULE_JSON_150_SECONDS;
                } else {
                    restoreReclaimJson = before.reclaimUsesUnprivilegedSh
                            ? SH_RECLAIM_RULE_JSON : LEGACY_RECLAIM_RULE_JSON;
                    restorePostUseJson = before.postUseReclaimUsesUnprivilegedSh
                            ? SH_POST_USE_RECLAIM_RULE_JSON : LEGACY_POST_USE_RECLAIM_RULE_JSON;
                }
                try {
                    if (!before.shellSuSupportInstalled) {
                        setBoolean(profile, IPROFILE,
                                PROFILE_SET_SHELL_SU_INSTALLED, true);
                    }
                    replaceRule(profile, RECLAIM_RULE_NAME, RECLAIM_RULE_JSON, true);
                    replaceRule(profile, POST_USE_RECLAIM_RULE_NAME,
                            POST_USE_RECLAIM_RULE_JSON, true);
                    State after = readState(profile);
                    require(after.reclaimRuleExists && after.reclaimRuleEnabled
                                    && after.reclaimUsesAmKill
                                    && after.postUseReclaimRuleExists
                                    && after.postUseReclaimRuleEnabled
                                    && after.postUseReclaimUsesAmKill
                                    && after.reclaimDelayMs == 30000
                                    && after.postUseReclaimDelayMs == 30000
                                    && after.shellSuSupportInstalled,
                            "30-second reclaimer upgrade postcondition failed.");
                    printStateWithBefore(after, before);
                    return;
                } catch (Throwable failure) {
                    try {
                        replaceRule(profile, RECLAIM_RULE_NAME,
                                restoreReclaimJson, before.reclaimRuleEnabled);
                        replaceRule(profile, POST_USE_RECLAIM_RULE_NAME,
                                restorePostUseJson,
                                before.postUseReclaimRuleEnabled);
                        restoreGlobals(profile, before);
                    } catch (Throwable restoreFailure) {
                        failure.addSuppressed(restoreFailure);
                    }
                    throw failure;
                }
            }
            if ("remove".equals(command)) {
                if (args.length != 3) {
                    throw new IllegalArgumentException(
                            "remove requires previous profileEnabled and pushEnabled values.");
                }
                boolean restoreProfile = parseBoolean(args[1]);
                boolean restorePush = parseBoolean(args[2]);
                Rule rule = readRule(profile, TELEMETRY_RULE_NAME);
                if (rule != null) {
                    callNameBoolean(profile, PROFILE_DISABLE_RULE_BY_NAME,
                            TELEMETRY_RULE_NAME);
                    deleteRule(profile, rule.id);
                }
                setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, restorePush);
                setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, restoreProfile);
                State after = readState(profile);
                require(!after.ruleExists && after.profileEnabled == restoreProfile
                                && after.pushEnabled == restorePush,
                        "Telemetry removal postcondition failed.");
                printState(after);
                return;
            }
            if ("remove-reclaim".equals(command)) {
                if (args.length != 3) {
                    throw new IllegalArgumentException(
                            "remove-reclaim requires previous profileEnabled and pushEnabled values.");
                }
                boolean restoreProfile = parseBoolean(args[1]);
                boolean restorePush = parseBoolean(args[2]);
                Rule rule = readRule(profile, RECLAIM_RULE_NAME);
                if (rule != null) {
                    callNameBoolean(profile, PROFILE_DISABLE_RULE_BY_NAME,
                            RECLAIM_RULE_NAME);
                    deleteRule(profile, rule.id);
                }
                setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, restorePush);
                setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, restoreProfile);
                State after = readState(profile);
                require(!after.reclaimRuleExists
                                && after.profileEnabled == restoreProfile
                                && after.pushEnabled == restorePush,
                        "Reclaimer removal postcondition failed.");
                printState(after);
                return;
            }
            if ("remove-post-use-reclaim".equals(command)) {
                if (args.length != 3) {
                    throw new IllegalArgumentException(
                            "remove-post-use-reclaim requires previous profileEnabled and pushEnabled values.");
                }
                boolean restoreProfile = parseBoolean(args[1]);
                boolean restorePush = parseBoolean(args[2]);
                Rule rule = readRule(profile, POST_USE_RECLAIM_RULE_NAME);
                if (rule != null) {
                    callNameBoolean(profile, PROFILE_DISABLE_RULE_BY_NAME,
                            POST_USE_RECLAIM_RULE_NAME);
                    deleteRule(profile, rule.id);
                }
                setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, restorePush);
                setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, restoreProfile);
                State after = readState(profile);
                require(!after.postUseReclaimRuleExists
                                && after.profileEnabled == restoreProfile
                                && after.pushEnabled == restorePush,
                        "Post-use reclaimer removal postcondition failed.");
                printState(after);
                return;
            }
            throw new IllegalArgumentException("Unknown command: " + args[0]);
        } catch (Throwable failure) {
            System.err.println("ERROR=" + failure.getClass().getSimpleName() + ":" + safeMessage(failure));
            System.exit(1);
        }
    }

    private static State readState(IBinder profile) throws Exception {
        Rule telemetry = readRule(profile, TELEMETRY_RULE_NAME);
        Rule reclaim = readRule(profile, RECLAIM_RULE_NAME);
        Rule postUseReclaim = readRule(profile, POST_USE_RECLAIM_RULE_NAME);
        return new State(
                readBoolean(profile, IPROFILE, PROFILE_IS_ENABLED),
                readBoolean(profile, IPROFILE, PROFILE_IS_PUSH_ENABLED),
                telemetry != null,
                telemetry != null && telemetry.enabled,
                reclaim != null,
                reclaim != null && reclaim.enabled,
                reclaim != null && reclaim.ruleText.contains("su.exe"),
                reclaim != null && reclaim.ruleText.contains("sh.exe"),
                readDelayMs(reclaim),
                postUseReclaim != null,
                postUseReclaim != null && postUseReclaim.enabled,
                postUseReclaim != null && postUseReclaim.ruleText.contains("su.exe"),
                postUseReclaim != null && postUseReclaim.ruleText.contains("sh.exe"),
                readDelayMs(postUseReclaim),
                readEnabledRuleCount(profile),
                readBoolean(profile, IPROFILE, PROFILE_IS_SHELL_SU_INSTALLED));
    }

    private static int readDelayMs(Rule rule) {
        if (rule == null) return -1;
        Matcher matcher = Pattern.compile("\\\"delay\\\"\\s*:\\s*(\\d+)")
                .matcher(rule.ruleText);
        if (!matcher.find()) return -1;
        try {
            return Integer.parseInt(matcher.group(1));
        } catch (NumberFormatException ignored) {
            return -1;
        }
    }

    private static int readEnabledRuleCount(IBinder profile) throws Exception {
        Parcel reply = begin(profile, IPROFILE, PROFILE_GET_ENABLED_RULES);
        try { return reply.readInt(); } finally { reply.recycle(); }
    }

    private static Rule readRule(IBinder profile, String ruleName) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(IPROFILE);
            data.writeString(ruleName);
            require(profile.transact(PROFILE_GET_RULE_BY_NAME, data, reply, 0),
                    "getRuleByName was not handled.");
            reply.readException();
            if (reply.readInt() == 0) return null;
            int id = reply.readInt();
            reply.readString(); // name
            reply.readString(); // description
            String ruleText = reply.readString();
            reply.readString(); // author
            reply.readLong();
            boolean enabled = reply.readByte() != 0;
            reply.readInt(); // format
            reply.readInt(); // version
            reply.readInt(); // priority
            return new Rule(id, enabled, ruleText == null ? "" : ruleText);
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void addIfNotExists(
            IBinder profile, AddCallback callback, String ruleJson) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(IPROFILE);
            data.writeString("Codex");
            data.writeInt(1);
            data.writeString(ruleJson);
            data.writeStrongBinder(callback);
            data.writeInt(0);
            require(profile.transact(PROFILE_ADD_IF_NOT_EXISTS, data, reply, 0),
                    "addRuleIfNotExists was not handled.");
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void replaceRule(
            IBinder profile, String ruleName, String ruleJson, boolean enabled) throws Exception {
        Rule existing = readRule(profile, ruleName);
        if (existing != null) {
            callNameBoolean(profile, PROFILE_DISABLE_RULE_BY_NAME, ruleName);
            deleteRule(profile, existing.id);
        }
        AddCallback callback = new AddCallback();
        addIfNotExists(profile, callback, ruleJson);
        require(callback.await(), "Replacement rule-add callback timed out.");
        require(callback.succeeded,
                "Replacement rule validation failed with code " + callback.errorCode + ".");
        if (enabled) {
            enableRuleByName(profile, ruleName);
        } else {
            callNameBoolean(profile, PROFILE_DISABLE_RULE_BY_NAME, ruleName);
        }
    }

    private static void enableRuleByName(IBinder profile, String ruleName) throws Exception {
        callNameBoolean(profile, PROFILE_ENABLE_RULE_BY_NAME, ruleName);
    }

    private static boolean callNameBoolean(IBinder binder, int transaction, String name)
            throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(IPROFILE);
            data.writeString(name);
            require(binder.transact(transaction, data, reply, 0),
                    "Named rule transaction was not handled.");
            reply.readException();
            return reply.readInt() != 0;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void deleteRule(IBinder profile, int id) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(IPROFILE);
            data.writeInt(id);
            require(profile.transact(PROFILE_DELETE_RULE, data, reply, 0),
                    "deleteRule was not handled.");
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void executeAction(IBinder profile, String action) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(IPROFILE);
            data.writeString(action);
            require(profile.transact(PROFILE_EXECUTE_ACTION, data, reply, 0),
                    "executeAction was not handled.");
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void restoreGlobals(IBinder profile, State state) throws Exception {
        setBoolean(profile, IPROFILE, PROFILE_SET_SHELL_SU_INSTALLED,
                state.shellSuSupportInstalled);
        setBoolean(profile, IPROFILE, PROFILE_SET_PUSH_ENABLED, state.pushEnabled);
        setBoolean(profile, IPROFILE, PROFILE_SET_ENABLED, state.profileEnabled);
    }

    private static IBinder getService(String name) throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Method getService = serviceManager.getDeclaredMethod("getService", String.class);
        return (IBinder) getService.invoke(null, name);
    }

    private static Parcel begin(IBinder binder, String descriptor, int transaction)
            throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            require(binder.transact(transaction, data, reply, 0),
                    "Binder transaction was not handled: " + transaction);
            reply.readException();
            return reply;
        } finally {
            data.recycle();
        }
    }

    private static boolean readBoolean(IBinder binder, String descriptor, int transaction)
            throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try { return reply.readInt() != 0; } finally { reply.recycle(); }
    }

    private static String readString(IBinder binder, String descriptor, int transaction)
            throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try { return reply.readString(); } finally { reply.recycle(); }
    }

    private static IBinder readBinder(IBinder binder, String descriptor, int transaction)
            throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try { return reply.readStrongBinder(); } finally { reply.recycle(); }
    }

    private static void setBoolean(
            IBinder binder, String descriptor, int transaction, boolean value) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            data.writeInt(value ? 1 : 0);
            require(binder.transact(transaction, data, reply, 0),
                    "Boolean Binder transaction was not handled: " + transaction);
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static boolean parseBoolean(String value) {
        if ("true".equalsIgnoreCase(value)) return true;
        if ("false".equalsIgnoreCase(value)) return false;
        throw new IllegalArgumentException("Expected boolean.");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    private static String safeMessage(Throwable failure) {
        String message = failure.getMessage();
        return message == null ? "no-message" : message.replace('\n', ' ').replace('\r', ' ');
    }

    private static void printStateWithBefore(State state, State before) {
        System.out.println("profileEnabledBefore=" + before.profileEnabled);
        System.out.println("pushEnabledBefore=" + before.pushEnabled);
        printState(state);
    }

    private static void printState(State state) {
        System.out.println("profileEnabled=" + state.profileEnabled);
        System.out.println("pushEnabled=" + state.pushEnabled);
        System.out.println("ruleExists=" + state.ruleExists);
        System.out.println("ruleEnabled=" + state.ruleEnabled);
        System.out.println("reclaimRuleExists=" + state.reclaimRuleExists);
        System.out.println("reclaimRuleEnabled=" + state.reclaimRuleEnabled);
        System.out.println("reclaimUsesAmKill=" + state.reclaimUsesAmKill);
        System.out.println("reclaimUsesUnprivilegedSh="
                + state.reclaimUsesUnprivilegedSh);
        System.out.println("reclaimDelayMs=" + state.reclaimDelayMs);
        System.out.println("postUseReclaimRuleExists=" + state.postUseReclaimRuleExists);
        System.out.println("postUseReclaimRuleEnabled=" + state.postUseReclaimRuleEnabled);
        System.out.println("postUseReclaimUsesAmKill=" + state.postUseReclaimUsesAmKill);
        System.out.println("postUseReclaimUsesUnprivilegedSh="
                + state.postUseReclaimUsesUnprivilegedSh);
        System.out.println("postUseReclaimDelayMs=" + state.postUseReclaimDelayMs);
        System.out.println("shellSuSupportInstalled=" + state.shellSuSupportInstalled);
        System.out.println("enabledRuleCount=" + state.enabledRuleCount);
    }

    private static final class Rule {
        final int id;
        final boolean enabled;
        final String ruleText;
        Rule(int id, boolean enabled, String ruleText) {
            this.id = id;
            this.enabled = enabled;
            this.ruleText = ruleText;
        }
    }

    private static final class State {
        final boolean profileEnabled;
        final boolean pushEnabled;
        final boolean ruleExists;
        final boolean ruleEnabled;
        final boolean reclaimRuleExists;
        final boolean reclaimRuleEnabled;
        final boolean reclaimUsesAmKill;
        final boolean reclaimUsesUnprivilegedSh;
        final int reclaimDelayMs;
        final boolean postUseReclaimRuleExists;
        final boolean postUseReclaimRuleEnabled;
        final boolean postUseReclaimUsesAmKill;
        final boolean postUseReclaimUsesUnprivilegedSh;
        final int postUseReclaimDelayMs;
        final int enabledRuleCount;
        final boolean shellSuSupportInstalled;
        State(boolean profileEnabled, boolean pushEnabled, boolean ruleExists, boolean ruleEnabled,
              boolean reclaimRuleExists, boolean reclaimRuleEnabled,
              boolean reclaimUsesAmKill, boolean reclaimUsesUnprivilegedSh,
              int reclaimDelayMs,
              boolean postUseReclaimRuleExists, boolean postUseReclaimRuleEnabled,
              boolean postUseReclaimUsesAmKill,
              boolean postUseReclaimUsesUnprivilegedSh,
              int postUseReclaimDelayMs,
              int enabledRuleCount, boolean shellSuSupportInstalled) {
            this.profileEnabled = profileEnabled;
            this.pushEnabled = pushEnabled;
            this.ruleExists = ruleExists;
            this.ruleEnabled = ruleEnabled;
            this.reclaimRuleExists = reclaimRuleExists;
            this.reclaimRuleEnabled = reclaimRuleEnabled;
            this.reclaimUsesAmKill = reclaimUsesAmKill;
            this.reclaimUsesUnprivilegedSh = reclaimUsesUnprivilegedSh;
            this.reclaimDelayMs = reclaimDelayMs;
            this.postUseReclaimRuleExists = postUseReclaimRuleExists;
            this.postUseReclaimRuleEnabled = postUseReclaimRuleEnabled;
            this.postUseReclaimUsesAmKill = postUseReclaimUsesAmKill;
            this.postUseReclaimUsesUnprivilegedSh = postUseReclaimUsesUnprivilegedSh;
            this.postUseReclaimDelayMs = postUseReclaimDelayMs;
            this.enabledRuleCount = enabledRuleCount;
            this.shellSuSupportInstalled = shellSuSupportInstalled;
        }
    }

    private static final class AddCallback extends Binder {
        private final CountDownLatch latch = new CountDownLatch(1);
        volatile boolean succeeded;
        volatile int errorCode = Integer.MIN_VALUE;

        AddCallback() { attachInterface(null, ICALLBACK); }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            if (code == INTERFACE_TRANSACTION) {
                if (reply != null) reply.writeString(ICALLBACK);
                return true;
            }
            if (code == 1) {
                data.enforceInterface(ICALLBACK);
                succeeded = true;
                latch.countDown();
                return true;
            }
            if (code == 2) {
                data.enforceInterface(ICALLBACK);
                errorCode = data.readInt();
                data.readString(); // discard validation message; it can contain rule text
                succeeded = false;
                latch.countDown();
                return true;
            }
            try {
                return super.onTransact(code, data, reply, flags);
            } catch (Exception error) {
                return false;
            }
        }

        boolean await() throws InterruptedException {
            return latch.await(10L, TimeUnit.SECONDS);
        }
    }
}

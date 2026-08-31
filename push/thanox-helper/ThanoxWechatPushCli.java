package com.codex.wechatpush;

import android.os.IBinder;
import android.os.Parcel;

import java.lang.reflect.Method;
import java.util.Locale;

/**
 * Minimal raw-Binder client for the Thanox 8.6 APIs used by the WeChat push
 * repair workflow. It deliberately has no access to WeChat data, FCM tokens,
 * notification contents, contacts, or messages.
 */
public final class ThanoxWechatPushCli {
    private static final String SERVICE_NAME = "tv_input";
    private static final String ITHANOS = "github.tornaco.android.thanos.core.IThanos";
    private static final String IACTIVITY = "github.tornaco.android.thanos.core.app.IActivityManager";
    private static final String IPUSH = "github.tornaco.android.thanos.core.push.wechat.IPushDelegateManager";

    // AIDL method order is locked to Tornaco/Thanox tag v8.6 (debe3e32).
    private static final int ITHANOS_GET_ACTIVITY_MANAGER = 3;
    private static final int ITHANOS_WHO_ARE_YOU = 20;
    private static final int ITHANOS_GET_PUSH_DELEGATE_MANAGER = 29;

    private static final int ACTIVITY_SET_PKG_START_BLOCK = 24;
    private static final int ACTIVITY_IS_PKG_START_BLOCKED = 25;
    private static final int ACTIVITY_SET_PKG_BG_RESTRICTED = 32;
    private static final int ACTIVITY_IS_PKG_BG_RESTRICTED = 33;
    private static final int ACTIVITY_IS_SMART_STANDBY_ENABLED = 52;
    private static final int ACTIVITY_SET_SMART_STANDBY_ENABLED = 53;
    private static final int ACTIVITY_SET_PKG_SMART_STANDBY = 54;
    private static final int ACTIVITY_IS_PKG_SMART_STANDBY = 55;
    private static final int ACTIVITY_IS_SMART_STANDBY_STOP_SERVICE_ENABLED = 79;
    private static final int ACTIVITY_SET_SMART_STANDBY_STOP_SERVICE_ENABLED = 80;
    private static final int ACTIVITY_IS_SMART_STANDBY_INACTIVE_ENABLED = 81;
    private static final int ACTIVITY_SET_SMART_STANDBY_INACTIVE_ENABLED = 82;
    private static final int ACTIVITY_IS_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED = 83;
    private static final int ACTIVITY_SET_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED = 84;
    private static final int ACTIVITY_IS_SMART_STANDBY_BLOCK_RESTART_ENABLED = 85;
    private static final int ACTIVITY_SET_SMART_STANDBY_BLOCK_RESTART_ENABLED = 86;
    private static final int ACTIVITY_IS_SMART_STANDBY_BYPASS_VISIBLE_ENABLED = 129;
    private static final int ACTIVITY_SET_SMART_STANDBY_BYPASS_VISIBLE_ENABLED = 130;
    private static final int ACTIVITY_IS_SMART_STANDBY_UNBIND_SERVICE_ENABLED = 137;
    private static final int ACTIVITY_SET_SMART_STANDBY_UNBIND_SERVICE_ENABLED = 138;

    private static final int PUSH_WECHAT_ENABLED = 1;
    private static final int PUSH_SET_WECHAT_ENABLED = 2;
    private static final int PUSH_CONTENT_ENABLED = 5;
    private static final int PUSH_SET_CONTENT_ENABLED = 6;
    private static final int PUSH_START_APP_ENABLED = 10;
    private static final int PUSH_SET_START_APP_ENABLED = 11;
    private static final int PUSH_SKIP_IF_RUNNING_ENABLED = 12;
    private static final int PUSH_SET_SKIP_IF_RUNNING_ENABLED = 13;

    private static final String WECHAT = "com.tencent.mm";
    private static final int SYSTEM_USER = 0;

    private ThanoxWechatPushCli() {}

    public static void main(String[] args) {
        try {
            if (args.length == 0) {
                throw new IllegalArgumentException(
                        "Expected audit, apply-native, apply-native-guarded, apply-thanox, apply-thanox-restricted, "
                                + "apply-thanox-notify-only, or restore.");
            }
            IBinder root = getService(SERVICE_NAME);
            if (root == null) {
                throw new IllegalStateException("Thanox Binder service is unavailable.");
            }
            String descriptor = root.getInterfaceDescriptor();
            if (!ITHANOS.equals(descriptor)) {
                throw new IllegalStateException("Unexpected service descriptor: " + descriptor);
            }
            String identity = readString(root, ITHANOS, ITHANOS_WHO_ARE_YOU);
            if (identity == null || !identity.contains("Thanox")) {
                throw new IllegalStateException("Thanox identity check failed.");
            }

            IBinder activity = readBinder(root, ITHANOS, ITHANOS_GET_ACTIVITY_MANAGER);
            IBinder push = readBinder(root, ITHANOS, ITHANOS_GET_PUSH_DELEGATE_MANAGER);
            if (activity == null || push == null) {
                throw new IllegalStateException("Required Thanox sub-service is unavailable.");
            }

            String command = args[0].toLowerCase(Locale.ROOT);
            if ("audit".equals(command)) {
                printState(readState(activity, push));
                return;
            }

            State before = readState(activity, push);
            try {
                if ("apply-native".equals(command)) {
                    // Disable the proxy first, then keep native Firebase eligible to start.
                    setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_START_BLOCK, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_BG_RESTRICTED, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_SMART_STANDBY, true);
                    setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_ENABLED, true);
                    State after = readState(activity, push);
                    require(!after.delegateEnabled, "Delegate channel remained enabled.");
                    require(!after.startBlocked, "WeChat remained in start blocking.");
                    require(!after.backgroundRestricted, "WeChat remained background restricted.");
                    require(after.smartStandby, "Smart standby remained disabled.");
                    require(after.smartStandbyGlobal, "Global smart standby remained disabled.");
                    printState(after);
                    return;
                }
                if ("apply-native-guarded".equals(command)) {
                    // Keep native Firebase as the only notification handler. The reviewed
                    // Thanox build allows system FCM and user activity starts through its
                    // package start block, while rejecting WeChat's later service restarts.
                    if (before.delegateEnabled) {
                        setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, false);
                    }
                    if (before.backgroundRestricted) {
                        setPkgBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_PKG_BG_RESTRICTED, false);
                    }
                    if (!before.smartStandby) {
                        setPkgBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_PKG_SMART_STANDBY, true);
                    }
                    if (!before.smartStandbyGlobal) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_ENABLED, true);
                    }
                    if (!before.smartStandbyStopService) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_STOP_SERVICE_ENABLED, true);
                    }
                    if (before.smartStandbyUnbindService) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_UNBIND_SERVICE_ENABLED, false);
                    }
                    if (!before.smartStandbySetInactive) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_INACTIVE_ENABLED, true);
                    }
                    if (before.smartStandbyBypassNotification) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED, false);
                    }
                    if (!before.smartStandbyBypassVisible) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_BYPASS_VISIBLE_ENABLED, true);
                    }
                    if (!before.smartStandbyBlockServiceRestart) {
                        setBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_SMART_STANDBY_BLOCK_RESTART_ENABLED, true);
                    }
                    try {
                        if (!before.startBlocked) {
                            setPkgBoolean(activity, IACTIVITY,
                                    ACTIVITY_SET_PKG_START_BLOCK, true);
                        }
                    } catch (Throwable expectedRebind) {
                        // Verification below decides success.
                    }
                    IBinder[] recovered = awaitManagers();
                    root = recovered[0];
                    activity = recovered[1];
                    push = recovered[2];
                    State after = readState(activity, push);
                    require(!after.delegateEnabled && after.startBlocked
                                    && !after.backgroundRestricted
                                    && after.smartStandby && after.smartStandbyGlobal
                                    && after.smartStandbyStopService
                                    && !after.smartStandbyUnbindService
                                    && after.smartStandbySetInactive
                                    && !after.smartStandbyBypassNotification
                                    && after.smartStandbyBypassVisible
                                    && after.smartStandbyBlockServiceRestart,
                            "Guarded native FCM postcondition failed.");
                    printState(after);
                    return;
                }
                if ("apply-thanox".equals(command) || "apply-thanox-restricted".equals(command)) {
                    boolean restrictBackground = "apply-thanox-restricted".equals(command);
                    // Configure all dependent options before enabling the proxy channel last.
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_START_BLOCK, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_BG_RESTRICTED, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_SMART_STANDBY, true);
                    setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_CONTENT_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_SKIP_IF_RUNNING_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_START_APP_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, true);
                    if (restrictBackground) {
                        // Add the staged residency control only after the delegate is complete.
                        setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_BG_RESTRICTED, true);
                    }
                    State after = readState(activity, push);
                    require(after.delegateEnabled && after.showContent && after.startApp
                                    && after.skipIfRunning && !after.startBlocked
                                    && after.backgroundRestricted == restrictBackground
                                    && after.smartStandby
                                    && after.smartStandbyGlobal,
                            "Thanox delegate postcondition failed.");
                    printState(after);
                    return;
                }
                if ("apply-thanox-notify-only".equals(command)) {
                    // Intercept transport in system_server and never launch WeChat merely
                    // because a push arrived. A user launch or notification click remains
                    // eligible as user-initiated activity starts; background receivers and
                    // services are rejected by Thanox start blocking.
                    setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_START_BLOCK, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_BG_RESTRICTED, false);
                    setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_SMART_STANDBY, true);
                    setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_ENABLED, true);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_STOP_SERVICE_ENABLED, true);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_UNBIND_SERVICE_ENABLED, false);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_INACTIVE_ENABLED, true);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED, false);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_BYPASS_VISIBLE_ENABLED, true);
                    setBoolean(activity, IACTIVITY,
                            ACTIVITY_SET_SMART_STANDBY_BLOCK_RESTART_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_CONTENT_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_SKIP_IF_RUNNING_ENABLED, true);
                    setBoolean(push, IPUSH, PUSH_SET_START_APP_ENABLED, false);
                    setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, true);
                    try {
                        // Thanox 8.6 can rebuild its activity-manager sub-service when this
                        // flag changes. A dead reply is acceptable only if a fresh Binder
                        // session proves the requested state below.
                        setPkgBoolean(activity, IACTIVITY,
                                ACTIVITY_SET_PKG_START_BLOCK, true);
                    } catch (Throwable expectedRebind) {
                        // State is verified from a new Binder below; never treat this catch
                        // alone as success.
                        Thread.sleep(500L);
                    }
                    root = getService(SERVICE_NAME);
                    require(root != null && ITHANOS.equals(root.getInterfaceDescriptor()),
                            "Thanox Binder did not recover after start-block transition.");
                    activity = readBinder(root, ITHANOS, ITHANOS_GET_ACTIVITY_MANAGER);
                    push = readBinder(root, ITHANOS, ITHANOS_GET_PUSH_DELEGATE_MANAGER);
                    require(activity != null && push != null,
                            "Thanox sub-services did not recover after start-block transition.");
                    State after = readState(activity, push);
                    require(after.delegateEnabled && after.showContent
                                    && !after.startApp && after.skipIfRunning
                                    && after.startBlocked && !after.backgroundRestricted
                                    && after.smartStandby && after.smartStandbyGlobal
                                    && after.smartStandbyStopService
                                    && !after.smartStandbyUnbindService
                                    && after.smartStandbySetInactive
                                    && !after.smartStandbyBypassNotification
                                    && after.smartStandbyBypassVisible
                                    && after.smartStandbyBlockServiceRestart,
                            "Thanox notify-only postcondition failed.");
                    printState(after);
                    return;
                }
                if ("restore".equals(command)) {
                    if (args.length != 9 && args.length != 15) {
                        throw new IllegalArgumentException(
                                "restore requires eight or fourteen boolean values.");
                    }
                    State restore = new State(
                            parseBoolean(args[1]), parseBoolean(args[2]), parseBoolean(args[3]),
                            parseBoolean(args[4]), parseBoolean(args[5]), parseBoolean(args[6]),
                            parseBoolean(args[7]), parseBoolean(args[8]),
                            args.length == 15 ? parseBoolean(args[9])
                                    : before.smartStandbyStopService,
                            args.length == 15 ? parseBoolean(args[10])
                                    : before.smartStandbyUnbindService,
                            args.length == 15 ? parseBoolean(args[11])
                                    : before.smartStandbySetInactive,
                            args.length == 15 ? parseBoolean(args[12])
                                    : before.smartStandbyBypassNotification,
                            args.length == 15 ? parseBoolean(args[13])
                                    : before.smartStandbyBypassVisible,
                            args.length == 15 ? parseBoolean(args[14])
                                    : before.smartStandbyBlockServiceRestart);
                    restoreState(activity, push, restore);
                    State after = readState(activity, push);
                    require(after.equals(restore), "Restore verification failed.");
                    printState(after);
                    return;
                }
                throw new IllegalArgumentException("Unknown command: " + args[0]);
            } catch (Throwable applyFailure) {
                try {
                    IBinder[] recovered = awaitManagers();
                    activity = recovered[1];
                    push = recovered[2];
                    restoreState(activity, push, before);
                } catch (Throwable restoreFailure) {
                    applyFailure.addSuppressed(restoreFailure);
                }
                throw applyFailure;
            }
        } catch (Throwable failure) {
            System.err.println("ERROR=" + failure.getClass().getSimpleName() + ":" + safeMessage(failure));
            System.exit(1);
        }
    }

    private static State readState(IBinder activity, IBinder push) throws Exception {
        return new State(
                readBoolean(push, IPUSH, PUSH_WECHAT_ENABLED),
                readBoolean(push, IPUSH, PUSH_CONTENT_ENABLED),
                readBoolean(push, IPUSH, PUSH_START_APP_ENABLED),
                readBoolean(push, IPUSH, PUSH_SKIP_IF_RUNNING_ENABLED),
                readPkgBoolean(activity, IACTIVITY, ACTIVITY_IS_PKG_START_BLOCKED),
                readPkgBoolean(activity, IACTIVITY, ACTIVITY_IS_PKG_BG_RESTRICTED),
                readPkgBoolean(activity, IACTIVITY, ACTIVITY_IS_PKG_SMART_STANDBY),
                readBoolean(activity, IACTIVITY, ACTIVITY_IS_SMART_STANDBY_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_STOP_SERVICE_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_UNBIND_SERVICE_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_INACTIVE_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_BYPASS_VISIBLE_ENABLED),
                readBoolean(activity, IACTIVITY,
                        ACTIVITY_IS_SMART_STANDBY_BLOCK_RESTART_ENABLED));
    }

    private static void restoreState(IBinder activity, IBinder push, State state) throws Exception {
        setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, false);
        setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_START_BLOCK, state.startBlocked);
        setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_BG_RESTRICTED, state.backgroundRestricted);
        setPkgBoolean(activity, IACTIVITY, ACTIVITY_SET_PKG_SMART_STANDBY, state.smartStandby);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_ENABLED, state.smartStandbyGlobal);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_STOP_SERVICE_ENABLED,
                state.smartStandbyStopService);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_UNBIND_SERVICE_ENABLED,
                state.smartStandbyUnbindService);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_INACTIVE_ENABLED,
                state.smartStandbySetInactive);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_BYPASS_NOTIFICATION_ENABLED,
                state.smartStandbyBypassNotification);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_BYPASS_VISIBLE_ENABLED,
                state.smartStandbyBypassVisible);
        setBoolean(activity, IACTIVITY, ACTIVITY_SET_SMART_STANDBY_BLOCK_RESTART_ENABLED,
                state.smartStandbyBlockServiceRestart);
        setBoolean(push, IPUSH, PUSH_SET_CONTENT_ENABLED, state.showContent);
        setBoolean(push, IPUSH, PUSH_SET_SKIP_IF_RUNNING_ENABLED, state.skipIfRunning);
        setBoolean(push, IPUSH, PUSH_SET_START_APP_ENABLED, state.startApp);
        setBoolean(push, IPUSH, PUSH_SET_WECHAT_ENABLED, state.delegateEnabled);
    }

    private static IBinder getService(String name) throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Method getService = serviceManager.getDeclaredMethod("getService", String.class);
        return (IBinder) getService.invoke(null, name);
    }

    private static IBinder[] awaitManagers() throws Exception {
        Throwable lastFailure = null;
        for (int attempt = 0; attempt < 20; attempt++) {
            try {
                IBinder root = getService(SERVICE_NAME);
                if (root != null && root.isBinderAlive()
                        && ITHANOS.equals(root.getInterfaceDescriptor())) {
                    IBinder activity = readBinder(
                            root, ITHANOS, ITHANOS_GET_ACTIVITY_MANAGER);
                    IBinder push = readBinder(
                            root, ITHANOS, ITHANOS_GET_PUSH_DELEGATE_MANAGER);
                    if (activity != null && activity.isBinderAlive()
                            && push != null && push.isBinderAlive()) {
                        return new IBinder[]{root, activity, push};
                    }
                }
            } catch (Throwable failure) {
                lastFailure = failure;
            }
            Thread.sleep(250L);
        }
        IllegalStateException timeout = new IllegalStateException(
                "Thanox Binder did not recover within five seconds.");
        if (lastFailure != null) timeout.addSuppressed(lastFailure);
        throw timeout;
    }

    private static Parcel begin(IBinder binder, String descriptor, int transaction) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            if (!binder.transact(transaction, data, reply, 0)) {
                throw new IllegalStateException("Binder transaction was not handled: " + transaction);
            }
            reply.readException();
            return reply;
        } finally {
            data.recycle();
        }
    }

    private static boolean readBoolean(IBinder binder, String descriptor, int transaction) throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try {
            return reply.readInt() != 0;
        } finally {
            reply.recycle();
        }
    }

    private static String readString(IBinder binder, String descriptor, int transaction) throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try {
            return reply.readString();
        } finally {
            reply.recycle();
        }
    }

    private static IBinder readBinder(IBinder binder, String descriptor, int transaction) throws Exception {
        Parcel reply = begin(binder, descriptor, transaction);
        try {
            return reply.readStrongBinder();
        } finally {
            reply.recycle();
        }
    }

    private static boolean readPkgBoolean(IBinder binder, String descriptor, int transaction) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            writePkg(data);
            if (!binder.transact(transaction, data, reply, 0)) {
                throw new IllegalStateException("Binder transaction was not handled: " + transaction);
            }
            reply.readException();
            return reply.readInt() != 0;
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void setBoolean(IBinder binder, String descriptor, int transaction, boolean value) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            data.writeInt(value ? 1 : 0);
            if (!binder.transact(transaction, data, reply, 0)) {
                throw new IllegalStateException("Binder transaction was not handled: " + transaction);
            }
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void setPkgBoolean(IBinder binder, String descriptor, int transaction, boolean value) throws Exception {
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(descriptor);
            writePkg(data);
            data.writeInt(value ? 1 : 0);
            if (!binder.transact(transaction, data, reply, 0)) {
                throw new IllegalStateException("Binder transaction was not handled: " + transaction);
            }
            reply.readException();
        } finally {
            data.recycle();
            reply.recycle();
        }
    }

    private static void writePkg(Parcel data) {
        data.writeInt(1); // non-null typed object marker
        data.writeString(WECHAT);
        data.writeInt(SYSTEM_USER);
    }

    private static boolean parseBoolean(String value) {
        if ("true".equalsIgnoreCase(value)) return true;
        if ("false".equalsIgnoreCase(value)) return false;
        throw new IllegalArgumentException("Expected boolean but received: " + value);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    private static String safeMessage(Throwable failure) {
        String message = failure.getMessage();
        return message == null ? "no-message" : message.replace('\n', ' ').replace('\r', ' ');
    }

    private static void printState(State state) {
        System.out.println("delegateEnabled=" + state.delegateEnabled);
        System.out.println("showContent=" + state.showContent);
        System.out.println("startApp=" + state.startApp);
        System.out.println("skipIfRunning=" + state.skipIfRunning);
        System.out.println("startBlocked=" + state.startBlocked);
        System.out.println("backgroundRestricted=" + state.backgroundRestricted);
        System.out.println("smartStandby=" + state.smartStandby);
        System.out.println("smartStandbyGlobal=" + state.smartStandbyGlobal);
        System.out.println("smartStandbyStopService=" + state.smartStandbyStopService);
        System.out.println("smartStandbyUnbindService=" + state.smartStandbyUnbindService);
        System.out.println("smartStandbySetInactive=" + state.smartStandbySetInactive);
        System.out.println("smartStandbyBypassNotification="
                + state.smartStandbyBypassNotification);
        System.out.println("smartStandbyBypassVisible=" + state.smartStandbyBypassVisible);
        System.out.println("smartStandbyBlockServiceRestart="
                + state.smartStandbyBlockServiceRestart);
    }

    private static final class State {
        final boolean delegateEnabled;
        final boolean showContent;
        final boolean startApp;
        final boolean skipIfRunning;
        final boolean startBlocked;
        final boolean backgroundRestricted;
        final boolean smartStandby;
        final boolean smartStandbyGlobal;
        final boolean smartStandbyStopService;
        final boolean smartStandbyUnbindService;
        final boolean smartStandbySetInactive;
        final boolean smartStandbyBypassNotification;
        final boolean smartStandbyBypassVisible;
        final boolean smartStandbyBlockServiceRestart;

        State(boolean delegateEnabled, boolean showContent, boolean startApp,
              boolean skipIfRunning, boolean startBlocked,
              boolean backgroundRestricted, boolean smartStandby,
              boolean smartStandbyGlobal, boolean smartStandbyStopService,
              boolean smartStandbyUnbindService, boolean smartStandbySetInactive,
              boolean smartStandbyBypassNotification,
              boolean smartStandbyBypassVisible,
              boolean smartStandbyBlockServiceRestart) {
            this.delegateEnabled = delegateEnabled;
            this.showContent = showContent;
            this.startApp = startApp;
            this.skipIfRunning = skipIfRunning;
            this.startBlocked = startBlocked;
            this.backgroundRestricted = backgroundRestricted;
            this.smartStandby = smartStandby;
            this.smartStandbyGlobal = smartStandbyGlobal;
            this.smartStandbyStopService = smartStandbyStopService;
            this.smartStandbyUnbindService = smartStandbyUnbindService;
            this.smartStandbySetInactive = smartStandbySetInactive;
            this.smartStandbyBypassNotification = smartStandbyBypassNotification;
            this.smartStandbyBypassVisible = smartStandbyBypassVisible;
            this.smartStandbyBlockServiceRestart = smartStandbyBlockServiceRestart;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof State)) return false;
            State state = (State) other;
            return delegateEnabled == state.delegateEnabled
                    && showContent == state.showContent
                    && startApp == state.startApp
                    && skipIfRunning == state.skipIfRunning
                    && startBlocked == state.startBlocked
                    && backgroundRestricted == state.backgroundRestricted
                    && smartStandby == state.smartStandby
                    && smartStandbyGlobal == state.smartStandbyGlobal
                    && smartStandbyStopService == state.smartStandbyStopService
                    && smartStandbyUnbindService == state.smartStandbyUnbindService
                    && smartStandbySetInactive == state.smartStandbySetInactive
                    && smartStandbyBypassNotification
                            == state.smartStandbyBypassNotification
                    && smartStandbyBypassVisible == state.smartStandbyBypassVisible
                    && smartStandbyBlockServiceRestart
                            == state.smartStandbyBlockServiceRestart;
        }
    }
}

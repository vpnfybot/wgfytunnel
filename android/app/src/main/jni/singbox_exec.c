#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <dlfcn.h>
#include <android/log.h>

#define LOG_TAG "SingBoxNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

typedef struct nstring {
    void *chars;
    jsize len;
} nstring;

typedef struct proxylibcore__NewSingBoxInstance_return {
    int32_t r0;
    int32_t r1;
} proxylibcore__NewSingBoxInstance_return;

typedef nstring (*version_box_fn)(void);
typedef proxylibcore__NewSingBoxInstance_return (*new_singbox_instance_fn)(nstring config, int32_t localTransport);

#define GO_NULL_REFNUM 41

static void *gojni_handle = NULL;

static void throw_runtime_exception(JNIEnv *env, const char *message) {
    jclass exception_class = (*env)->FindClass(env, "java/lang/RuntimeException");
    if (exception_class != NULL) {
        (*env)->ThrowNew(env, exception_class, message);
    }
}

static void *load_gojni_symbol(JNIEnv *env, const char *name) {
    if (gojni_handle == NULL) {
        gojni_handle = dlopen("libgojni.so", RTLD_NOW | RTLD_GLOBAL);
        if (gojni_handle == NULL) {
            const char *error = dlerror();
            LOGE("dlopen libgojni.so failed: %s", error != NULL ? error : "unknown");
            throw_runtime_exception(env, error != NULL ? error : "Unable to load libgojni.so");
            return NULL;
        }
    }

    void *symbol = dlsym(gojni_handle, name);
    if (symbol == NULL) {
        const char *error = dlerror();
        LOGE("dlsym %s failed: %s", name, error != NULL ? error : "unknown");
        throw_runtime_exception(env, error != NULL ? error : "Unable to resolve symbol from libgojni.so");
        return NULL;
    }

    return symbol;
}

JNIEXPORT jint JNICALL
Java_com_example_wgfytunnel_LibcoreNativeShim_versionBoxLength(JNIEnv *env, jobject thiz) {
    (void)thiz;

    version_box_fn version_box = (version_box_fn)load_gojni_symbol(env, "proxylibcore__VersionBox");
    if (version_box == NULL) {
        return 0;
    }

    nstring version = version_box();
    jint length = version.len;
    free(version.chars);
    return length;
}

JNIEXPORT jint JNICALL
Java_com_example_wgfytunnel_LibcoreNativeShim_newSingBoxRef(JNIEnv *env, jobject thiz, jstring config) {
    (void)thiz;

    new_singbox_instance_fn new_singbox_instance =
        (new_singbox_instance_fn)load_gojni_symbol(env, "proxylibcore__NewSingBoxInstance");
    if (new_singbox_instance == NULL) {
        return 0;
    }

    const char *config_utf8 = (*env)->GetStringUTFChars(env, config, NULL);
    if (config_utf8 == NULL) {
        return 0;
    }

    size_t config_len = strlen(config_utf8);
    char *config_copy = NULL;
    if (config_len > 0) {
        config_copy = malloc(config_len);
        if (config_copy == NULL) {
            (*env)->ReleaseStringUTFChars(env, config, config_utf8);
            throw_runtime_exception(env, "malloc failed while copying sing-box config");
            return 0;
        }
        memcpy(config_copy, config_utf8, config_len);
    }

    (*env)->ReleaseStringUTFChars(env, config, config_utf8);

    nstring config_string = {
        .chars = config_copy,
        .len = (jsize)config_len,
    };

    proxylibcore__NewSingBoxInstance_return result =
        new_singbox_instance(config_string, GO_NULL_REFNUM);
    if (result.r1 != 0 && result.r1 != GO_NULL_REFNUM) {
        char error_message[128];
        snprintf(error_message, sizeof(error_message), "Libcore newSingBoxInstance failed with error ref %d", result.r1);
        throw_runtime_exception(env, error_message);
        return 0;
    }

    return (jint)result.r0;
}

JNIEXPORT jint JNICALL
Java_com_example_wgfytunnel_SingBoxManager_nativeExec(JNIEnv *env, jclass clazz, jstring binaryPath, jstring configPath, jstring workDir) {
    const char *binary = (*env)->GetStringUTFChars(env, binaryPath, NULL);
    const char *config = (*env)->GetStringUTFChars(env, configPath, NULL);
    const char *dir = (*env)->GetStringUTFChars(env, workDir, NULL);
    
    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        // Don't chdir to app dir - use tmp dir instead
        chdir("/data/local/tmp");
        
        char *const argv[] = {
            (char *)binary,
            "run",
            "-c", (char *)config,
            "-D", "/data/local/tmp",
            NULL
        };
        
        char *const envp[] = {
            "PATH=/system/bin:/system/xbin",
            NULL
        };
        
        execve(binary, argv, envp);
        
        // If execve returns, it failed
        LOGE("execve failed: %s", binary);
        _exit(127);
    } else if (pid > 0) {
        // Parent process
        LOGI("Started sing-box with PID %d", pid);
        (*env)->ReleaseStringUTFChars(env, binaryPath, binary);
        (*env)->ReleaseStringUTFChars(env, configPath, config);
        (*env)->ReleaseStringUTFChars(env, workDir, dir);
        return pid;
    } else {
        LOGE("fork failed");
        (*env)->ReleaseStringUTFChars(env, binaryPath, binary);
        (*env)->ReleaseStringUTFChars(env, configPath, config);
        (*env)->ReleaseStringUTFChars(env, workDir, dir);
        return -1;
    }
}

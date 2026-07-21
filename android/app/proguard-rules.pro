-assumenosideeffects class android.view.Window {
    public void setStatusBarColor(int);
    public void setNavigationBarColor(int);
    public void setNavigationBarDividerColor(int);
}

# Room creates generated database implementations by reflection. With R8 full
# mode the no-argument constructor can otherwise be removed, causing
# WorkManager's InitializationProvider to crash before the first Activity.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}

# ML Kit discovers Firebase component registrars from manifest metadata and
# instantiates them by reflection. Preserve their generated constructors so QR
# scanning continues to work in minified release builds.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

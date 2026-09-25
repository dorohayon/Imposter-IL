# Release shrinking (R8) rules for this app. Flutter adds this file to the
# release build by itself.

# Room creates each database from its generated <Name>_Impl class by
# reflection, through the no-argument constructor. R8 in full mode removed that
# constructor from WorkManager's WorkDatabase_Impl — WorkManager comes with the
# Google Mobile Ads SDK — and release builds crashed before the first frame
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# The same shape one class over: WorkManager builds each job's InputMerger by
# reflection through its no-argument constructor, and R8 removed those too, so
# every one-time job (the Mobile Ads SDK's offline ping buffering) failed.
-keepclassmembers class * extends androidx.work.InputMerger { public <init>(); }

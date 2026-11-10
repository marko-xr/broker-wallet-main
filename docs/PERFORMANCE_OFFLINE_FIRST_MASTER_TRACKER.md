# BROKER WALLET — PERFORMANCE + OFFLINE-FIRST MASTER TRACKER

**الإصدار:** 1.3 — 2026-10-31 (تصحيح توقف P1.1-a + تسليم وثيقة قابلة للإيداع؛ لا توجد قياسات جديدة)  
**طبيعة الملف:** سجل تنفيذ ومراجعة محمول، يُحدّث في كل handoff. ليس إثباتاً بأن الأعمال المستقبلية قد نُفذت.  
**المسار المقترح داخل المستودع:** `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` (المالك يطلب الآن تحديثه؛ يمكن لوكيل البرمجة إنشاؤه/تحديثه كتغيير توثيقي محصور بعد التحقق من الفرع وعدم الكتابة فوق عمل قائم بلا مراجعة).  
**الفرع المستهدف:** `perf/phase-1-startup-baseline` — أبلغ Claude بأنه تحقق منه من checkout الحي في 2026-10-31 15:42 +04؛ **دليل مقدم من المالك، ولم نتحقق منه مباشرة من Git هنا**. ZIP لا يحتوي `.git`.  
**المرحلة النشطة:** `P1 — Startup & Initial Screen Performance`؛ `P1.0` مراجعة مصدر فقط؛ `P1.1-a` **PAUSED BY PROCESS / NOT RUN** بعد تشديد التعليمات، وليس بسبب فشل تقني مثبت. `P1.1-b` **NOT APPROVED**. لا بناء ولا تثبيت ولا benchmark مثبت بهذه النسخة.  
**حالة المشروع:** PRE-PUBLIC-RELEASE؛ الأداء وOffline-First لا يغلقان بنود إطلاق المتاجر #8–#52.
**نسخة المستودع:** أُنشئ هذا الملف في المستودع بتاريخ 2026-10-31 19:06 +04 من النسخة المحمولة 1.3 دون تغيير محتواها السابق؛ أحدث حالة مُتحقَّق منها مباشرة من Git والجهاز في §7D–§7U-1 (آخر تحديث 2026-11-02، D-3 تنفيذ B + S2).

---

## 0) مهم — الحقيقة الحالية وحدود الإثبات

**المواد التي تمت مراجعتها لإعداد النسخة 1.0**

- أرشيف الكود المرفوع: `broker-wallet-main-perf-phase-1-startup-baseline.zip`؛ 1,565 مدخلاً؛ الجذر `broker-wallet-main-perf-phase-1-startup-baseline/`.
- `AGENTS.md`، `CLAUDE.md`، `docs/CURRENT_CHECKPOINT.md`، `docs/DECISIONS.md`، `lib/main.dart`، بعض خدمات الكاش و`pubspec.yaml` من الأرشيف.
- `BROKER_WALLET_MASTER_CONTEXT_PRO_PLUS_UPDATED_2026-10-31.md`؛ `BROKER_WALLET_FINAL_PRODUCTION_CHECKLIST_UPDATED_2026-10-31.md`؛ نظرة التطبيق المحدثة.
- خطة الأداء ذات خمس مراحل التي قدمها المالك (`FLUTTER PERFORMANCE OPTIMIZATION — COMPLETE 5-PHASE WORKFLOW`) ودليل إطلاق التطبيق 12 فيديو (خصوصاً Video 03 وVideo 12).
- SHA-256 للأرشيف المرفوع: `b5fdbacbaee26d55f8c98039cc924d2058a6313f6777a93afd2e5b58aa861d67` (لتمييز نسخة الأرشيف فقط، وليس commit).

**التحقق من Git:** لا يحتوي ZIP على `.git/`، لذلك لا يمكن منه إثبات الفرع الحالي ولا الـ HEAD ولا clean worktree ولا أصل الفرع ولا push أو merge. اسم ملف ZIP ليس شهادة Git. يلزم في مجلد العمل الأصلي تشغيل أوامر Git للقراءة فقط وتدوين نتائجها. كما أن نهاية `docs/CURRENT_CHECKPOINT.md` في ZIP تصف أعمال إزالة Firebase على `remove-firebase` ولا تتضمن قياسات P1 الجديدة؛ هذه ليست مشكلة بحد ذاتها، لكنها تمنع الادعاء أن مرحلة الأداء بدأت.

**آخر مرجع Git تاريخي، لا باعتباره HEAD الفرع الجديد:** `f686b80` في handoff الخاص بـ `remove-firebase` حسب تقارير المالك. يجب التحقق مما إذا كان فرع الأداء يبدأ منه، ولا تفترض ذلك تلقائياً.

### نتائج مستندة إلى المصدر المرفوع، ولا تعني وجود عطل مقاس

1. `main.dart` ينتظر `initializeAppServices()` قبل `runApp()`، كما ينتظر `FastUploadViewModel.initialize()` بمهلة 3 ثوانٍ قبل أول رسم.
2. ضمن تهيئة الخدمات: `Hive.initFlutter` و`SharedPreferences.getInstance` و`SupabaseBootstrapService.initialize`، ثم فتح Hive boxes: `pending_uploads`, `local_media`, `pending_profile_uploads`, `local_profile`، وتهيئة OfflineData/OfflineMedia/Count caches. بعضها قد يكون مطلوباً قبل العرض — لا تؤجل دون تتبع المستهلكين والأمان.
3. `SupabaseBootstrapService.initialize` يهيئ Supabase ثم يهيئ حالات Password Recovery وAccount Deletion ويبدأ Auth Callback Coordinator. ترتيب هذه العمليات مرتبط بعزل جلسات الاستعادة والحذف؛ **لا تنقلها إلى الخلفية بمجرد أنها await**.
4. `CountCacheService` يستخدم مفاتيح SharedPreferences ثابتة `cached_item_counts` و`counts_last_updated`؛ يلزم فحص مسارات القراءة/التبديل/المسح لتقييم العزل بين الحسابات، لكن هذا ليس تصريحاً بإصلاحه في P1.
5. `OfflineDataService` وFavorites/Hive ومخازن الوسائط موجودة. لا تستنتج منها وجود Offline-First CRUD كامل، ولا تستبدلها تلقائياً بمكتبة أخرى.
6. `pubspec.yaml` يحتوي Hive وSharedPreferences وSupabase، وتظل `cloud_firestore` و`firebase_core` مرتبطة ببوابات الحصص القديمة. لا تحذفها ضمن هذا المسار.

**أحدث فجوة إنتاجية معروفة من Master Context (موضوع منفصل):** Quotas/Entitlements ليست server-authoritative؛ حسابات أعمال Supabase قد تكون fail-open، وتوجد خمس نقاط استعمال `cloud_firestore` متبقية. إغلاقها يحتاج مشروعاً منفصلاً مع قرارات المالك بشأن الاشتراكات والحصص. **ممنوع** استعمال تحسين الأداء أو Offline لإزالة بوابات الحصص أو جعلها أكثر تساهلاً.

**اختبارات سابقة مذكورة في التقارير، ليست Baseline لهذا الفرع:** عند `f686b80` أبلغ المالك عن `flutter analyze --no-pub lib` بلا errors/warnings مع 84 infos، و1,888 pass / 2 historical fails في مجموعة موجهة. وسبق تسجيل 505 pass / 8 known fails في مرحلة إزالة أوسع، وبعض إخفاقات Map/Session القديمة. يلزم إعادة تثبيت baseline من checkout الحقيقي قبل مقارنة أي تغيير؛ لا تنسب هذه الأرقام للفرع الجديد أو تُصلح إخفاقاتها خارج النطاق.

---

## 1) عقد الأمان ومنع التأثير الجانبي — MANDATORY NON-REGRESSION CONTRACT

- **مصدر الحقيقة:** سلوك hosted/real-device الموثق > `docs/CURRENT_CHECKPOINT.md` في الفرع الحي > المصدر الحي > `AGENTS.md` / `CLAUDE.md` / `docs/DECISIONS.md` > Master Context > هذا tracker > الأرشيفات القديمة. عند التعارض سجّل التعارض وأوقف التعديل المعني.
- **المستودع:** اعمل في checkout الحالي فقط، على `perf/phase-1-startup-baseline` بعد التحقق؛ لا تنشئ worktree/branch/clone، ولا checkout، ولا stash، ولا reset، ولا clean، ولا commit، ولا push، ولا merge إلا بموافقة صريحة ومستقلة.
- **بداية آمنة:** `git branch --show-current`; `git rev-parse HEAD`; `git status --short`; `git diff --name-status`; `git diff --cached --name-status`؛ اعرض أي تعديلات موجودة قبل العمل. إذا الفرع غير مطابق أو تغييرات غير معروفة، STOP.
- **قفل النطاق:** P1 فقط. لا تنفذ P2–P5 ولا أي O-Phase من Offline-First في جلسة P1. لا SQLite/Drift، ولا Local Outbox، ولا Backend/SQL/RLS/Workers/Storage/Billing/Quota/SDK migration ضمن P1.
- **الواجهة:** لا حذف/إخفاء/إعادة تصميم للصفحات أو tabs أو routes أو الأدوات أو الإشعارات أو الأسطر المحلية أو الترجمة أو الألوان والخطوط. احفظ العربية/الإنجليزية وRTL/LTR وLight/Dark وMontserrat والـ custom bottom nav.
- **الهوية والأمان:** Supabase Auth و`AuthRepository.currentUserId` هما المرجع؛ لا تعطل أو تؤخر gates الخاصة بـ password recovery, account deletion, Single Active Device, session-superseded, OTP/phone UI, protected routing، أو media ownership. لا تجعل كاش الاشتراك/الصلاحيات مرجعاً أمنياً.
- **بقاء الوظائف:** حافظ على Requests/Offers/Owners/Offices/Brokers/Watchmen, Home, Search, Favorites, Smart Map, Quotations, Share, Toolkit, Phone tabs/OTP UI, private Cloudflare R2, Plan attachments, Toolkit Cloud Documents, Hive media queues وlegacy URL readers.
- **Firebase:** إزالة Firebase الجزئية السابقة ليست تصريحاً بإزالة `cloud_firestore`/`firebase_core` المتبقية أو native config؛ لا تغيّر quota bridge/Toolkit gates، ولا تُنشئ نجاحاً وهمياً أو bypass.
- **عدم تعديل الإنتاج:** لا Supabase SQL migration/RLS/RPC/data، لا Cloudflare Worker/R2 deployment، لا Firebase hosted deletion، لا تعديل أسرار أو خصائص billing/subscription أو إرسال SMS، ولا اختبارات destructive على حسابات حقيقية.
- **اكتشاف الأداء:** لا تنقل `await` من critical path حتى تُثبت أنه غير مرتبط بتأمين session/auth/recovery/deletion أو بجاهزية الشاشة. لا تضف fixed delays أو isolate أو caching SDK لتحسين وهمي. قِس أولاً.
- **اختبارات آمنة:** اقترح الأوامر قبل تشغيل أي build/profile/tool ينشئ generated files أو يتصل بخدمات حقيقية. لا تكتب إلى إنتاج، ولا تطلق requests كثيفة. استخدم test doubles عندما يلزم.
- **تنسيق:** تجنب `dart format` على مسارات عامة؛ امتثل لـ `CLAUDE.md` بشأن الملفات ذات تنسيق تاريخي وCRLF/LF وتغيير generated plugin registrants عند أوامر Flutter.
- **Graphify:** للبحث فقط وبحدود `AGENTS.md`؛ لا تستعمل edges الخاصة بـ Dart imports/calls كدليل معماري ولا تعيد توليده في هذا المسار.
- **صراحة الإثبات:** مصدر الكود فقط = `VERIFIED_SOURCE`، اختبار محلي = `CODE_PROVEN`، hosted = `VERIFIED_HOSTED`، device = `VERIFIED_REAL_DEVICE`؛ لا تدّعِ benchmark على جهاز لم يُستخدم.
- **قفل التغيير:** إذا كان الإصلاح المقترح يؤثر على نظام خارج النطاق، قدم تحليلاً وخياراً منفصلاً ولا تلمسه.

### تعريف نجاح P1 / Rollback

- لا تراجع في auth, recovery, deletion, active-session, routing, media/upload queues، أو بقية الوظائف ضمن الاختبارات المطبقة.
- تقرير diff محدود: لكل ملف مُعدل سبب مثبت، نتيجة اختبار، ومخاطر.
- نتائج قبل/بعد على **نفس الجهاز والإصدار وشروط الشبكة** إن أمكن؛ إن تعذرت فـ `PENDING_REAL_DEVICE`، ولا يوجد ادعاء بتحسن مقاس.
- خطة استعادة آمنة: عرض الـ diff والرجوع للتغييرات المحددة بموافقة المالك فقط؛ لا `git reset --hard` أو حذف تغييرات الآخرين.

---

## 2) تعريف الحالات والتحديثات

| الحالة | المعنى |
|---|---|
| `NOT STARTED` | لم تبدأ أدلة هذه المرحلة في الفرع الجديد. |
| `IN PROGRESS` | عمل مفحوص وقيد التنفيذ مع نطاق واضح. |
| `PARTIAL` | جزء أُثبت والباقي مع قيود. |
| `BLOCKED` | قرار/أداة/اختبار ضروري غير متاح. |
| `CODE_PROVEN` | تم إثبات النتائج من الكود والاختبارات المحددة فقط. |
| `PENDING_REAL_DEVICE` | مطلوب قبول Android/iOS الفعلي. |
| `VERIFIED_REAL_DEVICE` | قبول مثبت بجهاز وتفاصيل حالة محددة. |
| `DONE` | جميع شروط إغلاق المرحلة، بما فيها الجهاز حيث يفرض AGENTS.md، قد استوفيت. |

**قواعد تحديث Tracker في كل handoff:**

1. لا تمسح تاريخ المراحل أو تستبدل نتائج قديمة؛ أضف `Session Update` مؤرخاً مع اسم الفرع وHEAD قبل/بعد و`git status` والدليل.
2. عدّل حالة المرحلة النشطة والمقاييس والنواقص فقط بناء على أدلة من المستودع الجاري أو جهاز/خادم حقيقي.
3. لكل تغيير اذكر الملف والدالة، السبب والبديل، المقياس قبل/بعد، الاختبارات PASS/FAIL، الانحدارات والخطوة التالية.
4. اكتب `NOT RUN` بدلاً من افتراض نجاح اختبار لم يتم تشغيله، و`OWNER-REPORTED` حين يكون الدليل تقرير المالك فقط.
5. في نهاية كل تسليم: `NOW` خطوة واحدة محددة، `NEXT` خطوة بعد قبول المالك، و`STOP` ما لا يحق التنفيذ تلقائياً.
6. لا تنتقل إلى المرحلة التالية إلا بجملة موافقة واضحة من المالك. لا تغيّر checklist الإنتاج (#8–#52) لمجرد تقدم الأداء.
7. في بداية كل محادثة جديدة، ارفع آخر نسخة من هذا tracker + handoff السابق، واطلب قراءة المصدر/التعليمات الحية قبل الاستكمال.

---

## 3) مسار A — تحسين الأداء (الترتيب إلزامي؛ مرحلة واحدة فقط في كل مرة)

| ID | المرحلة | حالة 2026-10-31 | شروط الإغلاق المختصرة |
|---|---|---|---|
| `P1` | Startup & Initial Screen | `IN PROGRESS — P1.0 source review only; P1.1 not run` | baseline حقيقي؛ أسباب مثبتة؛ تغييرات محدودة؛ before/after؛ regression؛ real-device gate. |
| `P2` | Smart Local Caching & Background Refresh | `IN PROGRESS` — P2.1 (Requests offline، مشفّر) CODE_PROVEN، commit `0579b5b` (§7M)؛ P2.2 (Offers offline، مشفّر) CODE_PROVEN، commit `df1c45c` (§7O)؛ P2.3 (Owners offline، مشفّر) CODE_PROVEN، commit `10f2f15` (§7P)؛ P2.4a (Offices offline، مشفّر) CODE_PROVEN، commit `1abba8c` (§7Q)؛ P2.4b (Brokers offline، مشفّر) CODE_PROVEN، commit `978b2b9` (§7R)؛ P2.4c (Watchmen offline، مشفّر) CODE_PROVEN، commit `7ad15cc` (§7S) — آخر قوائم الكيانات؛ P2.5a (مراجعة أمان/نسخ احتياطي/استعادة) REVIEWED (§7T)؛ **D-1a + D-2 CODE_PROVEN، commit `dc4c95d` (§7T-1/§7T-2)**؛ D-3 (مصادقة الحمولة، الخيار B + S2) **CODE_PROVEN، غير مدمج (§7U-1)** | عرض آمن للكاش، تحديث صريح، عزل الحسابات، offline/refresh/empty/error tests. |
| `P3` | Supabase Queries & N+1 | `NOT STARTED` | عدّ الطلبات/latency؛ إصلاح ناتج عن قياس؛ RLS بلا تغيير؛ فروقات مثبتة. |
| `P4` | Pagination & Large Lists | `NOT STARTED` | قوائم كبيرة حقيقية، scrolling/memory/data transfer، مع صحة البحث والترتيب. |
| `P5` | Real-Device Performance Validation | `NOT STARTED` | Android+iOS بما يتيسر، cold/warm/reconnect, animations, memory, التقرير النهائي. |

### P1.0 — التحقق والـ Baseline (العمل الأول الوحيد الموافق عليه هنا: خطة قراءة فقط)

- [x] تأكيد الفرع `perf/phase-1-startup-baseline` وHEAD وworking tree مع الأمر وتوقيته؛ التأكد من base/ancestor عند الحاجة دون تعديل Git.
- [x] قراءة `AGENTS.md`, `CLAUDE.md`, `docs/CURRENT_CHECKPOINT.md`، ثم القرارات المتعلقة بـ auth/startup والأمان.
- [x] توثيق مسار startup الدقيق: entrypoint → initialized services → `runApp` → App/AuthViewModel/Router → first useful screen.
- [x] تصنيف كل await قبل الرسم إلى `SECURITY_CRITICAL` / `FIRST_SCREEN_REQUIRED` / `CANDIDATE_DEFER` / `UNKNOWN` مع دليل المستهلك والملف/السطر.
- [x] حصر أثر `Hive.initFlutter`, Preferences, Supabase init, boxes, Offline services, Count cache, FastUpload VM, Theme/Locale initialization وتدفقات الجلسات.
- [x] تحديد طريقة قياس cold/warm/first useful screen مع شروط الشبكة/الجهاز/البناء وإجراءات منع الإفشاء.
- [x] تجهيز baseline لاثنين من سيناريوهات الهوية: signed-out وsigned-in؛ وإضافة recovery/deletion/session-superseded كاختبارات حماية لا يجوز تخطيها.
- [x] جرد اختبارات بدء التشغيل والمصادقة القديمة وأي failure معروف من نفس الفرع قبل أي تغيير.
- [x] تقديم **خطة تغيير صغيرة** ببدائلها ومخاطرها وأوامر الاختبار، والتوقف لموافقة المالك قبل تعديل الكود.

**إغلاق P1.0 هنا يعني إغلاق قراءة المصدر/الخطة فقط، وليس إثبات تحسن الأداء أو نجاح اختبارات Flutter أو الأجهزة.**

### P1.1 — التنفيذ المحدود (غير معتمد بعد؛ ينفذ بعد قبول خطة P1.0)

- [ ] اختبارات/Instrumentation قياس صغيرة مع عدم تسجيل JWT/PII أو secrets.
- [ ] تنفيذ تعديل واحد مُثبت في المرة مع diff واضح وحدود محددة.
- [ ] اختبار auth/recovery/deletion/session gate والتهيئة والوسائط/المفضلة المجاورة.
- [ ] تحليل Flutter على الملفات المتأثرة، واختبارات موجهة، و`git diff --check` مع مقارنة baseline.
- [ ] إعادة القياس في ظروف مماثلة، وتحضير Device Acceptance Matrix.
- [ ] توثيق `CODE_PROVEN` أو `PARTIAL` دون `DONE` قبل device gate.

### بطاقة قياسات P1 (املأ من التنفيذ الفعلي فقط)

| Scenario | Build/device/network | Before (ms) | After (ms) | Samples | Evidence | Status |
|---|---|---:|---:|---:|---|---|
| Cold start signed-out → first usable screen | — | — | — | — | NOT RUN | PENDING |
| Cold start signed-in → first usable screen | — | — | — | — | NOT RUN | PENDING |
| Warm start → usable screen | — | — | — | — | NOT RUN | PENDING |
| Splash/blank-screen duration | — | — | — | — | NOT RUN | PENDING |
| Main-isolate busy frames / jank | — | — | — | — | NOT RUN | PENDING |
| Request count before first usable screen | — | — | — | — | NOT RUN | PENDING |

**منهجية القياس:** Profile/Release فقط لتقييم الأداء؛ قيم debug ليست دليلاً للأداء النهائي. ثبّت الجهاز/نسخة التطبيق/حالة cache/جلسة المستخدم/الشبكة، واذكر التباين وعدد التكرارات. إن لم تتوفر أجهزة فعلية اكتب خطة قياس قابلة للتكرار ولا تختلق أرقاماً.

### P2 — Smart Cache

- [ ] Inventory: Hive/SharedPreferences/OfflineData/OfflineMedia/Favorites/CountCache/Search/Map/Profile.
- [ ] اختبر stale/empty/error/offline/refresh مع فصل الحسابات وlogout.
- [ ] ثبّت سياسة TTL/invalidation لكل نوع بيانات وصلاحيات الوصول.
- [ ] لا تمنح صلاحيات اشتراك محلية ولا تفترض وصول الكاش إلى جميع سجلات الخادم.
- [ ] ارفع نتائج الأداء والأمان ثم توقف.

### P3 — Supabase Queries / N+1

- [ ] عدد الاستعلامات وlatency/bytes لكل شاشة أساسية قبل أي تغيير.
- [ ] كشف طلبات مرتبطة لكل صف والطلبات المتكررة دون افتراض وجود N+1.
- [ ] راجع joins/nested select/batching/RPC/indexes على ورق أولاً؛ لا migrations بلا موافقة.
- [ ] tests لصحة العلاقات والـ RLS ثم before/after.

### P4 — Large Lists

- [ ] Baseline للعدد الحقيقي والسحب والترتيب والبحث والتصفية والصور والذاكرة.
- [ ] Pagination/lazy loading فقط عند إثبات الفائدة؛ stable sort/cursors.
- [ ] تحقق عدم تكرار/سقوط عناصر عند التعديل، واهتزاز الصفحة عند العودة.

### P5 — Device & Final Report

- [ ] Android profile/release؛ iOS real device عندما يتاح.
- [ ] network offline/2G/slow/reconnect؛ warm/cold؛ account transitions.
- [ ] تقرير شامل: metrics, modified files, risk, regression, limitations, owner device sign-off.

---

## 4) مسار B — Offline-First الكامل (مستقبلي وغير مصرح بتنفيذه في P1)

**التبعيات:** تقييم وتصميم جزئي أثناء P2، والكتابة الدائمة ومزامنة CRUD لا تبدأ قبل موافقة معمارية مستقلة وفحص server constraints؛ لا تخلط بين قراءة كاش وبين كتابة معتمدة على الخادم. مسار الأداء P1–P5 يبقى متسلسلاً كما طلب المالك. يمكن تسجيل ملاحظات تصميم Offline على الهامش أثناء الفحص فقط دون تنفيذ مبكر.

| ID | العمل | الحالة | حد السلامة/القبول |
|---|---|---|---|
| `O0` | Architecture + privacy/threat model | `NOT STARTED` | مراجعة مصادر البيانات الحالية، الهوية، Single Active Device، retention/backup، قرار SQLite/Drift مقابل Hive. |
| `O1` | Offline read for Home/selected lists | `NOT STARTED` | Local-first reads بعد أول تحميل، stale timestamp، لا cross-account leak، لا شاشة بيضاء. |
| `O2` | Requests pilot: durable writes | `NOT STARTED` | ذرية local record + outbox، عمليات لا تضيع عند process death، حالة pending واضحة. |
| `O3` | Conflict/idempotency + delta sync | `NOT STARTED` | IDs ثابتة، server idempotency، optimistic concurrency/version، tombstones/deletes، auth/RLS. |
| `O4` | Expand business entities | `NOT STARTED` | Offers/Owners ثم Brokers/Offices/Watchmen/Search؛ الحفاظ على associated rows والـ media. |
| `O5` | Private media upload queue | `NOT STARTED` | R2 signed URLs وقت الرفع، تمكين retry/verification، عدم تغيير Worker دون موافقة. |
| `O6` | Background orchestration + observability | `NOT STARTED` | best-effort خلفية لا ضمان فوري عند غلق التطبيق، backoff، عدادات وآثار آمنة. |
| `O7` | Offline security and device acceptance | `NOT STARTED` | lost-response, restart, conflict, two accounts, session revoked, quota, storage-full, iOS/Android. |

### O0 — قرارات يجب تثبيتها قبل أي مكتبة جديدة

- `Local source of truth` للعرض فقط مقابل `Server source of authority` لملكية البيانات والاشتراك والحذف.
- ما الذي يُسمح بقراءته offline بعد token/session انتهاء الصلاحية؟ سياسة معتمدة من المالك؛ لا bypass.
- local encryption/Keychain/Keystore/backup retention/privacy disclosures.
- الواجهة الدائمة لتغييرات CRUD، ومعاملات atomic، وعدد العمليات المعلقة وحجم الوسائط.
- API عقد idempotency/versioning والكتابة transactional لروابط العلاقات، قبل إعادة المحاولة.
- conflict policy لا تستبدل أحدث نسخة بصمت؛ لا تعتمد على ساعة الجهاز وحدها.
- logout/delete-account/account switching وما يحدث للمسودات المعلقة؛ لا حذف صامت.
- policy للصلاحيات والحصص offline: لا ترفع صلاحيات client cache على الخادم.
- قرار local-store toolkit/cloud documents منفصل عن CRUD والميديا العقارية.

### Offline-First Test Matrix (مستقبلية)

| Scenario | Expected | Status |
|---|---|---|
| سبق تحميل Offers ثم فصل الشبكة وإعادة فتح التطبيق | قائمة محلية آمنة مع معلومات عن قدم البيانات | NOT RUN |
| حفظ Request بدون شبكة ثم force close/relaunch | الملاحظة وoutbox باقِيان | NOT RUN |
| نجاح الخادم ثم ضياع الاستجابة | لا duplicate بعد retry | NOT RUN |
| تعديل متزامن لنفس السجل من نسختين | كشف conflict ومنع overwrite صامت | NOT RUN |
| Logout/Login مستخدم آخر على نفس الهاتف | لا تسريب محتوى أو أعداد الحساب السابق | NOT RUN |
| سحب صلاحية جلسة Single Active Device | لا sync أو عمليات privileged قبل التحقق | NOT RUN |
| انتهاء اشتراك/حصة أثناء Offline | الخادم يرفض الحفظ غير المصرح به بأمان | NOT RUN |
| إعادة رفع الصور/Plan بعد reconnect | صلاحيات صالحة وprivate R2 فقط | NOT RUN |
| مساحة تخزين ممتلئة/بيانات محلية تالفة | error واضح دون اعتبار العملية محفوظة | NOT RUN |

---

## 5) سجل المخاطر والقرارات المحظورة

| ID | الخطر | الاحتمال/الأثر | ضبطه | الحالة |
|---|---|---|---|---|
| R-01 | تأخير فحص Recovery/Delete/Single Session لأجل السرعة | مرتفع الأثر | تتبع الاعتمادات؛ لا تأجيل دون اختبار سلبي | OPEN |
| R-02 | كاش حساب يظهر لحساب آخر — تقرير P1.0 يشير تحديداً إلى مفاتيح Home CountCache العامة وعدم مسحها عند logout | مرتفع الأثر/خصوصية | Namespace + lifecycle + اختبار حسابين؛ فصل الإصلاح في قرار أمني معتمد، وليس تجاوز خطة P1 | **CODE_PROVEN** — commit `8f1ba82`؛ فحص الجهاز **DEFERRED BY OWNER** (§7L، §7N). كان: FIXED IN SOURCE (§7K)؛ وقبله: OPEN — SOURCE FINDING, UNTESTED ON DEVICE |
| R-03 | فقدان أو تكرار عملية offline | مرتفع الأثر | durable outbox, idempotency, transactional backend | FUTURE |
| R-04 | تغييرات التنسيق تولّد diff ضخم | متوسط | ملفات جديدة فقط؛ لا format شامل | OPEN |
| R-05 | تغييرات Flutter generated registrants | متوسط | سجل واكشف diff قبل/بعد، لا تمسح يدوياً | OPEN |
| R-06 | quotas fail-open + remaining Firebase | إنتاجي مرتفع | مسار مستقل approved billing/entitlements، لا touch هنا | OPEN / OUT-OF-SCOPE |
| R-07 | الخلط بين تحسين الأداء وإغلاق release checklist | متوسط | إبلاغ مستقل، #8–#52 كما هي | OPEN |
| R-08 | أرشيف دون `.git` ثم نسب baseline إلى commit غير مثبت | متوسط | Git read-only على Windows checkout الحقيقي | OPEN |
| R-09 | تثبيت Profile بنفس package ID قد يستبدل نسخة يومية أو يُحدث ضرراً بالبيانات المحلية | حرج إن وجدت بيانات لا يمكن استعادتها | Pre-flight read-only، جهاز اختبار، موافقة منفصلة على install، STOP عند signature mismatch، لا uninstall/pm clear | OPEN — NEW IN v1.2 |

---

## 6) قالب Session Update — يُنسخ ويُملأ في نهاية كل جلسة

```text
### SESSION UPDATE — YYYY-MM-DD HH:MM [Asia/Dubai]
- Phase / checkpoint:
- Work approved by owner (exact scope):
- Repository path / branch:
- HEAD before / after:
- Git status before / after (tracked, untracked, staged):
- Evidence category (VERIFIED_SOURCE / CODE_PROVEN / VERIFIED_REAL_DEVICE / ...):
- Baseline (device/build/network/samples, metrics):
- Confirmed finding + source file:line / root cause:
- Files changed (why each is necessary):
- Before/after numbers and method:
- Tests (commands + passed/failed/not-run + existing vs new failures):
- Security/auth/routing/locale/theme/business regression checks:
- Hosted changes: NONE unless separately approved, with proof:
- New risks / known limitations / approvals needed:
- Tracker status changes:
- NOW:
- NEXT (after explicit owner approval):
- STOP (out-of-scope actions):
```

## 7) أول تحديث / Handoff عند إنشاء الملف

### SESSION UPDATE — 2026-10-31 — TRACKER INITIALIZED (DOCUMENTATION ONLY)

- Phase: `P1.0`; status `NOT STARTED`.
- Owner-reported branch: `perf/phase-1-startup-baseline`.
- Inspected archive: ZIP source snapshot, SHA-256 as above; no `.git` present.
- HEAD of the new branch: `UNVERIFIED`; earlier reported `f686b80` belongs to `remove-firebase` history.
- Current checkpoint tail in ZIP: `Firebase removal - last dead-code cleanup` on `remove-firebase`; no measured Phase 1 results.
- Source investigation only: startup awaits identified; latency and correctness impact **not measured**; no code changes, builds, device tests, database writes, commits or deployments performed by the tracker preparation.
- `NOW`: افتح Claude Code من checkout الحقيقي على فرع الأداء، اختر **Plan Mode + Opus high effort + Fast OFF** إن كانت الإعدادات متاحة، وأرسل ملف P1 prompt المرفق. سجّل Git state والتحليل في هذا الملف فقط بعد الموافقة على كتابة التقرير.
- `NEXT`: بعد مراجعة خطة P1.0 والموافقة الصريحة، نفذ Phase 1 فقط في **Ask permissions / Default mode** مع اختبارات وقياسات موجهة.
- `STOP`: لا تنفيذ P2–P5 أو O0–O7؛ لا SQL/Worker/R2/Firebase/quotas/billing أو إعادة تصميم أو commit/push/merge/deploy.

---

## 7A) تحديث P1.0 من تقرير Claude المرفق — 2026-10-31 15:42 +04

**مصدر هذا التحديث:** النص الكامل لتقرير `P1.0 — Read-only Startup Investigation & Baseline Plan (Broker Wallet)` الذي شاركه المالك. إن صدرت معلومات أحدث من checkout الحي أو الاختبارات الفعلية، تُقدَّم عليها. لا يدل حفظ هذا التحديث هنا على كتابة أي ملف في المستودع المحلي للمستخدم.

### SESSION UPDATE — 2026-10-31 15:42 [Asia/Dubai] — P1.0 SOURCE REVIEW

- **Checkpoint:** `P1.0` = **COMPLETE (read-only source investigation; owner-supplied Claude report)**. `P1` = `IN PROGRESS`. `P1.1-a`/`P1.1-b` = `NOT RUN`, بحاجة موافقة مستقلة.
- **Git:** أبلغ Claude بأن الفرع `perf/phase-1-startup-baseline` نظيف، HEAD = `f686b80cce32de929688180491fa8c61f4bcba91`، upstream = `origin/perf/phase-1-startup-baseline` بلا ahead/behind. لم يُنشَأ commit جديد للأداء. الـ stashes القديمة لم تُمس.
- **Git history warning:** فرع الأداء يبدأ من سلسلة `remove-firebase` عند `f686b80`، ووفق تقرير Claude يقع بـ 93 commit فوق `main` (`c29115e`). **لا تدمجه في main تلقائياً؛ راجع نطاق الدمج وتاريخه لاحقاً بصورة مستقلة.**
- **Evidence:** `VERIFIED_SOURCE` كما صنّفه Claude؛ هذا تحديث ثانوي بناءً على تقرير المالك، **وليس تحققاً مباشراً من checkout على جهازه**.
- **No measured performance:** Startup times, Home usable-time, network count/runtime, cold/warm latency, token-refresh latency, Hive/ARB overhead جميعها **NOT MEASURED**. لا builds ولا tests ولا device benchmarks أُجريت في P1.0.
- **Key critical path:** المستخدم المسجّل يحتاج RPC `is_current_app_session` قبل فتح Home؛ لا تأجيله أو bypass أو fail-open. المستخدم غير المسجل يمكنه الوصول إلى Welcome دون شبكة حسب مسار المصدر.
- **Pre-runApp work:** Supabase secure initialization + recovery/deletion state priming + initial auth link classification + Hive boxes، بعضها مرتبط بحذف البيانات المحلية وأمان Recovery. **لا تؤجَّل هذه العمليات بناء على حدس.**
- **P1 candidate observations:** بدء التحقق من الجلسة يحدث بعد التهيئة المحلية؛ Hive boxes تفتح متتابعة؛ ARB loading قد يؤخر أول إطار؛ كلها **candidate costs — not yet measured**.
- **F-5:** تقرير Claude يرجّح تكرار طلبات أعداد Home بسبب أحداث auth المعاد تشغيلها (حد أدنى متوقع 14 بدلاً من 7). **هذا استنتاج من المصدر؛ يحتاج إثبات بعدّ الطلبات الفعلية، وليس benchmark قائماً.** سجّل للمتابعة في P3 ما لم يثبت أثر مباشر على P1.
- **F-6 / R-02:** `cached_item_counts` غير معزول بحسب الحساب في التقرير، واحتمال عرض أعداد الحساب A عند دخول B يحتاج اختبار خصوصية موجه. **ملاحظة أمنية عالية الأولوية؛ لا تُمكن الكاش الجديد أو التوسع في P2 قبل حسمها.** أي إصلاح مستقل بموافقة واضحة واختبارات logout/account-switch.
- **F-7:** التحقق من RPC دون مهلة تطبيقية معلنة في التقرير؛ أي تعديل timeout يجب أن يكون **fail-closed to Retry**، لا تخويل تلقائي؛ خارج P1.0.
- **F-8:** مسار فشل تهيئة Supabase قد يؤثر على ViewModel مبكر؛ **UNKNOWN RUNTIME**، يحتاج اختبار فشل منفصل، لا تعديل بلا إعادة إنتاج.
- **Native Firebase:** لا تلمس `cloud_firestore`/`firebase_core` أو التهيئة الأصلية؛ تبعيات حصص Toolkit لم تُستبدل بعد.
- **Changes/tests/hosted:** لا تغييرات مصدرية في P1.0، لا اختبارات/بناء، لا تغييرات Supabase/Cloudflare/Firebase، ولا merge/push/commit.

### NEXT — موافقة منفصلة على P1.1-a فقط (NO-SOURCE-EDIT BASELINE)

1. ابدأ بقياسات **دون تعديل المصدر** على جهاز Samsung نفسه، باستخدام profile build، مع التحقق من package/activity وGit status قبل وبعد أوامر Flutter؛ سجل الجهاز ونسخة Flutter وبناء التطبيق والشبكة وحالة حساب الاختبار.
2. افصل المقاييس: `first frame` (Splash) ≠ `first useful screen` (Welcome/Home)، وأرقام `am start -W` لا تساوي مدة Home؛ استخدم فيديو/DevTools وأفصح عن الدقة والقيود.
3. سيناريوهات signed-out cold، signed-in cold token-valid، warm start، offline signed-in → Retry دون Home. لا تفترض صلاحية JWT/expiry بناء على عمر زمني فقط؛ تحقق بطريقة آمنة بلا كشف رموز.
4. **حماية الخصوصية:** لا سجلات شبكة حساسة أو JWT أو signed R2 URLs أو لقطات شاشة بحسابات حقيقية؛ لا تغييرات بيانات اختبار إنتاجية؛ حساب اختبار خاص مع بيانات غير حساسة.
5. بعد القياسات قدّم تقرير الأرقام الخام والوسيط وP90 وعدد التكرارات والمشاكل. **توقف هنا**؛ `P1.1-b instrumentation` قرار آخر بعد مراجعة الأرقام. يمنع `Accept and use auto mode` أو تشغيل التعديلات الآلية.
6. أوامر `flutter run/build` قد تغيّر ملفات generated registrants، لذلك سجّل `git status` وأظهر الفرق دون stash/reset/clean أو إدخاله في commit. لا تقل إن هذا قياس «بلا آثار ملفات»، بل **بلا تعديل مقصود للمصدر**.

**NOW:** مراجعة خطة Claude على الشاشة ثم طلب فصل P1.1-a عن P1.1-b؛ لا تبدأ أي تحسين أو instrumentation في الموافقة الحالية.  
**NEXT:** بعد موافقة المالك الصريحة، قياس P1.1-a على الهاتف وتحديث هذا الملف بنتائج واقعية.  
**STOP:** no auto mode; no P1.1-b before its approval; no P1.2, P2–P5, O0–O7, backend/SQL/Firebase/quota changes, commits, pushes, merges, deployments, or deletions.

---

## 7B) مراجعة خطة Claude P1.1-a — 2026-10-31 18:46 +04 — PLAN REVIEW ONLY

**دليل جديد:** خطة Claude التي شاركها المالك بعنوان `P1.1-a — قياس الأداء الفعلي على Samsung (Profile Mode) — خطة فقط` وصورة شاشة `Claude proposed a plan`. التقرير يذكر أن آخر فحص Android للـ checkout أثبت: `applicationId=com.example.broker_wallet`، Launcher Activity `.MainActivity`، ولا يوجد `applicationIdSuffix` منفصل لـ Profile. هذه حقائق **CLAUDE-REPORTED SOURCE**؛ لم نعِد فحص Git الحي من هذه البيئة. لا تتضمن هذه المواد أي benchmark أو تشغيل build/profile أو تثبيت.

### حالة التنفيذ

- **P1.0:** `COMPLETE — SOURCE REVIEW ONLY` بناءً على تقرير Claude السابق.
- **P1.1-a:** `PLANNED / REVIEWED / REVISION REQUESTED / NOT RUN`. لا موافقة على البناء أو التثبيت أو القياس بعد.
- **P1.1-b:** `NOT APPROVED / NOT RUN`؛ يبقى instrumentation منفصلاً.
- **Git:** لا دليل جديد على تغيّر HEAD؛ آخر SHA أبلغ به Claude `f686b80cce32de929688180491fa8c61f4bcba91` والفرع `perf/phase-1-startup-baseline`؛ يجب إعادة التحقق عند التنفيذ. لا تعديل Repository تم بهذا التحديث المحمول.
- **Metrics:** جميع TTFF/TTUS/Displayed/jank/query counts ما زالت `NOT MEASURED`.

### خطر تشغيل حرج جديد — R-09: Profile install على نفس package ID

1. `flutter build apk --profile --no-pub` ينشئ artifact له **نفس `applicationId`** للتطبيق المثبت على Samsung. التثبيت قد **يستبدل التطبيق** إن تطابق التوقيع؛ ويمكن أن يفشل بسبب التوقيع إن اختلف. `adb install -r` دون uninstall أو `pm clear` يقلل خطر حذف البيانات، لكنه **لا يضمن** الحماية من مشاكل مخطط التخزين/المحتوى أو تغيير الحالة بسبب تشغيل التطبيق.
2. لا تنفيذ على جهاز أساسي يحمل بيانات محلية لا يمكن استعادتها. **الأفضل جهاز Android مخصص للاختبار وبيانات وحساب اختبار غير حساس**؛ خلاف ذلك STOP قبل أي build/install حتى قرار حماية/استعادة موثق من المالك.
3. قبل `flutter run --profile` و`flutter run --trace-startup` تحقق من أنهما لن يؤديا إلى مسار uninstall/reinstall غير مقصود على هذا الجهاز؛ عند تعارض توقيع أو مطالبة بإلغاء التثبيت `STOP` فوراً.
4. لا استخدام `adb uninstall` أو `pm clear` أو مسح Hive/Toolkit/ملفات user، أو تغيير signing/Application ID ضمن هذا الـ checkpoint.

### تصحيحات قبل اعتماد الخطة

- **Step gate:** المرحلة التالية هي `P1.1-a Pre-flight` **قراءة فقط**: branch/HEAD/status، معلومات APK المثبت والتوقيع/الحزمة وفق الأدوات المتاحة، إصدار الجهاز، وملفات البيانات الحساسة المحتملة **دون عرض البيانات نفسها**. اجعل **build/install** موافقة مستقلة بعد تقرير الـ Pre-flight، لا جزءاً ضمنياً من Accept.
- **Terminology:** `timeToFrameworkInitMicros` لا ينبغي تعريفه مساويًا لمدة كل العمليات قبل `runApp()`؛ يسجل حدث تهيئة Flutter framework. توقيت كل `await` يحتاج instrumentation مستقلة إذا لزم.
- **TTUS:** قياس screenrecord `--bugreport` مع logcat يكون تجريبياً أولاً، مع توضيح مصدر timebase، دقة الإطارات ووجود احتمال فقد/تأخير frames؛ إذا لم يظهر Home/Retry قبل مهلة الفيديو تسجل `TIMEOUT/CENSORED` بدلاً من رقم مفترض. `am start -W` ليس زمن Home.
- **Windows commands:** أوامر `%USERPROFILE%` تخص `cmd.exe`، وقد تختلف في PowerShell؛ اختر shell واحداً وأنشئ مجلد النتائج مسبقاً بأمر غير مدمّر. تجنب `adb logcat -c` غير الضروري لمسح سجل الجهاز، ولا تحذف تسجيل الجهاز قبل التحقق من نجاح نسخه.
- **Auth tests:** تأجيل logout/login والتجارب المتعلقة بانتهاء JWT وAirplane mode إلى جلسة مستقلة في حساب اختبار، لأنها قد تغيّر الصف المعتمد لجلسة Single Active Device على Supabase، وقد تزيح جلسة جهاز آخر.
- **Network observations:** أدوات DevTools لا تثبت بالضرورة جميع الطلبات الأصلية والنظامية؛ اذكر التغطية وحدود القياس، ولا تستنتج عدد استعلامات Home من قراءة المصدر وحدها.
- **Sampling:** اختبار سريع صغير لصحة خطوات القياس أولاً، ثم الاعتماد على تكرارات كافية للمقارنة؛ لا تغيّر شروط الشبكة/الجهاز بين العينات دون توثيق.
- **No changes:** لا تعديل App code أو SDKs أو hosts/keys/SQL/RLS/Firebase/Cloudflare أو quota/billing، ولا commit/push/merge/deploy. الـ stashes تبقى كما هي.

### NOW / NEXT / STOP

- **NOW:** المالك يضغط `Revise...` ويطلب `P1.1-a-preflight only` للتحقق من بيئة القياس والجهاز والحزمة والتوقيع دون تنفيذ build/install، مع إعداد تعليمات Windows سليمة.
- **NEXT:** بعد مراجعة Pre-flight وموافقة مستقلة على سلامة جهاز الاختبار، ينفذ المالك قياسات P1.1-a ويشارك جداول النتائج دون بيانات شخصية أو Tokens؛ بعدها قرار مستقل حول P1.1-b.
- **STOP:** لا `Accept and use auto mode`، لا تثبيت Profile على هاتف به بيانات غير قابلة للاستعادة، لا uninstall/pm clear، لا logout/login أو تغيير جلسة الحساب بلا موافقة، ولا P1.1-b أو تحسين كود قبل أرقام قياس.

---


## 7C) تصحيح Workflow — 2026-10-31 — Claude paused P1.1-a (owner-shared report)

**مصدر هذا الملحق:** رسالة Claude التي نقلها صاحب المشروع في المحادثة. نحن لا نملك دليلاً جديداً من جهاز Samsung أو Git الفعلي هنا. لا توجد قياسات فعلية أو تغييرات مصدرية أثبتها هذا التقرير.

### الحالة الفعلية حسب رسالة Claude

- **P1.0:** `COMPLETE — SOURCE REVIEW ONLY`؛ لم تنتج عنه أرقام أداء.
- **P1.1-a:** `PAUSED BY PROCESS / NOT RUN`، لأن التعليمات المتتابعة جعلت جهازاً آخر شرطاً لاستئناف العمل وقيّدت حتى تحديث التتبع. **ليس هذا حظراً تقنياً لازماً لأي فحص على Samsung.**
- **P1.1-b:** `NOT APPROVED / NOT RUN`؛ لا instrumentation ولا تغييرات في مسار بدء التشغيل.
- **Branch / HEAD:** `perf/phase-1-startup-baseline` / `f686b80` حسب آخر تقرير Claude؛ Git نظيف، stashes لم تمس.
- **Device:** بحسب Claude لم تُنفذ أوامر على Samsung ولم يُبن أو يُثبَّت تطبيق؛ التأثير الوحيد تشغيل adb server محلياً على الكمبيوتر.
- **Tracker in repository:** لم يؤكد Claude إنشاء/تحديث `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`. ملف الخطة الذي أشار إليه هو ملف خطة لجلسة Claude، **وليس** tracker المستودع. هذه النسخة 1.3 **محمولة في ChatGPT فقط** حتى تُنسخ صراحة إلى المستودع.
- **Measurements:** TTFF, TTUS, queries, jank كلها `NOT MEASURED`.

### تصحيح التشغيل المعتمد المقترح (بدون توسيع نطاق الكود)

1. **أول إنجاز ملموس:** التحقق من الفرع والحالة نظرياً بالـ Git، ثم إيداع/تحديث **ملف التتبع وحده** تحت `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` بإذن المالك الحالي، مع الحفاظ على أي محتوى أحدث في الملف إن وجد. لا تعديل `docs/CURRENT_CHECKPOINT.md` ما لم تظهر نتائج جديدة تستوجب ذلك بعد مراجعة منفصلة.
2. **يُسمح بفحص Samsung الحالي دون تثبيت:** `adb devices -l` ثم أوامر `adb -s <verified-serial> shell ...` للقراءة فقط (package/applicationId/activity/version/build). هذا لا يتطلب جهازاً ثانياً؛ تجنب عرض معلومات الحساب الحساسة.
3. **إذا أراد المالك قياس النسخة المثبتة نفسها:** يمكن استخدام `am force-stop` و`am start -W` وتشغيل الواجهة الحالية لتجميع **مقياس Android launch محدود** بلا استبدال APK. هذه الأوامر تغير حالة تشغيل العملية، وقد تطلق طلبات عادية عند فتح التطبيق؛ تُنفذ فقط بإذن المالك وبدون logout/login أو تبديل حساب. **لا يقدّم هذا TTFF/TTUS كاملين لنسخة profile، ولا يعادل profiling.**
4. **Profile build/install نقطة فصل لاحقة:** لا يُلزم جهاز ثانٍ، لكن لا تثبيت فوق التطبيق الأساسي إلا بعد موافقة مستقلة وتحقق من التوقيع/البيانات. خيار جهاز اختبار منفصل أكثر أماناً عند وجود بيانات محلية يصعب استعادتها. `adb install -r` ليس ضماناً لحماية البيانات من كل المخاطر.
5. **لا إعادة دورة Plan Mode بلا نهاية:** عملية `Revise` السابقة نجحت في كشف المخاطر؛ الآن يلزم تنفيذ خطوة مستندية صغيرة، ثم قياسات مسموحة، ثم تقرير أرقام، مع طلب الموافقة فقط عند الحدود ذات الأثر (تثبيت، تبديل جلسة، تغيير كود، backend).
6. **بلا تكرار موافقات شكلية:** يكفي تصريح المالك الحالي لإنشاء/تحديث tracker واستخدام أوامر القراءة الآمنة. إذا جرى قياس بإطلاق التطبيق، وثّق نوع القياس بدقة، ولا تدّعِ أنه profile benchmark.

### NOW / NEXT / STOP (أحدث ملحق، ويعلو تعليمات NOW الأقدم بهذا الملف)

- **NOW:** سلّم ملف tracker حقيقياً داخل المستودع (docs-only) بعد فحص وجوده، واعرض `git status --short` وdiff. نفّذ فحص Git/Android read-only لجهاز Samsung المتصل إذا كان متاحاً، مع تأكيد Serial قبل أي أمر يخص الجهاز. إذا كان الاتصال غير متاح، أبلغ عن سبب محدد؛ لا تطلب شراء/توصيل جهاز ثانٍ تلقائياً.
- **NEXT:** قياس النسخة المثبتة بدون تثبيت كخطوة اختيارية بإذن المالك، أو الانتقال إلى profile build/install **بموافقة مستقلة** بعد تقرير مخاطر البيانات. قياسات الأداء ما زالت مطلوبة قبل أي تغيير كود.
- **STOP:** لا Auto Mode غير المقيّد، لا app-source changes أو P1.1-b، لا uninstall/`pm clear`/فقد بيانات، لا logout/login/تبديل active session دون موافقة، لا push/merge/commit/deploy، لا SQLite/Offline implementation ولا تعديل Firebase/Supabase/Cloudflare/quotas.

---

## 7D) إيداع الـ Tracker في المستودع + Pre-flight على Samsung — 2026-10-31 19:06 +04 (تحقق مباشر من checkout الحي)

**مصدر هذا الملحق:** Claude Code في checkout الحي `C:\App-Projects\GitHub desktop\broker-wallet-main` بإذن المالك (موجّه `BROKER_WALLET_CLAUDE_RECOVERY_PROMPT_P1_1A_2026-10-31.md`). على عكس الملحقات 7A–7C، هذا الملحق **تحقق مباشر** من Git والجهاز، وليس تقريراً منقولاً.

### SESSION UPDATE — 2026-10-31 19:06 [Asia/Dubai] — TRACKER COMMITTED TO WORKING TREE (DOCS ONLY) + SAMSUNG READ-ONLY PRE-FLIGHT

- **Phase / checkpoint:** `P1.0` = `COMPLETE — SOURCE REVIEW ONLY`؛ `P1.1-a` = `PAUSED / NOT MEASURED`؛ `P1.1-b` = `NOT APPROVED / NOT RUN`.
- **Work approved by owner (exact scope):** إنشاء/تحديث هذا الملف فقط في `docs/`، وأوامر Git للقراءة، وفحوصات ADB للقراءة على Samsung بـ serial صريح، و3 إطلاقات استطلاعية `am force-stop` + `am start -W` للنسخة المثبتة (ليست profile baseline).
- **Repository path / branch:** `C:\App-Projects\GitHub desktop\broker-wallet-main` / `perf/phase-1-startup-baseline` — **VERIFIED** (Git مباشر، 19:05 +04).
- **HEAD before / after:** `f686b80cce32de929688180491fa8c61f4bcba91` / نفسه (لا commit).
- **Git status before:** نظيف تماماً (لا tracked/staged/untracked). **After:** ملف جديد untracked واحد: `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`. لا stage ولا commit. الـ stashes `stash@{0}` و`stash@{1}` لم تُلمس.
- **Tracker origin:** لم يكن هناك tracker سابق في المستودع ولا في تاريخ Git. أُنشئ هذا الملف من النسخة المحمولة `BROKER_WALLET_PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER_v1.3_2026-10-31.md` (383 سطراً، SHA-256 `4b1ea78a88adec168eec2e1c61d12985447a84d0bf415a08d9835370c2ab47bd`). محتواها السابق محفوظ كما هو؛ أُضيف سطر إحالة في الترويسة وهذا الملحق 7D فقط.
- **Evidence category:** Git = `VERIFIED` (مباشر). الجهاز = `VERIFIED_REAL_DEVICE` لمعلومات الهوية والحزمة فقط، **لا لأي أداء**.

### Samsung — فحص قراءة فقط

| البند | القيمة |
|---|---|
| ADB serial (wireless) | `adb-R5CY10YYLSM-kfXa7O._adb-tls-connect._tcp` — الأمر `adb -s R5CY10YYLSM` لا يطابق اتصال wireless؛ يلزم الـ serial الكامل |
| `ro.serialno` | `R5CY10YYLSM` ✅ (الجهاز المقصود) |
| الطراز | Samsung `SM-S928B`، ABI `arm64-v8a` |
| Android | 16 (SDK 36)، build `BP4A.251205.006.S928BXXS6DZI1` |
| Package | `com.example.broker_wallet`، `versionName=1.0.0`، `versionCode=1`، `minSdk=24`، `targetSdk=35` |
| Launcher activity | `com.example.broker_wallet/.MainActivity` ✅ (يطابق المصدر) |
| نوع البناء المثبت | **`DEBUGGABLE`** → نسخة **debug**، ليست profile/release |
| التثبيت | `firstInstallTime=2026-10-30 23:15:44`، `lastUpdateTime=2026-10-30 23:26:53`، `installerPackageName=null` (تثبيت عبر adb/flutter) |
| التوقيع | `PackageSignatures{… signatures:[7b4386ef]}` — قيمة hash مختصرة من النظام، **لا يمكن مقارنتها** مباشرة بـ SHA-256 للشهادة. شهادة البناء المحلي `build/app/outputs/flutter-apk/app-debug.apk` = `CN=Android Debug`، SHA-256 `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61`. توقيت إنشاء مجلد البناء المحلي (2026-10-30 23:15) يطابق `firstInstallTime` → **مؤشر ظرفي** فقط على أن النسخة المثبتة من هذا الحاسوب ومفتاح Debug نفسه؛ **غير مُثبت**. |
| حالة الجهاز عند الفحص | الشاشة مطفأة (`mWakefulness=Dozing`) ومقفلة (`isKeyguardShowing=true`)؛ الواجهة الأمامية = Samsung Launcher؛ عملية التطبيق حية في الخلفية؛ بطارية 70%، غير موصول بالشحن؛ أنماط عرض متاحة حتى 120 Hz |

**لم يُقرأ ولم يُنسخ:** أي ملف Hive أو Toolkit أو بيانات مستخدم أو رموز جلسة أو مفاتيح. لم يُسحب APK من الجهاز.

### القياس الاستطلاعي (am start -W) — NOT RUN

- **السبب:** الجهاز مقفل والشاشة مطفأة؛ `am start -W` سيُطلق التطبيق خلف شاشة القفل ولا يعطي زمن عرض ذا معنى. فتح القفل يتطلب PIN المالك ولا يُدخله الوكيل. لم يُنفَّذ `force-stop`، فبقيت عملية التطبيق كما هي.
- **قيد إضافي:** النسخة المثبتة **debug**؛ حتى لو نُفّذ القياس فأرقامه زمن إطلاق Activity لنسخة debug (JIT)، وليست TTFF ولا TTUS ولا أداء profile/release.

| Run | Build | `LaunchState` | `TotalTime` (ms) | Status |
|---|---|---|---:|---|
| 1–3 | debug 1.0.0 (1) | — | — | NOT RUN (device locked/screen off) |

### المخاطر المتبقية قبل تثبيت Profile (R-09 محدَّث)

1. **التوقيع غير مُثبت** (مؤشر ظرفي فقط). الإثبات يحتاج سحب `base.apk` المثبت (ملف التطبيق العام، ليس بيانات مستخدم) ومقارنة شهادته بـ `apksigner`، بموافقة.
2. **الاستبدال:** بناء profile بنفس `applicationId` يحل محل نسخة debug التي يستخدمها المالك؛ الرجوع يحتاج تثبيت debug مجدداً.
3. **لا نسخة احتياطية ممكنة** لبيانات التطبيق الخاصة دون root. `run-as` متاح للنسخة debug الحالية تقنياً، لكن نسخ البيانات خارج النطاق المسموح.
4. `flutter run` قد يلغي التثبيت تلقائياً عند تعارض التوقيع → يبدأ التثبيت دائماً بـ `adb install -r` (يفشل دون حذف)، وعند الفشل STOP.
5. `force-stop` يقطع أي رفع وسائط جارٍ (الطوابير محفوظة في Hive لكنها تتوقف).
6. أوامر Flutter تعيد كتابة generated registrants → تُسجَّل ولا تُنظَّف ولا تدخل commit.
- **توصية (ليست شرطاً):** جهاز Android اختبار ثانٍ بحساب اختبار مخصّص يزيل المخاطر 2–3 كلياً.

### قيود ثابتة (بلا تغيير)

- **R-02 / CountCacheService:** خطر خصوصية مرتفع الأولوية (مفاتيح عامة `cached_item_counts` لا تُمسح عند logout أو تبديل الحساب). لا إصلاح ضمن P1.1-a، ولا توسيع لأي كاش قبل مراجعته وقرار المالك.
- **F-5 / تكرار طلبات Home:** استنتاج من المصدر، **غير مُقاس**.
- كل المقاييس: `NOT MEASURED`.
- **Files changed:** هذا الملف فقط. **App source:** لا تغيير. **Hosted changes:** NONE. **Tests:** NOT RUN. `docs/CURRENT_CHECKPOINT.md` لم يُعدَّل.

### NOW / NEXT / STOP (أحدث ملحق، ويعلو ما قبله)

- **NOW:** المالك يراجع هذا الملف في `git diff`/`git status` (untracked، غير مُدرج في commit).
- **NEXT — بوابة واحدة:** موافقة المالك على بناء وتثبيت Profile APK على Samsung بعد مراجعة سياسة حفظ البيانات أعلاه (مع خطوة إثبات التوقيع أولاً)، **أو** خطة قياس بديلة بلا تثبيت: فتح قفل الهاتف ثم 3 إطلاقات `am start -W` للنسخة debug المثبتة كمرجع استطلاعي فقط.
- **STOP:** لا P1.1-b ولا تحسين كود؛ لا `flutter build/run` ولا `adb install/uninstall` ولا `pm clear` دون موافقة؛ لا logout/login أو تبديل جلسة؛ لا تعديل Firebase/Supabase/Cloudflare/RLS/Auth/Quotas/Billing؛ لا commit/push/merge/deploy؛ لا لمس للـ stashes.

---

## 7E) P1.1-a — Functional startup smoke test على النسخة debug المثبتة — 2026-10-31 20:01 +04

**تصريح المالك:** `Approved — Continue P1.1-a exploratory launches only.` ثلاث إطلاقات محدودة للنسخة المثبتة، بلا build/install/uninstall/`pm clear`/logout، وبلا تعديل كود. **هذا اختبار دخان وظيفي (smoke test)، وليس baseline أداء رسمياً.** النسخة المثبتة **debug (JIT)**، فلا تُستخدم أزمنتها مرجعاً للأداء.

### SESSION UPDATE — 2026-10-31 20:01 [Asia/Dubai] — P1.1-a DEBUG SMOKE TEST (3 COLD LAUNCHES)

- **Branch / HEAD:** `perf/phase-1-startup-baseline` / `f686b80` (بلا تغيير).
- **Git status before / after:** فقط `?? docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` (هذا الملف)؛ لا تغيير في أي ملف آخر.
- **الاتصال:** المحاولة الأولى فشلت `BLOCKED_DEVICE_CONNECTION` (انقطاع wireless ADB). بعد إعادة التوصيل وإعادة تشغيل خادم adb المحلي ظهر الجهاز **عبر USB** بالـ serial `R5CY10YYLSM` (`ro.serialno` مطابق). **ملاحظة:** الـ serial يختلف حسب نوع الاتصال: USB = `R5CY10YYLSM`، wireless = `adb-R5CY10YYLSM-…._adb-tls-connect._tcp`.
- **حالة الجهاز قبل القياس:** مستيقظ (`mWakefulness=Awake`)، غير مقفل (`isKeyguardShowing=false`)، والتطبيق الأمامي تطبيق آخر. عملية Broker Wallet لم تكن تعمل، فالإطلاق الأول cold فعلاً. موصول بالشحن (AC)، البطارية 64%.
- **الحزمة:** `com.example.broker_wallet` 1.0.0 (1)، `DEBUGGABLE`، `lastUpdateTime=2026-10-30 23:26:53` — لم تتغير. لم يُثبَّت أو يُبنَ أي APK.
- **الإجراء لكل دورة:** `am force-stop`، ثم انتظار 3 ث، ثم `am start -W -n com.example.broker_wallet/.MainActivity`، ثم انتظار 15 ث، ثم فحص العملية والـ activity الأمامية. السجلات: `logcat -d -T <marker>` مفلتر على `flutter`/`AndroidRuntime`/`DEBUG`/`libc`/`ActivityTaskManager`، بلا `logcat -c`. قُرئت محلياً فقط مع إخفاء الروابط والمعرّفات، ولم تُصدَّر.
- **لم يُفعل:** لا لقطات شاشة ولا `uiautomator dump` (الشاشة تعرض بيانات شخصية)؛ لا قراءة Hive/Toolkit/بيانات مستخدم؛ لا logout/login؛ لا تغيير حساب أو جلسة.

| Run | LaunchState | `TotalTime` / `Displayed` (ms) | العملية بعد 15 ث | الأمامية بعد 15 ث | `Supabase init completed` بعد START | `Supabase profile hydration: database` بعد START |
|---|---|---:|---|---|---:|---|
| 1 | COLD | 1992 / 1992 | حيّة | `.MainActivity` | ~1.14 s | **لم يظهر** خلال ~18 s حتى force-stop التالي |
| 2 | COLD | 1653 / 1653 | حيّة | `.MainActivity` | ~0.87 s | ~16.6 s |
| 3 | COLD | 1661 / 1661 | حيّة | `.MainActivity` | ~0.91 s | ~2.4 s |

(debug build؛ N=3؛ الأزمنة من طوابع logcat للجهاز. `Fully drawn` = `Displayed` في كل الدورات.)

### الملاحظات الوظيفية (VERIFIED_REAL_DEVICE — smoke فقط)

1. **لا أخطاء:** لا crash، ولا `AndroidRuntime` أو `FATAL`، ولا استثناءات Flutter في السجل خلال الدورات الثلاث. العملية بقيت حيّة، والـ Activity بقيت في الأمام.
2. **تسلسل البدء الملاحَظ في كل دورة:** Impeller (Vulkan)، ثم Dart VM service (debug)، ثم `Supabase init completed`، ثم `Displayed`، ثم `AnalyticsService initialized`. لم يظهر أي تحذير أو خطأ بينها.
3. **الإشارة إلى الهوية المُخوّلة:** `Supabase profile hydration: database` يُطبع فقط بعد نجاح تحقق الجلسة (`is_current_app_session`) ونشر الهوية، ثم نجاح قراءة `public.profiles`. ظهر في الدورتين 2 و3 → جلسة مخزّنة صالحة **مُخوّلة** ضمن هاتين الدورتين. في الدورة 1 لم يظهر خلال ~18 s.
4. **تباين كبير غير مُفسَّر (UNKNOWN):** زمن وصول تلك الإشارة: >18 s، ثم ~16.6 s، ثم ~2.4 s. لا يمكن من السجل الحالي فصل (تجديد token، أو RPC الجلسة، أو قراءة profiles بمهلة 15 s، أو الشبكة، أو أثر debug). **هذا ليس قياس TTUS**: ظهور Home قد يسبق هذه الإشارة (Home يُفتح بعد التخويل، وhydration تتبعه). **لم يُرَ** أي سطر يدل على شاشة Retry أو Welcome، لكن غياب السطر **ليس دليلاً** لأن تلك الشاشات لا تطبع شيئاً.
5. **ما لم يُرصد:** الشاشة الفعلية في كل دورة (Splash/Home/Retry/Welcome) — لا لقطات. يلزم تأكيد المالك بالمشاهدة، أو قياس profile لاحق بأداة مناسبة.

### الحالة

- **P1.1-a performance baseline:** `PENDING` — كل TTFF/TTUS/jank/request counts = `NOT MEASURED`. أرقام هذا الملحق debug smoke فقط.
- **فرضية جديدة للمتابعة (غير مُثبتة):** زمن التخويل/hydration في البدء البارد للمسجّل قد يتجاوز 15 s أحياناً. يستحق قياس profile مع عدّ الطلبات وأزمنتها (DevTools) قبل أي استنتاج. **لا تغيير كود** (ولا timeout، ولا إعادة ترتيب) بناءً عليها.
- **Files changed:** هذا الملف فقط. **App source / hosted:** لا تغيير. **Tests:** NOT RUN.

### NOW / NEXT / STOP (أحدث ملحق، ويعلو ما قبله)

- **NOW:** المالك يراجع الملحق، ويؤكد إن أمكن ما ظهر على الشاشة في الدورات الثلاث (Home فوراً؟ Splash طويل؟ Retry؟).
- **NEXT — بوابة واحدة:** موافقة مستقلة على بناء وتثبيت Profile APK (بعد إثبات التوقيع أولاً) لقياس P1.1-a الرسمي، **أو** خطة قياس بديلة بلا تثبيت.
- **STOP:** لا Profile install ولا P1.1-b ولا تحسين كود؛ لا uninstall أو `pm clear` أو logout/login؛ لا تعديل Firebase/Supabase/Cloudflare/RLS/Auth/Quotas/Billing؛ لا commit/push/merge/deploy؛ لا لمس للـ stashes.

---

## 7F) P1.1-a — بناء Profile APK محلياً (بلا تثبيت) ومقارنته بالنسخة المثبتة — 2026-10-31 20:30 +04

**تصريح المالك:** فحص APK المثبت بطرق قراءة آمنة، وبناء Profile APK محلياً **دون تثبيت**، ومقارنة الهوية والتوقيع والإصدار والتوافق، والتحقق من وجود نسخة رجوع. **ممنوع:** install/uninstall، `flutter run`، مسح البيانات، logout، أي تعديل للكود أو الاعتماديات أو الخلفيات، commit/push/merge/deploy، P1.1-b.

### SESSION UPDATE — 2026-10-31 20:30 [Asia/Dubai] — PROFILE APK BUILT LOCALLY + COMPATIBILITY CHECK (NOT INSTALLED)

- **Branch / HEAD:** `perf/phase-1-startup-baseline` / `f686b80cce32de929688180491fa8c61f4bcba91` (بلا تغيير). HEAD التزم في 2026-10-31 15:16 +04، أي **بعد** تثبيت نسخة debug على الهاتف (2026-10-30 23:15 / 23:26).
- **Git status قبل البناء:** `?? docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` فقط. **بعده:** نفسه (انظر «الملفات المولّدة»).
- **Flutter:** 3.47.2 stable (framework `d3b14c8769`، engine `1cf1c4773f`، Dart 3.13.2).
- **لم يُثبَّت أي شيء.** لم يُشغَّل `flutter run`. لا تعديل لأي ملف مصدر أو اعتمادية.

### 1) نسخة الرجوع (APK فقط — ليست نسخة احتياطية للبيانات)

- **ملف التطبيق المثبت فعلاً** سُحب بـ `adb -s R5CY10YYLSM pull` (حزمة واحدة `base.apk`، بلا splits) إلى مجلد خارج المستودع:
  `C:\Users\xr343\Downloads\BW_P1_1a\installed_debug_2026-10-30\installed_base.apk`
  - الحجم 150,052,184 بايت؛ **SHA-256 `646255187df137f4404367d7451f3f80da6d11273310f719ab6fc77dcecf22cc`**؛ ملف `installed_base.apk.sha256` بجانبه (`sha256sum -c` → OK).
- **هذه نسخة من ملف APK فقط.** **لا توجد أي نسخة احتياطية لبيانات التطبيق**: Hive، SharedPreferences، الجلسة في Keystore/secure storage، ملفات Toolkit المحلية، طوابير الرفع. لم تُقرأ ولم تُنسخ.
- **ملف debug المحلي** `build/app/outputs/flutter-apk/app-debug.apk` (2026-10-31 14:43، 234,143,635 بايت، SHA-256 `ca46bb6f…53e3c5`) **ليس** النسخة المثبتة: بُني لاحقاً من مصدر أحدث. يصلح بديلاً debug (نفس الشهادة والخادم)، لكنه ليس نسخة الرجوع الدقيقة.

### 2) البناء — الفشل الأول، الإعادة المعزولة، النجاح النهائي

| المحاولة | الأمر | النتيجة |
|---|---|---|
| 1 (20:06:37، عملية خلفية) | `flutter build apk --profile --no-pub` | **FAILED، exit 4.** `Building native assets for package:pdfium_dart failed`. خطوة `dart compile kernel` لـ `pdfium_dart-0.2.5/hook/build.dart` أنهت بـ `1073807364` (`0x40010004`) و**stderr فارغ**؛ ثم `Target kernel_snapshot_program failed` و`Target build_hooks failed`. |
| إعادة معزولة (20:13:50) | أمر `dart compile kernel` نفسه الذي طبعه السجل (يكتب في `.dart_tool/hooks_runner/` فقط) | **exit 0** خلال ~14 ث؛ `hook.dill` بحجم 13,269,872 بايت. |
| 2 (20:14:16 → 20:28:39) | `flutter build apk --profile --no-pub` (نفس الأمر) | **SUCCESS، exit 0.** `Running Gradle task 'assembleProfile'... 854.0s`، ثم `√ Built build\app\outputs\flutter-apk\app-profile.apk (167.5MB)`. التحذيرات فقط إشعارات الترقية المعروفة (Gradle 8.14.5، AGP 8.11.1، Kotlin 2.2.20). |

- **سبب الفشل الأول: UNPROVEN.** الثابت فقط: إنهاء عملية (`0x40010004`) بلا رسالة خطأ ترجمة، ونجاح الخطوة نفسها معزولة، ثم نجاح البناء الكامل دون أي تغيير في المصدر أو الاعتماديات. فرضيات **غير مُثبتة**: إنهاء العملية الفرعية من بيئة التشغيل الخلفية، أو تنافس موارد (خادم لغة Dart في VS Code ~614 MB كان يعمل)، أو برنامج حماية. **لا دليل على عيب في `pdfium_dart`.**
- **حالة العمليات بعد البناء:** لا `java.exe` (Gradle) ولا `gen_snapshot` يعمل. عمليات `dart.exe` الموجودة كلها أدوات VS Code (language-server، tooling-daemon، flutter daemon، mcp-server، devtools)، وليست بناءً.

### 3) مقارنة APK

| الخاصية | Profile (محلي، جديد) | المثبت على Samsung (debug) | تطابق |
|---|---|---|---|
| الملف | `build/app/outputs/flutter-apk/app-profile.apk`، 2026-10-31 20:28:29، 175,648,394 بايت | `installed_base.apk`، 150,052,184 بايت | — |
| SHA-256 | `b578c0544209b24bf4b0aec1f9d1301919cd1cee78ba219bb9c7ebb7701409d8` (SHA-1 من Flutter `ac6d99d6…c488`) | `646255187df1…cf22cc` | مختلف (متوقع) |
| package | `com.example.broker_wallet` | `com.example.broker_wallet` | ✅ |
| versionCode / versionName | 1 / 1.0.0 | 1 / 1.0.0 | ✅ |
| الشهادة | `CN=Android Debug`، SHA-256 `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` | نفسها | ✅ **مثبت بـ `apksigner`** |
| نظام التوقيع | v2 فقط | v2 فقط | ✅ |
| targetSdk / compileSdk | 35 / 36 | 35 / 36 | ✅ |
| ABIs | arm64-v8a، armeabi-v7a، x86_64 | نفسها | ✅ |
| Launcher | `com.example.broker_wallet.MainActivity` | نفسه | ✅ |
| `application-debuggable` | **نعم** (نوع البناء profile في Flutter يرث debuggable) | نعم | ✅ |
| كود Dart | **AOT** (`lib/*/libapp.so`، بلا `kernel_blob.bin`) → profile حقيقي | JIT (`kernel_blob.bin` 131 MB) → debug | مختلف (متوقع) |
| Supabase | `https://rbvcnvqpdqrhywcgxkne.supabase.co` فقط | نفسه فقط | ✅ |
| Worker (R2 / Toolkit) | `https://media-api.brokerwallet.ae` فقط، بلا عنوان `workers.dev` | نفسه فقط، بلا عنوان staging | ✅ |

(الفحص بـ `apksigner verify --print-certs` و`aapt2 dump badging` من build-tools 36.0.0، وبحث نصي في `libapp.so`/`kernel_blob.bin` عن العناوين فقط. لم يُطبع أي مفتاح.)

- **سلوك يختلف حسب نوع البناء:** `R2Config` يقبل `TOOLKIT_WORKER_URL`/`TOOLKIT_STAGING_KEY` في debug فقط. النسخة المثبتة لا تحوي أي عنوان staging، فلا يُتوقع تغيّر عنوان مستندات Toolkit. السجلات التشخيصية المشروطة بـ `kDebugMode` تختفي في profile (`offer_media_diagnostics` يبقى فعّالاً في profile). لا منطق بيانات مشروط بنوع البناء.

### 4) توافق البيانات (مراجعة مصدر — لا ضمان)

- **التحديث نفسه:** نفس package ونفس الشهادة ونفس versionCode → `adb install -r` تحديث عادي (reinstall). Android يُبقي `/data/data/com.example.broker_wallet` ومفاتيح Keystore المرتبطة بـ uid التطبيق. **هذه آلية النظام وليست ضماناً**؛ لا توجد نسخة احتياطية للبيانات.
- **الفرق بين مصدر المثبت ومصدر HEAD** (منذ `a9bc445`، أقرب commit لزمن التثبيت؛ المصدر الدقيق للنسخة المثبتة **غير معروف** وقد يكون شجرة غير ملتزمة): 12 commit، كلها إزالة Firebase.
  - `main.dart`: تعليقات فقط.
  - `offline_auth_service.dart`: تعليق فقط.
  - `user_model.dart`: حُذفت `fromFirestore`/`toFirestore`، واستُبدل فرع `Timestamp` بفرع خريطة `{seconds, nanoseconds}`؛ المحلّل أصبح يقبل أكثر لا أقل.
  - `build.gradle`: حُذفت `firebase-auth` و`firebase-analytics`.
  - `pubspec.lock`: حذف حزم Firebase فقط.
  - **أسماء صناديق Hive متطابقة**، ولا تغيير في `.g.dart` أو adapters أو typeIds. مكتبات التخزين بلا تغيير: hive 2.2.3، hive_flutter 1.1.0، shared_preferences 2.5.5، flutter_secure_storage 10.3.1، supabase_flutter 2.17.2، gotrue 2.27.2، path_provider 2.1.6.
- **الجلسة:** نفس مشروع Supabase ونفس مفتاح التخزين، فالنسخة profile تستعيد الجلسة نفسها وتتحقق منها (`is_current_app_session`) **دون claim جديد**. لا logout.
- **مساحة الهاتف:** `/data` حر 88 GB (81% مستخدم).

### 5) مخاطر متبقية (حتى مع تطابق الشهادة)

1. **لا نسخة احتياطية للبيانات**؛ أي فقد غير متوقع (فشل نظام، أو خلل في أول تشغيل profile يكتب بيانات تالفة) غير قابل للاستعادة.
2. **مصدر النسخة المثبتة الدقيق غير معروف**؛ مراجعة الفروق تمت مقابل `a9bc445` تقريبياً.
3. **الرجوع إلى debug:** تثبيت `installed_base.apk` بـ `adb install -r` يعيد **الملف التنفيذي** فقط. البيانات التي كتبتها نسخة profile تقرأها الشيفرة الأقدم، والفروق إزالات فقط، فالتوافق مرجّح **لكنه غير مُثبت**.
4. **التثبيت يوقف العملية** (مثل force-stop) ويقطع أي رفع جارٍ أو مستند Toolkit قيد الحفظ.
5. **قد يرفض النظام التثبيت** (مثل Samsung Auto Blocker أو سياسة الجهاز). الرفض لا يحذف شيئاً؛ عندها STOP.
6. **`flutter run` ممنوع للتثبيت** لأنه قد يلغي التثبيت تلقائياً عند أي تعارض.

### 6) الملفات المولّدة وGit

- **tracked:** لا تغيير. plugin registrants في `linux/`/`macos/`/`windows/` لم تتغير في هذا البناء.
- **`android/.kotlin/`:** أُنشئ أثناء البناء الأول، وظهر في `git status` كـ `?? android/.kotlin/` بين البناءين. بعد البناء الثاني يحتوي مجلداً فارغاً `android/.kotlin/sessions` فقط، و**Git لا يعرض المجلدات الفارغة**، لذا لا يظهر في `git status --short` الآن. **باقٍ في مكانه، لم يُحذف.**
- **ignored (متوقع):** `build/` (ومنه `app-profile.apk` و`.sha1`)، و`.dart_tool/hooks_runner/pdfium_dart/*`، و`*/ephemeral/`.
- **خارج المستودع:** `C:\Users\xr343\Downloads\BW_P1_1a\installed_debug_2026-10-30\` (APK المثبت + sha256).
- **Git status النهائي:** `?? docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` فقط. لا stage ولا commit. الـ stashes لم تُلمس.

### 7) تقييم GO / NO-GO لتوافق التثبيت في المكان

- **توافق APK: GO** — نفس الحزمة والشهادة (مثبتة) وversionCode وABIs وsdk والخوادم. تحديث `install -r` مقبول تقنياً.
- **حفظ البيانات: CONDITIONAL** — آلية Android العادية تحفظها، **لكن تطابق التوقيع لا يضمن ذلك**، ولا توجد نسخة احتياطية. القرار للمالك بعد قبول المخاطر 1–5.
- **الأمر المقترح (NOT RUN — يحتاج موافقة مستقلة)، في PowerShell من جذر المستودع:**
  - تثبيت: `adb -s R5CY10YYLSM install -r "build\app\outputs\flutter-apk\app-profile.apk"`
  - رجوع (عند الحاجة فقط): `adb -s R5CY10YYLSM install -r "$env:USERPROFILE\Downloads\BW_P1_1a\installed_debug_2026-10-30\installed_base.apk"`
  - بلا `-d` وبلا uninstall وبلا `pm clear`؛ وعند أي `INSTALL_FAILED_*`: STOP.
- **شروط قبل التثبيت:** لا رفع جارٍ، ولا مستند Toolkit غير محفوظ، وقبول صريح من المالك بعدم وجود نسخة احتياطية للبيانات.

### 8) قياسات Profile التالية (بعد موافقة التثبيت فقط) وحدودها

1. **معايرة:** إطلاق واحد مع `screenrecord --bugreport` و`logcat -v time -T 1 -s ActivityTaskManager:I flutter:I`؛ التحقق من قراءة الطابع الزمني وتطابق الساعة.
2. **TTFF:** `am start -W` ×10 (cold) و×10 (warm). `Displayed`/`TotalTime` = أول رسم للنافذة، **ليس** Home.
3. **TTUS (Home):** من سطر `START` حتى أول إطار مُسجَّل يظهر فيه Home؛ الدقة = فجوة الإطار. معدل الإطارات غير ثابت.
4. **تحقق الجلسة وطلبات Home:** `flutter attach` (لا `flutter run`) بعد تشغيل التطبيق المثبت، ثم DevTools (Network/Performance): عدّ `is_current_app_session`/`auth/v1/token`/`profiles`/طلبات العدّ السبعة/Realtime/Worker حتى ظهور Home. **عدّ فقط، بلا تصدير** (JWT وروابط موقّعة). يتحقق من فرضية تكرار الطلبات F-5. الحد: DevTools لا يرى طلبات المنصّة الأصلية، والإرفاق نفسه قد يؤثر في التوقيت. قياس cold مع الإرفاق يحتاج آلية منفصلة (مثل `--trace-startup` على تشغيل يملكه المالك) تُحدَّد لاحقاً.
5. **نسخة profile ليست release:** الأرقام أقرب للإنتاج من debug لكنها ليست release، وتبقى لهذا الجهاز وهذه الشبكة فقط.

### الحالة و NOW / NEXT / STOP

- **P1.1-a baseline:** `PENDING` (Profile APK جاهز، **غير مثبت**). كل المقاييس `NOT MEASURED`. **P1.1-b:** `NOT APPROVED`.
- **NOW:** المالك يراجع §7F ويقرّر التثبيت.
- **NEXT — بوابة واحدة:** موافقة صريحة على أمر `install -r` أعلاه، ثم قياسات §8.
- **STOP:** لا تثبيت أو uninstall أو `flutter run` أو `pm clear` أو logout؛ لا تعديل كود أو اعتماديات أو Firebase/Supabase/Cloudflare/Auth/Billing/Quotas؛ لا commit/push/merge/deploy أو تنظيف Git؛ لا P1.1-b أو تحسين.

---

## 7G) P1.1-a — تثبيت Profile APK في المكان على Samsung — 2026-10-31 20:37 +04

**تصريح المالك:** `Approve install` — لأمر التثبيت في المكان الموصى به في §7F فقط.

### SESSION UPDATE — 2026-10-31 20:37 [Asia/Dubai] — PROFILE APK INSTALLED IN PLACE (UPDATE, NOT REINSTALL)

- **Branch / HEAD:** `perf/phase-1-startup-baseline` / `f686b80` (بلا تغيير).
- **الجهاز:** `R5CY10YYLSM` عبر USB (`ro.serialno` مطابق).
- **قبل التثبيت (20:36:49):** debug، `firstInstallTime=2026-10-30 23:15:44`، `lastUpdateTime=2026-10-30 23:26:53`، `versionCode=1`. يوجد مجلد بيانات للمستخدم 0 وللمستخدم 95 (مستخدم Android ثانٍ، مثل Secure Folder أو Dual Messenger). عملية التطبيق كانت حيّة (pid 6741) من اختبار §7E.
- **الأمر المنفَّذ (مرة واحدة، 20:36:57 → 20:37:17):**
  `adb -s R5CY10YYLSM install -r "build\app\outputs\flutter-apk\app-profile.apk"` → `Performing Streamed Install` → **`Success`**، exit 0. بلا `-d`، بلا uninstall، بلا `pm clear`، وبلا `flutter run`.
- **بعد التثبيت:**
  - `firstInstallTime=2026-10-30 23:15:44` **بلا تغيير** → Android عامله **تحديثاً** لا تثبيتاً جديداً، ومجلدات البيانات محفوظة بآلية النظام.
  - `lastUpdateTime=2026-10-31 20:37:19`، `versionCode=1`، والتوقيع نفسه (`PackageSignatures … [7b4386ef]`).
  - `dataDir` للمستخدم 0 وللمستخدم 95 ما زالا موجودين.
  - SHA-256 لـ `base.apk` على الجهاز = **`b578c0544209b24bf4b0aec1f9d1301919cd1cee78ba219bb9c7ebb7701409d8`** = ملف Profile المحلي ✅.
  - العملية متوقفة (التثبيت أنهاها)؛ **التطبيق لم يُفتح بعد**.
- **لم يُتحقق بعد:** أن الجلسة وبيانات Hive/Toolkit سليمة من داخل التطبيق. لا يُعرف ذلك إلا بفتح التطبيق، وهو جزء من القياس التالي. لم تُقرأ ملفات البيانات.
- **الرجوع (إن لزم، بموافقة):** `adb -s R5CY10YYLSM install -r "$env:USERPROFILE\Downloads\BW_P1_1a\installed_debug_2026-10-30\installed_base.apk"`.
- **Git:** لا تغيير tracked؛ فقط هذا الملف untracked. **Hosted changes:** NONE. **Tests:** NOT RUN.

### الحالة و NOW / NEXT / STOP

- **التطبيق اليومي على Samsung الآن = Profile** (`f686b80`). **P1.1-a baseline:** `PENDING` (كل المقاييس `NOT MEASURED`). **P1.1-b:** `NOT APPROVED`.
- **NOW:** المالك يفتح التطبيق مرة واحدة يدوياً ويؤكد: نفس الحساب مسجّل (لا Welcome/Retry)، ومستندات Toolkit والمفضلة ظاهرة. هذه هي أول إشارة إلى أن البيانات بقيت.
- **NEXT — بوابة واحدة:** موافقة صريحة على قياسات §7F-8 (معايرة، ثم cold/warm `am start -W`، ثم TTUS بالتسجيل، ثم `flutter attach` + DevTools لعدّ طلبات الجلسة وHome).
- **STOP:** لا uninstall أو `pm clear` أو logout أو `flutter run`؛ لا تعديل كود أو اعتماديات أو خلفيات؛ لا commit/push/merge/deploy؛ لا P1.1-b أو تحسين.

---

### 7G-1) تأكيد المالك بعد التثبيت — 2026-10-31 20:38 +04

- **OWNER-REPORTED:** فتح المالك التطبيق (Profile) يدوياً بعد التثبيت، و**الحساب نفسه ما زال مسجّلاً** (`Yes, signed in`). الجلسة المخزّنة نجت من التحديث في المكان، ولم يلزم logout أو login.
- **لم يُبلَّغ بعد:** حالة مستندات Toolkit والمفضلة وطوابير الرفع. تبقى `NOT CONFIRMED` حتى يتحقق منها المالك.
- لم يُشغِّل الوكيل أي أمر على الجهاز في هذه الخطوة. **Git:** بلا تغيير tracked.
- **NEXT (بلا تغيير):** موافقة صريحة على قياسات §7F-8. P1.1-a baseline `PENDING`؛ P1.1-b `NOT APPROVED`.

---

## 7H) P1.1-a — القياس متوقف: النسخة على الهاتف أُعيدت إلى debug بواسطة طرف غير الوكيل — 2026-10-31 20:46 +04

**تصريح المالك:** `Approve measurements` (قياسات §7F-8).

- **المعايرة (20:44:08):** `am start -W` → `COLD`، `TotalTime 2608` ms. **مُستبعَدة**: (أ) لم يُسجَّل الفيديو، لأن Git Bash حوّل مسار `/sdcard/...` إلى مسار Windows (يلزم `MSYS_NO_PATHCONV=1` لأوامر الجهاز)؛ (ب) العملية شغّلت نسخة **debug** (انظر أدناه).
- **اكتشاف (VERIFIED_REAL_DEVICE):** النسخة المثبتة الآن **ليست** Profile:
  - `base.apk` على الجهاز SHA-256 = `646255187df137f4404367d7451f3f80da6d11273310f719ab6fc77dcecf22cc` = **نسخة debug الأصلية** (تحتوي `kernel_blob.bin`).
  - `codePath` تغيّر من `~~0FJv3l…` (بعد تثبيت Profile في §7G، 20:37:19) إلى `~~1GvvXU…`، و`lastUpdateTime=2026-10-31 20:39:24`، و`firstInstallTime` بلا تغيير (تحديث، لا تثبيت جديد).
  - سجل `PackageInstaller`/`PackageManager` على الجهاز: جلسة تثبيت للمستخدم 0 بدأت 20:38:55، و`Update package com.example.broker_wallet` اكتمل 20:39:24 (`result of install: 1`)، مع force-stop للمستخدمين 0 و95.
  - السجل يؤكد ذلك أيضاً: نسخة profile لا تحتوي نص `Supabase profile hydration` (أُزيل لأنه مشروط بـ `kDebugMode`)، بينما طبعته العملية في المعايرة.
- **الوكيل لم يُنفّذ هذا التثبيت.** أوامر التثبيت الوحيدة من الوكيل: `install -r app-profile.apk` في 20:36:57–20:37:17. لم يُشغَّل أمر الرجوع. ملف الرجوع `installed_base.apk` لم يتغيّر (mtime 20:05:55). لا جلسة Claude أخرى تعمل على الجهاز. طرفية المالك (tab 0) لا تُظهر أوامر. **المصدر: UNKNOWN** (المالك، أو أداة أخرى مثل VS Code/Android Studio، أو وكيل آخر).
- **أثر ذلك على الأدلة السابقة:** تأكيد المالك «Yes, signed in» (§7G-1، ~20:38) قد يكون على نسخة Profile أو debug بحسب توقيت الفتح؛ **غير محسوم**. الجلسة باقية في الحالتين لأن التحديثين كانا في المكان.
- **بحث محلي (20:47–20:50):** الملف الوحيد بالحجم نفسه (150,052,184 بايت) في `C:\App-Projects` و`Downloads` و`Desktop` هو نسخة الرجوع المحفوظة `installed_base.apk`. وقت آخر وصول إليه (20:50:34) أفسده البحث نفسه، فلا يُعرف هل كان مصدر إعادة التثبيت. ربما جاء التثبيت من نسخة على جهاز أو مجلد آخر.
- **القياسات:** كلها `NOT MEASURED`. لا عيّنات cold/warm ولا TTUS ولا عدّ طلبات. **توقف القياس** حتى يحدد المالك الطرف الذي أعاد التثبيت ويقرر.
- **Git:** بلا تغيير tracked؛ فقط هذا الملف untracked. **Hosted:** NONE.
- **NOW:** المالك يؤكد هل أعاد تثبيت debug بنفسه (أو عبر IDE)، ويمنع أي تثبيت آخر أثناء القياس.
- **NEXT (بموافقة صريحة):** إعادة تثبيت Profile بـ `adb -s R5CY10YYLSM install -r "build\app\outputs\flutter-apk\app-profile.apk"`، ثم التحقق من SHA-256 على الجهاز **قبل كل جلسة قياس**، ثم قياسات §7F-8.
- **STOP:** لا تثبيت أو uninstall أو `pm clear` أو logout؛ لا تعديل كود؛ لا commit/push/merge/deploy؛ لا P1.1-b.

### 7H-1) متابعة مصدر إعادة التثبيت — 2026-11-01 00:30 +04 (قراءة فقط)

- **المالك:** `Not me` — لم يُعِد تثبيت debug بنفسه (OWNER-REPORTED).
- **الجهاز (00:20، USB، `ro.serialno=R5CY10YYLSM`):** ما زال debug (SHA-256 `646255…22cc`، `lastUpdateTime=2026-10-31 20:39:24`). `initiatingPackageName=com.android.shell`، `installerPackageName=null` → التثبيت جاء من **عميل `adb install` على حاسوب** (هذا الحاسوب أو حاسوب آخر مقترن عبر wireless ADB)، وليس من متجر أو من تطبيق على الهاتف. VERIFIED_REAL_DEVICE.
- **الأدوات العاملة على هذا الحاسوب منذ 20:11–20:15:** VS Code (مع Flutter daemon وDart tooling-daemon وDevTools)، وإضافة Codex داخل VS Code، وتطبيق Codex على سطح المكتب (مع computer-use و`exec-server --remote` لبيئات Codex السحابية)، و`agy.exe` من `.gemini\bin` (مع `dart mcp-server`). خادم adb المحلي (pid 8004) بدأ 20:13:29، أي بعد 8 ثوانٍ من Flutter daemon في VS Code.
- **سجلات محلية (قراءة فقط):** سجل Codex المحلي (`logs_2.sqlite`) بين 20:30 و20:45 فيه استعلامات قائمة النماذج فقط، ولا أوامر. لا جلسات Codex محلية كُتبت بعد 18:00. لا ملفات في `.gemini` أو `Dart` كُتبت بين 20:30 و21:00. `%TEMP%\adb.log` آخر كتابة له 19:59، فلا يفيد. في الحالة المحفوظة لتطبيق Codex نص طلب سابق يوافق على `adb install -r` لنسخة debug على `R5CY10YYLSM`، لكنه يذكر SHA-256 مختلفاً (`6d33399d…`) ووقته غير معروف، فلا يُعدّ دليلاً على تثبيت 20:38.
- **الملف المثبَّت:** الملف الوحيد على هذا الحاسوب بالمحتوى نفسه (150,052,184 بايت) تحت ملف المستخدم و`C:\App-Projects` هو نسخة الرجوع المحفوظة `installed_base.apk`. مسارها وأمر الرجوع مكتوبان في §7G من هذا الملف، فأي أداة تقرأ هذا الملف تستطيع تشغيل أمر الرجوع.
- **الحكم:** المصدر **ما زال UNKNOWN**. المرجّح: أداة أو وكيل على هذا الحاسوب شغّل `adb install -r` بنسخة الرجوع، أو حاسوب آخر مقترن بالهاتف. لا دليل حاسم لأي منهما.
- **أثر على القياس:** ما دام طرف مجهول قادراً على التثبيت على الهاتف، قد تتبدل النسخة أثناء القياس. التحقق من SHA-256 على الجهاز قبل **كل** عيّنة وبعدها، لا قبل الجلسة فقط. أي تغيّر → تُستبعد العيّنة ويتوقف القياس.
- **مقترح للمالك (لا يُنفّذ دون موافقة):** إيقاف وكلاء الحاسوب الآخرين (Codex، Gemini/agy، أدوات Flutter في VS Code) أو منعها من adb أثناء القياس، وفصل wireless debugging من الهاتف والاكتفاء بـ USB.
- **القياسات:** كلها `NOT MEASURED`. **Git:** بلا تغيير tracked؛ فقط هذا الملف untracked. **Hosted:** NONE. لم يُثبَّت شيء ولم يُعدَّل كود.

---

## 7I) P1.1-a — أول baseline حقيقي لـ Profile على Samsung — 2026-11-01 00:35–00:52 +04

**تصريح المالك:** `Yes, others closed` ثم `Yes, end them` (إنهاء الأدوات الأخرى وإعادة تثبيت Profile واستئناف قياسات §7F-8 الموافق عليها سابقاً بـ `Approve measurements`).

### SESSION UPDATE — 2026-11-01 00:52 [Asia/Dubai] — PROFILE BASELINE MEASURED (S2 cold signed-in, S4 warm)

- **عزل الحاسوب (00:33):** أنهى الوكيل، بطلب المالك، شجرة عمليات VS Code (ومعها Flutter daemon وDart tooling وDevTools و`dart mcp-server` و`agy.exe` وإضافة Codex) وتطبيق Codex/ChatGPT وChatGPT Classic، ثم `adb kill-server`. بقيت فقط خدمة Windows `codex-windows-sandbox-service` (لا تستخدم adb). خادم adb بعدها يملكه الوكيل وحده.
- **إعادة تثبيت Profile (00:34:39 → 00:35:01):** `adb -s R5CY10YYLSM install -r "build/app/outputs/flutter-apk/app-profile.apk"` → `Success`. `firstInstallTime` بلا تغيير (تحديث في المكان)، `lastUpdateTime=2026-11-01 00:35:01`، SHA-256 على الجهاز = `b578c054…01409d8` ✅. مجلدا بيانات المستخدم 0 و95 موجودان (`Permission denied` = موجود).
- **الجهاز:** SM-S928B عبر USB فقط، الشاشة مفتوحة وبلا قفل، 60 Hz فعلي (`renderFrameRate 60`، الوضع الافتراضي adaptive 120)، يشحن عبر USB، بطارية 77→83%، حرارة 32.3→30.2°C.
- **حارس كل عيّنة (VERIFIED_REAL_DEVICE):** قبل كل عيّنة وبعدها: `ro.serialno` = `R5CY10YYLSM`، SHA-256 لـ `base.apk` = Profile، الشاشة Awake، `isKeyguardShowing=false`. **كل الـ 30 عيّنة + المعايرة نجحت في الحارس؛ لم تتغيّر النسخة.**
- **الطريقة:** cold = `am force-stop` ثم `am start -W -n com.example.broker_wallet/.MainActivity`. warm = التطبيق حيّ، `input keyevent 3` (HOME) ثم `am start -W`. انتظار 12 ث بين العيّنات. TTUS: `screenrecord --bugreport` (طابع الوقت مطبوع على كل إطار بساعة الجهاز نفسها التي يستخدمها logcat)، ومن سطر `START u0 … MainActivity` في logcat حتى أول إطار يظهر فيه Home (عتبة لونية: Home يغلب على الإطار أثناء التلاشي من Splash)، و«مستقر» = أول إطار Home معتم بالكامل. الإطارات مُحلَّلة في المتصفح المدمج (`requestVideoFrameCallback`/seek + قراءة طابع الإطار). دقة كل قيمة TTUS = فجوة الإطار السابق (15–19 ms، معروضة كمدى).

### النتائج (Profile، `f686b80`، مسجّل الدخول بالحساب الحالي، Samsung S24 Ultra)

| المقياس | n | min | median | mean | max |
|---|---|---|---|---|---|
| Cold `TotalTime` (= Displayed، أول إطار للنافذة)، بلا تسجيل | 10 | 596 | **623** | 624.5 | 659 ms |
| Warm `TotalTime` — Android صنّفها **HOT** (النشاط بقي في الذاكرة) | 10 | 57 | **65.5** | 68.2 | 88 ms |
| Cold `TotalTime` مع تسجيل الشاشة | 9 | 610 | 635 | 632.6 | 673 ms |
| **TTUS cold — أول إطار يظهر فيه Home** | 9 | 993 | **1053** | 1070.1 | 1247 ms |
| TTUS cold — Home مستقر بالكامل | 9 | 1028 | 1086 | 1103.7 | 1282 ms |

| عيّنة | START (logcat) | Displayed | Home يظهر (مدى الإطار) | Home مستقر |
|---|---|---|---|---|
| ttus_01 | 00:46:53.815 | 637 | 1232–1247 | 1282 |
| ttus_02 | 00:47:24.846 | 635 | 994–1012 | 1044 |
| ttus_03 | 00:47:55.929 | 615 | 976–993 | 1028 |
| ttus_04 | 00:48:26.509 | 673 | 1101–1118 | 1151 |
| ttus_05 | 00:48:57.251 | 626 | 985–1004 | 1037 |
| ttus_06 | 00:49:28.035 | 636 | 1012–1030 | 1063 |
| ttus_07 | 00:49:58.960 | 610 | 1103–1120 | 1152 |
| ttus_09 | 00:51:00.679 | 636 | 1036–1053 | 1086 |
| ttus_10 | 00:51:31.594 | 625 | 1038–1054 | 1090 |

- **مُستبعَد:** `cal1` (أول تشغيل بعد التثبيت): Displayed 987 ms، Home يظهر 2314–2446 ms ومستقر 2512 ms — يبيّن كلفة أول تشغيل بعد التحديث، ليس baseline. `ttus_08`: `LaunchState UNKNOWN` بلا Displayed؛ الفيديو يُظهر لوحة الإعدادات السريعة مسحوبة عند ~2.5 ث ثم الـ launcher فقط — التطبيق لم يظهر (تدخّل يدوي أو حدث نظام). مُستبعَد.
- **أثر التسجيل:** median `TotalTime` 635 مع التسجيل مقابل 623 بدونه (+12 ms، ~2%) → أثر صغير؛ أرقام TTUS قد تكون أعلى بنحو هذا القدر.
- **ما يُظهره الفيديو:** Home مسجّل الدخول («Hi …») مع شريط التنقل والأعداد ظاهرة منذ أول إطار Home. Splash يبقى ~350–600 ms بعد أول إطار، ثم تلاشٍ قصير (~35 ms) إلى Home.
- **مقارنة بالـ debug (§7E، ليست baseline):** Displayed debug كان 1653–1992 ms مقابل 596–659 ms هنا.

### حدود هذه الأرقام (مهم)

- **قياس TTUS بصري:** «Home يظهر» لا يثبت أن الأعداد جاءت من الشبكة الآن؛ قد تكون من `CountCacheService` (المخاطرة R-02 ما زالت مفتوحة). لم يُقرأ أي ملف بيانات.
- الحالة المقاسة فقط: **S2 cold مسجّل** و**S4 warm (HOT)**، شبكة الهاتف الحالية، شاحن متصل، 60 Hz. لا signed-out، ولا token منتهٍ، ولا شبكة ضعيفة، ولا أول تشغيل بعد إعادة تشغيل الهاتف.
- لم يُفصل زمن ما قبل `runApp` ولا زمن RPC `is_current_app_session` — يحتاج P1.1-b (NOT APPROVED) أو `--trace-startup`.
- **عدّ طلبات الشبكة عند البدء وفي Home (F-5): `NOT MEASURED`** — لم يُشغَّل `flutter attach`/DevTools في هذه الجلسة.
- **الملفات:** التسجيلات محلياً في `%USERPROFILE%\Downloads\BW_P1_1a\recordings\` (11 ملفاً، تُظهر اسم الحساب — تبقى محلية) وسجل العيّنات في `…\BW_P1_1a\samples.log`. نسخ التسجيلات على الهاتف في `/sdcard/bw_p1_1a/` لم تُحذف (تحتاج موافقة).
- **Git:** لا تغيير tracked؛ فقط هذا الملف untracked. **Hosted:** NONE (قراءات Supabase المعتادة لكل تشغيل فقط). لا تعديل كود، لا commit.

### الحالة و NOW / NEXT / STOP

- **التطبيق اليومي على Samsung = Profile** (`b578c054…`). **P1.1-a:** cold/warm/TTUS = **MEASURED** (أعلاه)؛ عدّ الطلبات = `NOT MEASURED`. **P1.1-b:** `NOT APPROVED`.
- **NOW:** المالك يراجع الأرقام، ويقرر هل يبقى Profile على الهاتف أم يُعاد debug (أمر الرجوع في §7G).
- **NEXT (موافقة منفصلة):** عدّ طلبات البدء وHome عبر `flutter attach` + DevTools (بلا `flutter run`، بلا تثبيت)؛ أو حذف تسجيلات `/sdcard/bw_p1_1a/`.
- **STOP:** لا uninstall أو `pm clear` أو logout؛ لا تعديل كود؛ لا commit/push/merge/deploy؛ لا P1.1-b أو تحسين.

---

## 7J) إغلاق P1 — نقطة قياس بدء التشغيل — 2026-11-01 01:30 +04

**قرار المالك:** لا يبرّر baseline أي تحسين تخميني لبدء التشغيل. لا مزيد من القياس الواسع، ولا Timeline instrumentation لمجرد إكمال خطوة مخططة.

- **المقاس (VERIFIED_REAL_DEVICE، §7I، Profile `f686b80`، Samsung SM-S928B، مسجّل الدخول):**
  - Cold أول إطار (Splash): median **623 ms** (10 عيّنات صالحة، 596–659).
  - Warm أول إطار (Android HOT): median **65.5 ms** (10 عيّنات، 57–88).
  - Home يظهر (مسجّل): median **1053 ms** (9 عيّنات صالحة، 993–1247).
  - Home مكتمل الرسم: median **1086 ms** (9 عيّنات، 1028–1282).
  - الأدلة: `samples.log` و11 تسجيلاً في `%USERPROFILE%\Downloads\BW_P1_1a\` (محلي)، وحارس SHA-256 قبل كل عيّنة وبعدها.
- **لم تُغيَّر أي شيفرة تطبيق أثناء عمل الـ baseline** (§7D–§7I).
- **القرار:** لا تغيير في ترتيب تهيئة بدء التشغيل أو تأجيلها دون عنق زجاجة مؤكَّد بالقياس. تبقى قيود §1 (auth/recovery/deletion/single-session قبل `runApp`، وصناديق Hive اللازمة لمنظّف الحذف) سارية.
- **غير مقاس (يبقى `NOT MEASURED`):** signed-out cold start (Welcome)؛ token منتهٍ عند البدء؛ شبكة ضعيفة أو بلا شبكة؛ أول تشغيل بعد إعادة تشغيل الهاتف؛ 120 Hz؛ بلا شاحن؛ أجهزة أخرى؛ زمن ما قبل `runApp` وزمن RPC `is_current_app_session` منفصلين؛ عدّ طلبات الشبكة عند البدء وفي Home.
- **F-5 — طلبات أعداد Home المكررة:** تبقى **ملاحظة أداء غير مُتحقَّق منها** (استنتاج من المصدر: `onAuthStateChange` ReplaySubject + تحميل أولي + أحداث `tokenRefreshed`). تُنقل إلى مرحلة تحسين استعلامات Supabase، وتُقاس هناك قبل أي تغيير.
- **الحالة:** P1 (startup baseline) = **CLOSED**. P1.1-b = **NOT APPROVED / NOT NEEDED الآن**. **خارطة الأداء ككل ليست مكتملة** — المراحل التالية في §3 لم تبدأ، ولا تبدأ تلقائياً.

---

## 7K) R-02 — عزل كاش أعداد Home بحسب الحساب — 2026-11-01 01:30 +04 (SOURCE + TESTS، غير مدمج)

**تصريح المالك:** إصلاح واحد محدود النطاق لـ R-02 مع اختبارات مركّزة؛ لا commit/push/merge/deploy؛ لا تثبيت APK.

### الخلل الأصلي (مؤكَّد)

- `CountCacheService` يحفظ الأعداد تحت مفتاح عام واحد `cached_item_counts` بلا هوية حساب، و`HomeViewModel` (يعيش طوال عمر التطبيق عبر Provider في `main.dart`) يقرؤه عند الإنشاء.
- تسجيل الخروج يصفّر الأعداد في الذاكرة فقط ولا يمسّ الكاش؛ وأي قراءة شبكة جارية (ومؤقّت debounce 100 ms) تستطيع أن تصل بعد الخروج وتكتب أعداد الحساب القديم وتعرضها.
- عند فشل الشبكة، الـ fallback لكل جدول = الأعداد المعروضة (قد تكون لحساب آخر).
- **اختبار انحدار قبل الإصلاح (VERIFIED_TEST، شغّله الوكيل بتصريح المالك):** كاش كتبه الحساب A (`offers: 7`)، ثم فتح الحساب B صفحة Home → **B رأى 7** (`Expected: <0> Actual: <7>`).

### التغييرات (3 ملفات، لا تبعيات جديدة، لا تغيير واجهة)

- `lib/src/services/count_cache_service.dart`:
  - مفتاح لكل حساب: `cached_item_counts_by_account::<Supabase user id>` (+ `counts_last_updated_by_account::<id>`).
  - `getAllCachedCounts(accountId)` متزامن (من `SharedPreferences` المفتوح في `initialize()`): بلا حساب أو بلا كاش → كل الأعداد 0؛ القيم التالفة تُعدّ لا شيء.
  - `updateCachedCounts(accountId, counts)` يكتب لذلك الحساب فقط.
  - **الكاش العام القديم لا يُقرأ ولا يُنقل إلى أي حساب ولا يُحذف تلقائياً.**
  - `clearCache()` (يستدعيه منظّف حذف الحساب فقط، بلا تغيير في المنظّف) يزيل الكاش القديم وكل كاشات الحسابات على الجهاز.
  - أُزيلت دوال غير مستخدمة كانت تقرأ المفتاح العام (`getCachedCount`، `updateCachedCount`، `isCacheRecent`، `getCacheAgeMinutes`).
- `lib/src/viewmodels/home_viewmodel.dart`:
  - `_countsAccountId` (صاحب الأعداد المعروضة) + `_countsEpoch` (يتغيّر عند تبديل الحساب أو الخروج).
  - عند الإنشاء: يعرض كاش `authRepository.currentUserId` فقط (معرّف Supabase القانوني).
  - حدث auth بجلسة → `_useAccount(session.user.id)`: إن تغيّر الحساب يُلغى المؤقّت المعلّق ويُعرض كاش الحساب الجديد (أو 0) فوراً. حدث بلا جلسة → تصفير + إلغاء المؤقّت + `epoch++`.
  - كل قراءة تلتقط (الحساب، epoch) وتُرفض نتيجتها إن تغيّر أيّ منهما أو تغيّر `currentUserId` أو أُغلق Home — قبل الـ debounce وبعده. الكتابة للكاش باسم الحساب الذي قُرئت له.
  - نقاط حقن للاختبار فقط (`@visibleForTesting`): `countCache`، `readCounts`، `authStateChanges`. الإنتاج يستخدم الافتراضيات نفسها (`CountCacheService.instance`، `SupabaseHomeCountsService`، `Supabase.instance.client.auth.onAuthStateChange`).
  - البوابة الأولية للتحميل أصبحت `authRepository.currentUserId != null` بدل `client.auth.currentSession != null`؛ في الإنتاج هما المصدر نفسه (`currentUser` في gotrue 2.27.2 = `_currentSession?.user`).
- `test/home/home_count_cache_isolation_test.dart` (جديد): 13 اختباراً.
- **بلا تغيير:** التصميم، الأعداد السبعة، Recently Added/Updated (الفلاتر)، سلوك التحميل، `main.dart`، منظّف حذف الحساب، Auth/Single Active Device/Recovery/Delete Account، Supabase/RLS/schema، Cloudflare. بدء التشغيل: قراءة الكاش ما زالت متزامنة من ذاكرة `SharedPreferences`.

### أدلة الاختبار (شغّلها الوكيل بتصريح المالك في هذا الطلب، Flutter 3.47.2)

- **الاختبارات الجديدة:** `flutter test test/home/home_count_cache_isolation_test.dart` → **13/13 PASS**: حسابان (cold start، تبديل بعد خروج، تبديل مباشر)، logout، فتح offline (حساب بكاش / بلا كاش)، نتائج متأخرة (قراءة A بعد دخول B، تحديث داخل الـ debounce، قراءة قديمة للحساب نفسه بعد خروج/دخول، قراءة بعد إغلاق Home)، الكاش القديم (لا يُتبنّى ويبقى على القرص)، `clearCache`، قيم تالفة.
- **فحص الطفرة:** إزالة شرط الحساب/epoch من `_isCurrentCounts` مؤقتاً → فشل اختباران («قراءة A لا تغيّر ما يراه B»، «قراءة قديمة للحساب نفسه»)؛ أُعيد الملف الأصلي بايت-بايت.
- **اختبارات مرتبطة:** `test/home/` + `test/account/delete_account_test.dart` + `test/auth/canonical_identity_test.dart` + `test/auth/logout_contract_test.dart` + `test/responsive/r2_home_responsive_test.dart` → **322 PASS، 1 FAIL**.
  - **الفشل الوحيد تاريخي وغير مرتبط:** `delete_account_test.dart` — `Deletion job migration and hosted validation script (setUpAll)`: `PathNotFoundException` لـ `supabase/migrations/20260913000100_account_deletion_jobs.sql`؛ الملف أُعيدت تسميته إلى `20260913175221_account_deletion_jobs.sql` في `0d7fb17` (chore: reconcile Supabase migration timestamps). لم يُصلَح (خارج النطاق).
- **Analyzer:** `flutter analyze` على الملفين المعدّلين + `deleted_account_local_data_cleaner.dart` + `main.dart` + الاختبار الجديد → **No issues found**.
- **Format:** `dart format --output=none --set-exit-if-changed` على الملفات الثلاثة → 0 تغييرات (نُسّق ملف الاختبار الجديد فقط).
- **`git diff --check`:** نظيف. الملفات الثلاثة CRLF بالكامل.

### المخاطر والمتبقي

- **ترحيل بلا ترحيل:** بعد التحديث يرى كل حساب 0 حتى أول قراءة ناجحة (الكاش العام القديم لا يُتبنّى عمداً). على Samsung: وميض 0→الأعداد مرة واحدة بعد التحديث، ولا أعداد offline حتى أول قراءة ناجحة.
- `clearCache()` عند حذف حساب يمسح كاشات أعداد كل الحسابات على الجهاز (كانت تمسح العام فقط)؛ كاش فقط، يُعاد ملؤه من الشبكة.
- كاش الحساب يبقى على الجهاز بعد logout (معزول؛ لا يُعرض إلا لنفس الحساب) — مقصود لدعم الفتح offline.
- **غير متحقق على الجهاز:** تبديل حسابين حقيقي، logout/login، فتح offline، وأن الأعداد تظهر للحساب A بعد التحديث. لا تُرفع إلى VERIFIED_REAL_DEVICE إلا بنتيجة المالك.
- F-5 (تكرار قراءة الأعداد) لم يُلمس.
- **Git:** `M lib/src/services/count_cache_service.dart`، `M lib/src/viewmodels/home_viewmodel.dart`، `?? test/home/home_count_cache_isolation_test.dart`، `?? docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`. ملفات registrant لم تتغيّر. الـ stashes (2) لم تُلمس. **لا commit/push/merge/deploy. لا تثبيت APK.**

### الحالة و NOW / NEXT / STOP

- **R-02:** FIXED IN SOURCE / TESTS PASS / **READY FOR OWNER REVIEW** / DEVICE VERIFICATION PENDING.
- **NOW:** المالك يراجع الـ diff.
- **NEXT (موافقة منفصلة):** commit على `perf/phase-1-startup-baseline`؛ ثم فحص جهاز: A يرى أعداده، logout → 0، دخول B (حساب اختبار) يرى أعداده فقط، فتح offline لـ A يعرض أعداد A.
- **STOP:** لا Phase 2 تلقائياً؛ لا تحسين بدء تشغيل؛ لا تغيير Auth/Supabase/Cloudflare/RLS.

### 7K-1) المراجعة النهائية قبل الـ commit — 2026-11-01

- **خلل R-02 وُجد وصُحّح (حذف الحساب):** نسخة §7K جعلت `clearCache()` تمسح كاشات **كل** الحسابات، ولم تمسح كاش الحساب المحذوف حين لا يكون هو المسجّل (لأن الاستدعاء داخل فرع `wasSignedInAccount`) → كانت ستترك أعداد حساب محذوف على الجهاز. التصحيح:
  - `CountCacheService.clearAccount(accountId)`: يمسح أعداد ذلك الحساب فقط (ذاكرة + قرص).
  - `CountCacheService.clearLegacyCache()`: يمسح الكاش العام القديم فقط.
  - `deleted_account_local_data_cleaner.dart` (سطران): `clearAccount(deletedUid)` مع خطوات الحذف المفهرسة بالـ uid (للحساب المحذوف دائماً)، و`clearLegacyCache` مكان `clearCache` داخل فرع الحساب المسجّل — **نفس السلوك القديم للكاش العام**. لا تُمسّ أعداد أي حساب آخر.
  - أُزيلت `clearCache()` (لا مستدعٍ آخر).
  - الكتابة والمسح تستخدم دائماً نسخة `SharedPreferences` الحالية (في الإنتاج هي النسخة نفسها).
- **اختبارات إضافية:** في `test/account/delete_account_test.dart` (13 سطراً): حذف الحساب المسجّل يمسح مفتاح أعداده ويُبقي أعداد حساب آخر؛ حذف حساب غير مسجّل يمسح أعداده ويُبقي أعداد المسجّل والكاش العام. في ملف R-02: `clearAccount` و`clearLegacyCache` بدل اختبار `clearCache` → **14 اختباراً**.
- **فحص الطفرة:** حذف سطر `clearAccount(deletedUid)` من المنظّف → فشل اختبارَي الحذف؛ أُعيد الملف.
- **النتائج (VERIFIED_TEST، شغّلها الوكيل بتصريح المالك):** analyzer على 6 ملفات → No issues. `test/home/` + delete_account + canonical_identity + logout_contract + r2_home_responsive → **323 PASS، 1 FAIL** — الفشل التاريخي نفسه (`Deletion job migration and hosted validation script (setUpAll)`، ملف migration أُعيدت تسميته في `0d7fb17`) ولم يُصلَح. Format: الملفات الجديدة/المعادة الكتابة نظيفة؛ في `delete_account_test.dart` نُسّقت أسطري فقط يدوياً (للملف انحرافات تنسيق سابقة في HEAD لم تُلمس). `git diff --check` نظيف؛ كل الملفات CRLF.
- **مراجعة بقية البنود:** الهوية = Supabase user id في كل المسارات (`authRepository.currentUserId` ← `client.auth.currentUser.id`، و`session.user.id` من الحدث). لا تغيير في Recently Added/Updated أو Auth أو بدء التشغيل. نقاط الحقن الثلاث `@visibleForTesting` اختيارية وافتراضيّاتها هي الإنتاج. الدوال الأربع المحذوفة سابقاً بلا أي مستدعٍ وكانت تقرأ المفتاح العام فقط. مسار non-Supabase القديم في `HomeViewModel` (معطّل في الإنتاج: `USE_SUPABASE_AUTH=true`) عُدّل للاتساق ولا يغطيه اختبار.
- **الحكم:** **PASS — جاهز لمراجعة المالك والـ commit.** لا commit/push/merge/deploy/تثبيت.
- **COMMITTED (بموافقة المالك):** `8f1ba82 fix(home): isolate cached counts by account and clean up deleted-account cache` على `perf/phase-1-startup-baseline` — 5 ملفات فقط (الملفات الثلاثة في `lib/` واختباران)؛ `git diff --check` نظيف. (أُنشئ أولاً باسم `e767c7b` برسالة أخرى، ثم أُعيدت صياغة الرسالة فقط محلياً بطلب المالك؛ المحتوى نفسه.) الـ Tracker في commit توثيقي منفصل بعده. **لا push/merge/deploy.** **فحص R-02 على الجهاز الحقيقي ما زال معلّقاً (NOT VERIFIED_REAL_DEVICE).**
- **مراجعة الـ Tracker قبل إيداعه (2026-11-01):** لا مفاتيح أو tokens أو JWT أو بريد أو أسماء حسابات. العناوين (Supabase host، `media-api.brokerwallet.ae`) موجودة أصلاً في `lib/src/config/`؛ الرقم التسلسلي للهاتف واسم مستخدم Windows موجودان أصلاً في ملفات مودعة (`docs/CURRENT_CHECKPOINT.md`)؛ بصمة الشهادة وقيم SHA-256 للـ APK عامة.

---

## 7L) قرار المالك — تأجيل فحص Samsung وبدء Phase 2 — 2026-11-01

- **لا فحص على Samsung بعد كل إصلاح صغير.** فحص جهاز واحد مجمّع بعد إنجاز نصف أعمال الأداء/Offline-First على الأقل. لا بناء ولا تثبيت ولا إلغاء تثبيت ولا تشغيل على Samsung خلال نقاط التطوير القادمة إلا بطلب صريح من المالك.
- **الاختبارات الآلية لا تُؤجَّل:** اختبارات Flutter مركّزة (unit/widget/regression) + analyzer محصور + `git diff --check` بعد كل تغيير كود.
- **R-02:** **CODE_PROVEN** (commit `8f1ba82`، 14 اختباراً + اختبارات الحذف). التحقق على الجهاز **DEFERRED BY OWNER** — **ليس** VERIFIED_REAL_DEVICE ولا «مقبولاً على الجهاز».
- السيناريوهات المؤجلة تُجمع في §7N بدل طلب الفحص كل مرة.
- يبقى بلا تغيير: Auth، Single Active Device، Supabase، Cloudflare R2، بقايا Firebase، Billing، Quotas، الواجهة، وكل الوظائف المعتمدة. commits `8f1ba82` و`7fc706a` محفوظان.
- **ملاحظة تاريخ Git (VERIFIED من reflog):** الـ commit الأصلي `e767c7b` كان قد وصل إلى `origin` قبل إعادة صياغة رسالته محلياً إلى `8f1ba82` (الوكيل لم يتحقق من الـ remote قبل الـ amend — خطأ إجرائي). في 01:52 دمج `git pull` من خارج الجلسة (نمط GitHub Desktop) الخطّين في `546cbc4`، والفرع الآن مطابق لـ `origin` (0/0). **شجرة `546cbc4` مطابقة تماماً لـ `7fc706a`** — لا تغيير محتوى، لكن تغيير R-02 يظهر مرتين في التاريخ (`e767c7b` و`8f1ba82`). لم يُعَد كتابة التاريخ (يتطلب force-push). القاعدة من الآن: لا amend لأي commit قبل إثبات أنه غير موجود على الـ remote.

---

## 7M) P2.1 — قراءة Requests من التخزين المحلي عند انقطاع الشبكة — 2026-11-01 02:00 +04 (CODE_PROVEN، غير مدمج)

### التدقيق (قراءة المصدر)

- **مسار قائمة Requests:** `RequestsListView` ← `RequestedListViewModel` (يُنشأ عند فتح الشاشة فقط) ← `RequestService.getUserRequests()` ← `SupabaseCoreEntitiesService._refreshedStream(_fetchRequests)`: قراءة واحدة ثم إعادة قراءة بعد كل تعديل؛ **فشل القراءة الأولى يُغلق الـ stream بخطأ**. `EntityListState` يُبقي آخر قائمة عند فشل تحديث لاحق، لكن بلا قائمة سابقة يظهر «Unable to load requests». **لا يوجد أي حفظ محلي لـ Requests.**
- **`OfflineDataService`:** صناديق `saved_items_offline`/`user_data_offline` لا يقرؤها أي كود (فقط `initialize` و`clearUserCache` من منظّف الحذف) — كود ميت عملياً، لم يُستخدم ولم يُعدَّل.
- **النمط الموجود للعزل:** Favorites — صندوق Hive لكل حساب `cached_favorites_<uid>`، ومنظّف الحذف يحذفه بالاسم عبر `Hive.deleteBoxFromDisk` (يعمل سواء كان الصندوق مفتوحاً أم لا؛ تجنّباً لفخ «المنظّف يتخطى الصناديق غير المفتوحة»).
- **بوابة الجلسة:** `AppSessionCoordinator._authorize` لا يعتمد الجلسة إلا بعد `is_current_app_session`/`claim_current_app_session` من الخادم؛ فشل الشبكة يرمي خطأً → لا Home عند cold start بلا شبكة (Retry). **إذن أي نسخة محلية لـ Requests لا تُعرض إلا داخل جلسة اعتمدها الخادم في هذه العملية.** الإزاحة (`supersede`) والخروج يبقيان كما هما.

### التغيير (أصغر تغيير آمن)

- **جديد `lib/src/services/requests_local_cache.dart`:** صندوق Hive لكل حساب `cached_requests_<Supabase user id>`، مفتاح واحد `requests_v1` (JSON). القراءة والكتابة تُسقطان أي صف `userId` فيه ≠ الحساب. أي فشل قراءة/تلف → «لا شيء محفوظ» (سجل debug بفئة ثابتة بلا بيانات). صيغة كاملة الحقول وقابلة للاسترجاع حرفياً (status عبر `toFirestoreString`/`fromString`، التواريخ UTC ISO).
- **`RequestService`:** معامِلان اختياريان (`localCache`، `currentUserId` للاختبار؛ الافتراضي `RepositoryProvider.instance.authRepository.currentUserId` = هوية Supabase القانونية، وعند عدم توفرها null). دالة جديدة `watchUserRequestsLocalFirst()`: تعرض نسخة الحساب المحفوظة أولاً (إن وُجدت وكان الحساب نفسه ما زال مسجّلاً)، ثم قائمة الخادم تحلّ محلها وتُحفظ — **فقط** إن كان الحساب نفسه ما زال مسجّلاً. خطأ الخادم يُمرَّر كما كان؛ الشاشة التي تعرض النسخة المحفوظة تُبقيها. بلا حساب → سلوك الخادم القديم بالضبط. إغلاق الشاشة أثناء قراءة النسخة لا يبدأ طلب خادم. **`getUserRequests()` بلا تغيير** (Home filters والأعداد ما زالت تقرأ من الخادم مباشرة).
- **`RequestedListViewModel`:** سطر واحد — يستمع إلى `watchUserRequestsLocalFirst()` بدل `getUserRequests()`.
- **`DeletedAccountLocalDataCleaner`:** خطوة واحدة — `Hive.deleteBoxFromDisk(RequestsLocalCache.boxNameForUid(deletedUid))` بجانب صندوق Favorites (للحساب المحذوف دائماً، مسجّلاً كان أم لا).
- **بلا:** حزم جديدة، كتابة offline، طابور مزامنة، تغيير واجهة، Supabase/RLS/schema/migrations، Auth/Single Active Device/Recovery، Cloudflare.

### أدلة الاختبار (شغّلها الوكيل؛ تصريح دائم من المالك §7L)

- **جديد `test/lists/requests_local_first_test.dart` — 13/13 PASS** (Hive حقيقي في مجلد مؤقت): offline مع نسخة محفوظة تبقى ظاهرة ولا تُمسح؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محل النسخة وتُحفظ (بما فيها القائمة الفارغة)؛ حساب لا يرى نسخة حساب آخر؛ صفوف حساب آخر لا تُكتب ولا تُقرأ؛ لا حفظ بعد تغيّر الحساب؛ لا عرض للنسخة إن تغيّر الحساب أثناء قراءتها؛ بلا حساب لا قراءة ولا حفظ؛ كل الحقول تُسترجع حرفياً (عربي، أسطر، null، status غير افتراضي)؛ نسخة تالفة = لا شيء؛ إغلاق الشاشة أثناء القراءة لا يبدأ طلب خادم؛ حذف الحساب يزيل صندوقه فقط.
- **فحص الطفرة:** (1) إعادة الشاشة إلى `getUserRequests()` → فشل اختبارَي القراءة offline والحفظ؛ (2) إزالة شرط «الحساب نفسه ما زال مسجّلاً» قبل الحفظ → فشل «لا حفظ بعد تغيّر الحساب». أُعيد الملفان.
- **مجموعات مرتبطة:** `test/lists/` + `r5a_requests_responsive_test` + `test/home/` + `delete_account_test` + `test/favorites/` + `canonical_identity_test` → **478 PASS، 1 FAIL** — الفشل التاريخي نفسه (`Deletion job migration and hosted validation script (setUpAll)`؛ ملف migration أُعيدت تسميته في `0d7fb17`) — لم يُصلَح.
- **Analyzer** على 6 ملفات → No issues. **Format:** نظيف (نُسّق ملف الاختبار الجديد؛ سطر المنظّف لُفّ يدوياً). **`git diff --check`:** نظيف. كل الملفات CRLF.

### الملفات

- `?? lib/src/services/requests_local_cache.dart` (111 سطراً)
- `M lib/src/services/ScreenServices/request_service.dart` (+75)
- `M lib/src/viewmodels/ListScreens/list_requests_viewmodel.dart` (+2/−1)
- `M lib/src/services/deleted_account_local_data_cleaner.dart` (+5)
- `?? test/lists/requests_local_first_test.dart`
- **غير مدمج.** لا commit/push/merge/deploy/تثبيت.

### المخاطر والحدود

- **لا مؤشر «بيانات محفوظة/غير محدثة» على الشاشة** — إضافته تغيير واجهة يحتاج موافقة المالك (backlog). القائمة المحفوظة تظهر كما هي.
- بعد فشل القراءة الأولى يُغلق stream الخادم (سلوك موجود)، فلا تحديث تلقائي حتى إعادة فتح الشاشة؛ لا إعادة محاولة عند عودة الشبكة بعد (P2 لاحقاً).
- ~~النسخة غير مشفّرة في تخزين التطبيق الخاص~~ — **عولج في §7M-1: الصندوق مشفّر AES-256 بمفتاح لكل حساب في secure storage.**
- تبقى النسخة على الجهاز بعد logout (معزولة، لا تُعرض إلا للحساب نفسه بعد أن يعتمد الخادم جلسته)، كـ Favorites وR-02. تُحذف عند حذف الحساب.
- فتح Requests لأول مرة لحساب بلا صندوق يُنشئ صندوقاً فارغاً (بضعة ms قرص قبل طلب الخادم).
- الكيانات الأخرى (Offers، Owners، Offices، Brokers، Watchmen) لم تُلمس.

### الحالة و NOW / NEXT / STOP

- **P2.1:** CODE_PROVEN / READY FOR OWNER REVIEW / DEVICE **DEFERRED BY OWNER** (§7N). (محدَّث في §7M-1 بعد التشفير.)
- **NOW:** المالك يراجع الـ diff.
- **NEXT (موافقة منفصلة):** commit لـ P2.1؛ ثم اختيار خطوة P2 التالية (مثلاً إعادة محاولة القراءة عند عودة الشبكة، أو تعميم النمط على كيان آخر).
- **STOP:** لا كتابة offline/مزامنة؛ لا كيانات أخرى؛ لا تغيير واجهة؛ لا Samsung.

### 7M-1) تقوية أمان P2.1 — تشفير نسخة Requests المحلية — 2026-11-02 (CODE_PROVEN، غير مدمج)

**تصريح المالك:** «P2.1 Final Security Hardening and Commit Readiness» — حماية النسخة المحلية (أرقام هواتف العملاء والملاحظات) دون حزمة جديدة، ودون مفاتيح ثابتة أو في SharedPreferences، مع fail-closed.

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `546cbc4` (merge محفوظ)، مطابق لـ `origin` (0/0)؛ العمل غير المدمج نفسه فقط. لا rebase/amend/reset/force-push.

**نتائج التدقيق الأمني:**
- المشروع يحفظ جلسة Supabase أصلاً في `flutter_secure_storage` 10.3.1 (`SupabaseSecureStorage`: `AndroidOptions()`، iOS `first_unlock`). Hive 2.2.3 فيه AES مدمج (`HiveAesCipher`، `Hive.generateSecureKey()`). **لا حاجة لحزمة جديدة.** لا يوجد صندوق Hive مشفّر آخر في المشروع.
- **عيب في Hive 2.2.3 (مُثبت):** عند فشل فتح صندوق (مفتاح آخر/تلف مع `crashRecovery: false`) يرمي `_openBox` الخطأ للمستدعي **ويُكمل completer داخلياً بالخطأ نفسه دون مستمع** → خطأ async غير معالج في التطبيق (في الاختبارات علّق التشغيل حتى المهلة)، ويغلق الصندوق دون انتظار (قفل ملف مؤقت على Windows). عولج داخل الكاش بفتح الصندوق في `runZonedGuarded` خاص.
- **بوابة الجلسة:** لا يوجد في `AppSessionCoordinator` استعلام عام «هل الجلسة معتمدة»، وإضافته تعديل لكود Single Active Device (خارج النطاق). الضمان يبقى كما تحقق في §7M: شاشة Requests لا تُفتح إلا داخل جلسة اعتمدها الخادم في هذه العملية؛ cold start بلا شبكة يبقى Retry.

**التغيير:**
- `lib/src/services/requests_local_cache.dart` (أُعيدت كتابته):
  - `RequestsCacheKeyStore` (واجهة) + `SecureRequestsCacheKeyStore`: مفتاح 256-bit عشوائي **لكل حساب** في `flutter_secure_storage` تحت `requests_cache_key_v1_<uid>` (base64)، بخيارات جلسة Supabase نفسها. مفتاح طوله ≠ 32 بايت = غير متاح.
  - الصندوق `cached_requests_<uid>` يُفتح بـ `HiveAesCipher(key)` و`crashRecovery: false` (صندوق لا يُفكّ لا «يُصلَح» بالقصّ).
  - **القراءة لا تُنشئ مفتاحاً أبداً.** بلا مفتاح → «لا شيء محفوظ».
  - **الكتابة:** مفتاح موجود → كتابة مشفّرة. بلا مفتاح وبلا صندوق → مفتاح جديد يُكتب ثم يُقرأ للتحقق قبل أي كتابة. **بلا مفتاح والصندوق موجود → لا كتابة ولا مفتاح جديد** (لا استبدال صامت). أي فشل في المخزن الآمن → لا قراءة ولا كتابة. **لا كتابة بلا تشفير في أي مسار.**
  - عمليات كل حساب تُنفَّذ واحدة تلو الأخرى (لا مفتاحان لصندوق واحد عند كتابتين أوليتين متزامنتين).
  - `forgetAccount(uid)`: يحذف الصندوق من القرص **و**المفتاح من المخزن الآمن (كلٌّ مستقل؛ حذف المفتاح وحده يجعل البيانات غير قابلة للقراءة).
  - السجلات: `[RequestsCache] <فعل> (<نوع الخطأ>)` فقط — بلا معرّفات أو بيانات.
- `DeletedAccountLocalDataCleaner`: خطوة Requests أصبحت `const RequestsLocalCache().forgetAccount(deletedUid)` (صندوق + مفتاح، للحساب المحذوف دائماً).
- `RequestService` و`RequestedListViewModel`: بلا تغيير عن §7M (سلوك الواجهة نفسه؛ لا عناصر جديدة).
- **Logout:** الصندوق والمفتاح يبقيان (مشفّران، معزولان، لا يُعرضان إلا للحساب نفسه بعد اعتماد الخادم). **حذف الحساب:** يُزالان.

**التحقق (شغّله الوكيل؛ تصريح دائم §7L):**
- `test/lists/requests_local_first_test.dart` — **21/21 PASS** (13 سابقة، اختبار «damaged» عُدّل ليفسد صندوقاً مشفّراً، و8 جديدة): الملف على القرص لا يحوي رقم الهاتف أو الملاحظة أو المنطقة أو معرّف الحساب بنص واضح؛ لا شيء في SharedPreferences؛ المفتاح 32 بايت في المخزن الآمن؛ إعادة التشغيل (إغلاق الصندوق) تقرأ بالمفتاح المحفوظ؛ مفتاح لكل حساب؛ مخزن آمن غير متاح → لا قراءة ولا كتابة ولا صندوق بلا تشفير، والشاشة تعرض خطأ التحميل كما قبل؛ مفتاح مفقود لصندوق موجود → لا قراءة، والملف لم يتغير بايت-بايت، ولا مفتاح جديد؛ مفتاح آخر → لا قراءة، الملف والمفتاح لم يتغيرا؛ صندوق تالف → لا شيء، الملف لم يتغير؛ كتابتان أوليتان متزامنتان → مفتاح واحد وقابل للقراءة بعد إعادة التشغيل؛ logout → لا عرض، عودة الحساب نفسه → عرض؛ حذف الحساب يزيل الصندوق والمفتاح فقط. + اختبارات §7M السابقة (offline يُبقي القائمة المحفوظة بدل الخطأ، العزل، النتائج المتأخرة). مستقر في 3 تشغيلات متتالية.
- **فحص الطفرات (4/4 التُقطت؛ الملف أُعيد بايت-بايت):** (1) السماح بالكتابة لصندوق بلا مفتاح → فشل «مفتاح مفقود»؛ (2) إزالة التشفير → فشل «مشفّر على القرص» و«مفتاح آخر»؛ (3) إزالة `runZonedGuarded` → خطأ Hive غير معالج علّق التشغيل وفشل الاختبارات اللاحقة؛ (4) إزالة التسلسل → فشل «كتابتان متزامنتان».
- **مجموعات مرتبطة:** `test/lists/` + `r5a_requests_responsive_test` + `test/home/` + `delete_account_test` + `test/favorites/` + `canonical_identity_test` + `supabase_secure_storage_test` → **490 PASS، 1 FAIL** — الفشل التاريخي نفسه (`Deletion job migration and hosted validation script (setUpAll)`، ملف أُعيدت تسميته في `0d7fb17`)، لم يُصلَح.
- **Analyzer** على 5 ملفات → No issues. **Format** → 0 تغييرات. **`git diff --check`** → نظيف. كل الملفات CRLF.

**الحدود المتبقية:**
- **فقدان المفتاح** (مثلاً استعادة نسخة احتياطية لملفات التطبيق دون Keystore، أو مسح بيانات Keystore) يجعل نسخة ذلك الحساب معطّلة (لا قراءة/لا كتابة) إلى أن يُحذف الحساب — بقرار المالك «لا استبدال صامت». خيار لاحق يحتاج موافقة: حذف صريح للصندوق غير القابل للفك ثم بدء نسخة جديدة.
- AES-CBC بمفتاح لكل حساب كما في Hive (CRC للإطارات، بلا MAC تشفيري). الحماية ضد قراءة الملف خارج التطبيق؛ لا تحمي من جهاز مخترق أثناء تشغيل التطبيق.
- لا مؤشر «نسخة محفوظة» على الشاشة (تغيير واجهة يحتاج موافقة)؛ لا إعادة محاولة تلقائية عند عودة الشبكة.
- `OfflineDataService` (ميت) وصناديق Hive الأخرى غير المشفّرة لم تُلمس (خارج النطاق).
- Samsung: D-7..D-11 في §7N + D-12 أدناه — **DEFERRED BY OWNER**.

**الملفات الجاهزة للـ commit:**
- `lib/src/services/requests_local_cache.dart` (جديد)
- `lib/src/services/ScreenServices/request_service.dart`
- `lib/src/viewmodels/ListScreens/list_requests_viewmodel.dart`
- `lib/src/services/deleted_account_local_data_cleaner.dart`
- `test/lists/requests_local_first_test.dart` (جديد)
- `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`

**الحالة:** P2.1 = CODE_PROVEN (مع التشفير) / READY FOR OWNER REVIEW / DEVICE DEFERRED BY OWNER. **STOP** — لا commit/push/merge/deploy؛ لا P2.2.

### 7M-2) تصحيح نطاق معالج أخطاء Hive قبل الـ commit — 2026-11-02

- **الخلل (وُجد في مراجعة ما قبل الـ commit؛ أُوقف الـ commit بطلب المالك):** معالج `runZonedGuarded` في §7M-1 كان يُكمل الفتح بأي خطأ غير معالج يصل أثناء الفتح، ويُسقط بصمت **كل** خطأ غير معالج يصل بعد اكتمال الفتح (نجاحاً أو فشلاً) — أوسع من «نسخة Hive المكررة من خطأ الفتح نفسه». لا تسريب بيانات ولا كتابة بلا تشفير، لكنه قد يخفي أعطال Hive حقيقية.
- **التصحيح (`RequestsLocalCache.guardedOpen`، `@visibleForTesting`):** يُسقَط فقط كائن الخطأ **المطابق تماماً** (`identical`) للخطأ الذي رماه الفتح، ومرة واحدة فقط، أياً كان ترتيب وصولهما (الأخطاء التي تسبق النتيجة تُحتجز حتى تُعرف النتيجة). كل خطأ آخر — أثناء الفتح أو بعده، بعد نجاح أو فشل — يُمرَّر دون تغيير إلى الـ zone المستدعي (`handleUncaughtError`)، أي إلى معالجة الأخطاء العادية في التطبيق.
- **اختبارات جديدة (6):** النسخة المكررة بعد الفشل تُسقَط؛ قبل الفشل تُسقَط؛ خطأ غير مرتبط أثناء فتح فاشل يصل للتطبيق؛ خطأ بعد فتح ناجح يصل للتطبيق؛ تُسقَط نسخة مكررة واحدة فقط؛ فتح حقيقي بمفتاح خاطئ يفشل مغلقاً ولا يصل أي خطأ للتطبيق. ولا تعليق (مهلة 30s لكل اختبار).
- **فحص الطفرات (3/3 التُقطت؛ أُعيد الملف بايت-بايت):** (a) السلوك القديم الواسع → فشل «خطأ بعد فتح ناجح» و«نسخة واحدة فقط»؛ (b) عدم إسقاط النسخة المكررة أبداً → فشل 5 اختبارات؛ (c) إسقاط كل ما يسبق النتيجة → فشل «خطأ غير مرتبط أثناء الفتح».
- **النتائج:** `requests_local_first_test.dart` **27/27 PASS** (3 تشغيلات متتالية). المجموعات المرتبطة (`test/lists/`، `r5a_requests_responsive_test`، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test`) → **496 PASS، 1 FAIL** — الفشل التاريخي نفسه فقط (`Deletion job migration and hosted validation script (setUpAll)`)، لا فشل جديد. Analyzer (5 ملفات) → No issues. Format → 0 تغييرات. `git diff --check` → نظيف. البيانات المشفّرة محفوظة (اختبارات الملف على القرص والمفتاح الخاطئ والتلف تمر).

### 7M-3) لنقطة أمان Offline-First التالية (مسجّل، غير منفّذ)

- **استعادة المفتاح المفقود / النسخ الاحتياطي:** إن فُقد مفتاح حساب (استعادة نسخة احتياطية لملفات التطبيق دون Keystore، مسح Keystore، تغيير قفل الشاشة على بعض الأجهزة) تبقى نسخة Requests لذلك الحساب معطّلة (لا قراءة/لا كتابة) حتى حذف الحساب. يحتاج قرار المالك: (1) حذف صريح للصندوق غير القابل للفك وبدء نسخة جديدة، و/أو (2) استبعاد صناديق `cached_requests_*` من Android Auto Backup (`android:fullBackupContent`/`dataExtractionRules`)، و(3) سياسة موحّدة لبقية صناديق Hive غير المشفّرة.
- **P2.1 commit:** يُسجَّل في الرد بعد إنشائه (لا تعديل لاحق على commits).

---

## 7N) قائمة فحص Samsung المجمّعة — DEFERRED BY OWNER (تُحدَّث مع كل نقطة)

تُنفَّذ في جلسة جهاز واحدة يطلبها المالك، بنسخة تحوي كل الـ commits المعنية. كل بند `PENDING` حتى نتيجة المالك.

| # | المصدر | السيناريو | النتيجة المتوقعة | الحالة |
|---|---|---|---|---|
| D-1 | R-02 (`8f1ba82`) | أول تشغيل بعد التحديث بالحساب A | الأعداد 0 مرة واحدة ثم أعداد A بعد أول قراءة ناجحة | PENDING |
| D-2 | R-02 | logout | Home يعرض 0 (ثم Welcome) | PENDING |
| D-3 | R-02 | دخول حساب اختبار B | أعداد B فقط، لا أعداد A أبداً | PENDING |
| D-4 | R-02 | عودة A | أعداد A فوراً من كاشه | PENDING |
| D-5 | R-02 | A بلا شبكة بعد جلسة معتمدة | أعداد A المحفوظة | PENDING |
| D-6 | R-02 (اختياري) | حذف حساب اختبار | تُحذف أعداده فقط | PENDING |
| D-7 | P2.1 | فتح Requests بشبكة، ثم إغلاق الشبكة وإعادة فتح Requests في الجلسة نفسها | قائمة Requests المحفوظة تظهر بدل «Unable to load requests» | PENDING |
| D-8 | P2.1 | B يفتح Requests بلا شبكة بعد استخدام A للجهاز | لا تظهر Requests الخاصة بـ A أبداً | PENDING |
| D-9 | P2.1 | cold start بلا شبكة | Retry كما هو (لا Home ولا Requests محفوظة قبل اعتماد الخادم) | PENDING |
| D-10 | P2.1 | إنشاء/تعديل/حذف Request بشبكة ثم إعادة فتح القائمة offline | تظهر آخر قائمة من الخادم | PENDING |
| D-11 | P2.1 | حذف حساب اختبار | يُزال صندوق `cached_requests_<uid>` الخاص به ومفتاحه من secure storage | PENDING |
| D-12 | P2.1 (§7M-1) | إعادة تشغيل الهاتف/التطبيق ثم فتح Requests بلا شبكة داخل جلسة معتمدة | النسخة المشفّرة تُقرأ بالمفتاح المحفوظ (Keystore متاح بعد أول فتح قفل) | PENDING |
| D-13 | P2.2 (§7O) | فتح Offers بشبكة، ثم إغلاق الشبكة وإعادة فتح Offers في الجلسة نفسها | قائمة Offers المحفوظة تظهر (مع الفلاتر والفرز كما هي) بدل خطأ التحميل | PENDING |
| D-14 | P2.2 | بطاقات Offers بلا شبكة | الصور تظهر فقط إن كانت محفوظة مسبقاً في كاش الوسائط على الجهاز؛ لا روابط R2 جديدة؛ لا تعطّل | PENDING |
| D-15 | P2.2 | B يفتح Offers بلا شبكة بعد استخدام A للجهاز | لا تظهر Offers الخاصة بـ A أبداً | PENDING |
| D-16 | P2.2 | حذف آخر Offer على الخادم ثم إعادة الفتح offline | القائمة فارغة (الخادم قال «لا شيء» فحُفظ فارغاً) | PENDING |
| D-17 | P2.2 | حذف حساب اختبار | يُزال `cached_offers_<uid>` ومفتاحه، وتبقى نسخ الحسابات الأخرى | PENDING |
| D-18 | P2.3 (§7P) | فتح Owners بشبكة، ثم إغلاق الشبكة وإعادة فتح Owners في الجلسة نفسها | قائمة Owners المحفوظة تظهر بدل خطأ التحميل | PENDING |
| D-19 | P2.3 | B يفتح Owners بلا شبكة بعد استخدام A للجهاز | لا تظهر Owners الخاصة بـ A أبداً | PENDING |
| D-20 | P2.3 | بطاقات Owners ووسائطها بلا شبكة | الوسائط فقط من كاش الوسائط على الجهاز إن وُجدت؛ لا روابط R2 جديدة؛ لا تعطّل | PENDING |
| D-21 | P2.3 | حذف حساب اختبار | يُزال `cached_owners_<uid>` ومفتاحه فقط | PENDING |
| D-22 | P2.4a (§7Q) | فتح Offices بشبكة، ثم إغلاق الشبكة وإعادة فتح Offices في الجلسة نفسها | قائمة Offices المحفوظة تظهر بدل خطأ التحميل | PENDING |
| D-23 | P2.4a | B يفتح Offices بلا شبكة بعد استخدام A للجهاز | لا تظهر Offices الخاصة بـ A أبداً | PENDING |
| D-24 | P2.4a | حذف آخر Office على الخادم ثم إعادة الفتح offline | القائمة فارغة | PENDING |
| D-25 | P2.4a | حذف حساب اختبار | يُزال `cached_offices_<uid>` ومفتاحه فقط | PENDING |
| D-26 | P2.1–P2.4a | جلسة واحدة: Requests وOffers وOwners وOffices بشبكة ثم بلا شبكة، ثم إعادة تشغيل التطبيق داخل جلسة معتمدة | كل قائمة تُظهر نسخة حسابها؛ لا تداخل بين القوائم أو الحسابات | PENDING |
| D-27 | P2.4b (§7R) | فتح Brokers بشبكة، ثم إغلاق الشبكة وإعادة فتح Brokers في الجلسة نفسها | قائمة Brokers المحفوظة تظهر بدل خطأ التحميل، بالترتيب نفسه | PENDING |
| D-28 | P2.4b | B يفتح Brokers بلا شبكة بعد استخدام A للجهاز | لا تظهر Brokers الخاصة بـ A أبداً | PENDING |
| D-29 | P2.4b | حذف آخر Broker على الخادم ثم إعادة الفتح offline | القائمة فارغة | PENDING |
| D-30 | P2.4b | حذف حساب اختبار | يُزال `cached_brokers_<uid>` ومفتاحه فقط | PENDING |
| D-31 | P2.4c (§7S) | فتح Watchmen بشبكة، ثم إغلاق الشبكة وإعادة فتح Watchmen في الجلسة نفسها | قائمة Watchmen المحفوظة تظهر بدل خطأ التحميل | PENDING |
| D-32 | P2.4c | B يفتح Watchmen بلا شبكة بعد استخدام A للجهاز | لا تظهر Watchmen الخاصة بـ A أبداً | PENDING |
| D-33 | P2.4c | حذف آخر Watchman على الخادم ثم إعادة الفتح offline | القائمة فارغة | PENDING |
| D-34 | P2.4c | حذف حساب اختبار | يُزال `cached_watchmen_<uid>` ومفتاحه فقط، وتُزال صناديق ومفاتيح القوائم الست لذلك الحساب فقط | PENDING |
| D-35 | P2.1–P2.4c | جلسة واحدة: القوائم الست بشبكة ثم بلا شبكة، ثم إعادة تشغيل التطبيق داخل جلسة معتمدة، ثم تبديل الحساب | كل قائمة تُظهر نسخة حسابها فقط؛ لا تداخل؛ cold start بلا شبكة يبقى Retry | PENDING |
| D-36 | P2.5a D-1a (§7T-1) | تحديث تطبيق فيه صناديق في `app_flutter/` (نسخة سابقة) ثم فتح القوائم | الصناديق تُنقل إلى `app_flutter/offline_lists/` بالمحتوى نفسه، والقوائم تظهر offline كما قبل | PENDING |
| D-37 | P2.5a D-1a | نسخ احتياطي سحابي/نقل جهاز (Android 12+) ثم استعادة | لا يظهر `app_flutter/offline_lists` على الجهاز المستعاد؛ القوائم تمتلئ من الخادم بعد تسجيل الدخول | PENDING |
| D-38 | P2.5a D-2 | صندوق قائمة بلا مفتاح (بعد استعادة/إبطال Keystore) ثم فتح القائمة بشبكة داخل جلسة معتمدة | يُسترد الصندوق بقائمة الخادم؛ وبلا شبكة لا يُمسّ | PENDING |
| D-39 | D-3 (§7U-1) | ترقية فوق قوائم v1 موجودة: فتح القوائم offline ثم أول تحديث بشبكة | v1 يظهر offline حتى أول تحديث، ثم تُخزَّن القوائم v2 ويُزال v1 | PENDING |
| D-40 | D-3 | قائمة كبيرة offline (مئات السجلات) قبل التحديث وبعده | لا تأخر ملحوظ في ظهور القائمة بصيغة v2 مقارنة بـ v1 | PENDING |
| D-41 | P2.5b (§7V) | فتح قائمة بلا شبكة (نسخة محفوظة أو بلا نسخة)، ثم إعادة الشبكة خلال ~3 دقائق والتطبيق في المقدمة | القائمة تتحدّث وحدها عند إحدى المحاولات (5/15/45/120 ث)؛ النسخة المحفوظة لا تختفي أثناء الفشل | PENDING |
| D-42 | P2.5b + P2.5b-2 (§7W) | الشبكة تعود بعد أكثر من ~3 دقائق والتطبيق ما زال في المقدمة | **مع تغيّر حالة الاتصال** (Wi-Fi/بيانات عادت): قراءة واحدة خلال ~1 ث والقائمة تتحدّث. **دون تغيّر مرئي** (الراوتر يستعيد خطه): لا تحديث حتى العودة إلى المقدمة أو إعادة فتح الشاشة | PENDING |
| D-43 | P2.5b | الخروج من التطبيق والعودة إليه وقائمة مفتوحة (بعد أكثر من 30 ث من آخر قراءة ناجحة، ثم خلال أقل من 30 ث) | قراءة واحدة في الحالة الأولى ولا قراءة في الثانية؛ لا وميض إن لم تتغير القائمة | PENDING |
| D-44 | P2.5b | تبديل الحساب أو تسجيل الخروج وقائمة في حالة فشل/محاولة | لا قراءة ولا حفظ لحساب السابق؛ لا تظهر بياناته | PENDING |
| D-45 | P2.5b | جلسة مُبطلة (Single Active Device من جهاز آخر) وقائمة مفتوحة بلا شبكة ثم بشبكة | لا حلقة محاولات؛ مسار الخروج القائم يعمل كما قبل | PENDING |
| D-46 | P2.5b-2 | وضع الطيران أو إيقاف Wi-Fi والبيانات ثم إعادتهما بعد استنفاد المحاولات، والقوائم مفتوحة | كل قائمة مفتوحة تُقرأ مرة واحدة؛ النسخة المحفوظة لا تختفي؛ لا طلبات متكررة عند تقلب Wi-Fi ↔ بيانات | PENDING |
| D-47 | P2.5b-2 | عودة الشبكة والتطبيق في الخلفية، ثم فتحه | لا قراءة في الخلفية؛ قراءة واحدة عند العودة إلى المقدمة | PENDING |
| D-48 | P2.5b-2 | بناء Android (ثم iOS) بعد إضافة `connectivity_plus 6.1.5` | البناء ينجح بـ AGP 8.11.1 بلا ترقية؛ لا إذن جديد في المتجر | PENDING (UNVERIFIED) |
| D-49 | P2.5c (§7X) | ترقية فوق قوائم v2 محفوظة بلا سجل وقت (نسخة `9d45059`)، ثم فتح القوائم الست offline، ثم أول تحديث بشبكة | القوائم تظهر offline كما قبل (السجل الغائب لا يخفي شيئاً)؛ بعد التحديث تعمل كالمعتاد؛ لا تغيّر مرئي | PENDING |
| D-50 | P2.5c | تقديم/تأخير ساعة الجهاز يدوياً ثم فتح القوائم offline وبشبكة | لا تعطّل ولا حجب ولا خروج؛ القوائم كما هي (الوقت داخلي فقط) | PENDING |
| D-51 | P3.1b (§7AA) | Samsung في الخلفية بقوائم محفوظة؛ تسجيل الدخول بالحساب نفسه على جهاز آخر؛ ثم إعادة Samsung إلى المقدمة وقائمة مفتوحة | لا تُستبدل القائمة بقائمة فارغة؛ يظهر حوار الإزاحة/الخروج المعتاد؛ بعد إعادة الدخول تبقى النسخة المحفوظة؛ وقائمة فارغة حقيقية لحساب جديد تظهر فارغة | PENDING |
| D-52 | P3.1a (§7AB) | حذف Request/Offer/Owner/Office/Broker/Watchman من قائمته؛ ثم حذف العنصر نفسه من جهاز ثانٍ بعد حذفه؛ ثم محاولة حذف بعد إزاحة الجلسة | الأول يُحذف برسالة النجاح؛ المحذوف مسبقاً يُعدّ محذوفاً بلا خطأ؛ بعد الإزاحة: رسالة الفشل القائمة ثم حوار الإزاحة/الخروج، والعنصر لا يُعلَّم محذوفاً | PENDING |
| D-53 | P3.1c (§7AC) | Home بأعداد ظاهرة؛ Samsung في الخلفية؛ دخول بالحساب نفسه على جهاز آخر؛ ثم إعادة Samsung إلى المقدمة (وسحب Home) | لا تصير الأعداد أصفاراً؛ يظهر حوار الإزاحة/الخروج المعتاد؛ بعد إعادة الدخول تظهر الأعداد المحفوظة ثم الحقيقية؛ حساب جديد فارغ يظهر بأصفار | PENDING |
| D-54 | P3.1d (§7AE) | حذف سجل من قائمة ثم قطع الشبكة فوراً؛ ثم إغلاق التطبيق وفتحه offline والقائمة نفسها؛ ثم إعادة الشبكة | السجل المحذوف لا يظهر offline ولا بعد إعادة التشغيل؛ بعد الشبكة تظهر قائمة الخادم كما هي؛ حذف رُفض (إزاحة/حساب آخر) لا يُخفي شيئاً | PENDING |
| D-55 | Q-1a + Q-1b (§7AV، §7AW) | قائمة Quotations مفتوحة تحت شاشة أخرى؛ تعديل/حذف Owner وOffer ثم العودة؛ ثم إنشاء وتعديل وحذف عرض سعر؛ ثم قطع الشبكة وتعديل عرض سعر | لا قراءة ولا toast بعد تعديل Owner/Offer؛ القائمة تتحدث بعد كل تعديل Quotation؛ عند الفشل تبقى القائمة وtoast مرة واحدة | PENDING (DEFERRED) |
| D-56 | Q-2b (§7AX) | فتح Quotations بشبكة ثم وضع الطيران وإعادة فتح الشاشة ثم إعادة تشغيل التطبيق داخل جلسة معتمدة؛ ثم استئناف مع عودة الشبكة؛ ثم حذف عرض سعر offline-بعد-حذف؛ ثم تبديل الحساب؛ ثم حذف حساب الاختبار؛ وزمن ظهور قائمة كبيرة | النسخة تظهر فوراً وتبقى مع toast مرة؛ تتحدث عند العودة؛ المحذوف لا يعود؛ الحساب الآخر لا يرى شيئاً؛ الحذف يمسح `cached_quotations_<uid>` ومفتاحه | PENDING (DEFERRED) |
| D-57 | Q-2c-1/1b (§7AY) | حفظ عرض سعر بـ PDF ثم فتحه offline؛ إعادة تشغيل وفتحه؛ ترقية فوق نسخة فيها PDF قديمة في الجذر ثم فتح القائمة بشبكة؛ نسخ احتياطي/نقل جهاز؛ إعادة تثبيت؛ تبديل الحساب؛ حذف حساب الاختبار؛ PDF كبير | يُفتح offline؛ الجذر لا يحوي PDF بعد الترحيل؛ `quotation_pdfs` غائب عن النسخة/الجهاز الجديد؛ بعد إعادة التثبيت يُنزَّل من جديد؛ الحساب الآخر لا يفتح؛ الحذف يمسح المجلد والمفتاح؛ زمن مقبول | PENDING (DEFERRED) |

---

## 7O) P2.2 — قراءة Offers من نسخة محلية مشفّرة — 2026-11-02 (CODE_PROVEN، غير مدمج)

**تصريح المالك:** «Implement P2.2: Encrypted Offers Offline Reading» — إعادة استخدام تصميم P2.1، بلا حزم، بلا كتابة offline، بلا تغيير وسائط/Plan/Share/backend، وبلا commit قبل موافقة.

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `0579b5b`، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0).

### التدقيق

- **مسار Offers:** `OffersListViewModel` ← `OfferService.getUserOffers()` ← `SupabaseCoreEntitiesService.getOffers()` = `_refreshedStream(_fetchOffers)` — نفس دورة Requests: قراءة كاملة، إعادة قراءة بعد كل تعديل، فشل القراءة الأولى يُغلق الـ stream.
- **الاكتمال (البند 10):** `_fetchOffers` استعلام واحد بلا `range`/`limit`/صفحات؛ تُسلَّم كل قراءة دفعةً واحدة أو تفشل كلها — لا تسليم جزئي. **حدّ معروف:** حدّ `max_rows` في PostgREST على مستوى المشروع (الافتراضي 1000) يقطع النتيجة بصمت؛ هذا يحدّ القائمة المعروضة نفسها اليوم، والنسخة لا تحفظ إلا ما عرضته الشاشة — لا تراجع عن السلوك الحالي. غير مُتحقَّق من قيمة `max_rows` على المشروع المستضاف (قراءة فقط لاحقاً إن لزم).
- **الوسائط:** صفوف قائمة Offers لا تحمل وسائط أصلاً (`_offerFromRow`: `mediaUrl: null`، `mediaUrls: []`، `mediaObjectIds` فارغ). البطاقات تصل للوسائط عبر `cachedOfferMedia` (كاش الوسائط على الجهاز) و`resolveOfferMedia` (روابط موقّعة عبر الـ Worker بعد التحقق). إذن النسخة لا تحتاج ولا تحفظ أي وسائط.

### التغيير

- **جديد `lib/src/services/encrypted_account_list_cache.dart`:** نواة P2.1 المُثبتة نُقلت كما هي إلى صنف عام `EncryptedAccountListCache<T>` (صندوق Hive مشفّر AES-256 لكل حساب، مفتاح لكل حساب في `flutter_secure_storage`، fail-closed بالكامل، عمليات متسلسلة لكل صندوق، `guardedOpen` الضيق من §7M-2، `forgetAccount`)، و`AccountCacheKeyStore`/`SecureAccountCacheKeyStore(prefix)`، والدالة `localFirstList<T>()` (منطق `watchUserRequestsLocalFirst` نفسه). **لا حذف أو إعادة توليد تلقائي لصندوق غير قابل للفك** (يبقى لـ P2.5).
- **`requests_local_cache.dart`:** أصبح غلافاً رفيعاً بالأسماء نفسها تماماً (`cached_requests_<uid>`، `requests_cache_key_v1_<uid>`، `requests_v1`، الصيغة نفسها) — لا ترحيل ولا تغيير بيانات. `RequestsCacheKeyStore` = typedef. `RequestService.watchUserRequestsLocalFirst` يستدعي `localFirstList`.
- **جديد `lib/src/services/offers_local_cache.dart`:** `cached_offers_<uid>`، مفتاح منفصل `offers_cache_key_v1_<uid>`، `offers_v1`. يحفظ حقول القائمة فقط (منها المناطق بالترتيب، الإحداثيات double/null، العنوان، status عبر `toFirestoreString`، التواريخ UTC ISO). **لا `mediaUrl` ولا `mediaUrls` ولا `mediaObjectIds` ولا روابط موقّعة ولا بايتات وسائط**؛ القراءة تعيدها فارغة كما قراءة الخادم للقائمة.
- **`OfferService`:** معاملان اختياريان (`localCache`، `currentUserId`؛ الافتراضي هوية `RepositoryProvider.authRepository.currentUserId` القانونية، أو null) + `watchUserOffersLocalFirst()`. **`getUserOffers()` بلا تغيير** (Home filters، Search، Favorites، Related Items تبقى على الخادم مباشرة).
- **`OffersListViewModel`:** سطر واحد → `watchUserOffersLocalFirst()`. الفرز (ترتيب الخادم `created_at desc` محفوظ كما هو في النسخة) والفلاتر والحذف بلا تغيير.
- **`DeletedAccountLocalDataCleaner`:** خطوة `const OffersLocalCache().forgetAccount(deletedUid)` (صندوق + مفتاح، للحساب المحذوف فقط).
- **بلا تغيير:** رفع الوسائط، تشغيل الفيديو، Plan، Share، Supabase/RLS/migrations، Worker/R2، Auth/Single Active Device، الواجهة.

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)

- **جديد `test/lists/offers_local_first_test.dart` — 21/21 PASS:** offline مع نسخة تبقى ولا تُمسح؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محل النسخة وتُحفظ، **والقائمة الفارغة تُحفظ فارغة**؛ فشل بعد قائمة يُبقيها؛ عزل الحسابات؛ Offers حساب آخر لا تُحفظ (فُحص النص المخزَّن نفسه بعد فك التشفير)؛ لا حفظ بعد تغيّر الحساب؛ لا عرض إن تغيّر الحساب أثناء القراءة؛ بلا حساب لا قراءة/حفظ؛ إغلاق الشاشة أثناء القراءة لا يطلب الخادم؛ كل الحقول تُسترجع حرفياً (lat=null، long سالب صغير، عربي، أسطر)؛ **لا رابط موقّع ولا media id ولا مفاتيح وسائط في النص المخزَّن**؛ مشفّر على القرص (لا هاتف/ملاحظة/عنوان/منطقة/معرّف حساب بنص واضح)، المفتاح 32 بايت في secure storage فقط، لا شيء في SharedPreferences، ويُقرأ بعد إعادة التشغيل؛ مفتاح Offers ≠ مفتاح Requests؛ مخزن آمن غير متاح → لا قراءة/كتابة/صندوق بلا تشفير؛ مفتاح مفقود/مفتاح آخر/صندوق تالف → لا قراءة، الملف لم يتغير بايت-بايت، لا مفتاح جديد؛ كتابتان أوليتان متزامنتان → مفتاح واحد؛ حذف الحساب يزيل صندوق ومفتاح Offers له فقط.
- **`requests_local_first_test.dart` — 27/27 PASS** بعد نقل النواة (يثبت أن P2.1 لم يتغير سلوكه)؛ اختبار «الصفوف الأجنبية لا تُحفظ» شُدّد ليفحص النص المخزَّن نفسه.
- **فحص الطفرات (3/3 التُقطت بعد التشديد؛ الملفات أُعيدت بايت-بايت):** (1) الشاشة على `getUserOffers()` → فشل 3 اختبارات offline؛ (2) حفظ `mediaUrl`/`mediaUrls` → فشل «لا وسائط»؛ (3) إزالة فلتر المالك عند الحفظ → **نجا أولاً** (فلتر القراءة أخفاه) → شُدّد الاختباران (Offers وRequests) لفحص النص المخزَّن → فشلا كما يجب.
- **مجموعات مرتبطة:** `test/lists/`، `test/offers/`، `test/plan_attachment/`، `r5a_requests`، `r5b_offers`، `r2_search_favorites`، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test` → **1037 PASS، 1 FAIL** — الفشل التاريخي نفسه فقط (`Deletion job migration and hosted validation script (setUpAll)`؛ ملف أُعيدت تسميته في `0d7fb17`)، لم يُصلَح.
- **Analyzer** (10 ملفات) → No issues. **Format:** الملفات الجديدة/المعدّلة نظيفة؛ في `offer_service.dart` انحراف تنسيق سابق موجود في HEAD (`removeMediaUrls`) لم يُلمس. **`git diff --check`:** نظيف. كل الملفات CRLF.

### ما يعمل offline وما يبقى online فقط

- **offline (داخل جلسة اعتمدها الخادم):** قائمة Requests وقائمة Offers (آخر نسخة من الخادم لهذا الحساب، مع الفلاتر والفرز)، وصور البطاقات المحفوظة مسبقاً في كاش الوسائط.
- **online فقط:** cold start (Retry بلا شبكة كما هو)، تفاصيل Offer/Request، روابط الوسائط الجديدة والفيديو، Home filters وأعداد Home الحية (الأعداد لها كاش R-02)، البحث، Favorites من الخادم، Related Items، كل الكتابات (لا كتابة offline ولا طابور مزامنة)، Owners/Offices/Brokers/Watchmen.

### الحدود

- **حدّ النتائج والاكتمال (مسجّل بطلب المالك):** النسخة المحلية لـ Requests وOffers = **آخر قائمة أعادها الخادم للشاشة، وليست بالضرورة كل سجلات الحساب.** قراءة القائمة استعلام واحد بلا صفحات، لكن حدّ `max_rows` في PostgREST على مستوى مشروع Supabase (الافتراضي 1000؛ القيمة المستضافة **غير مُتحقَّق منها**) يقطع النتيجة دون إشارة. إن تجاوز حساب هذا الحد فالشاشة اليوم تعرض أول N سجل (الأحدث بـ `created_at desc`)، والنسخة تحفظ الـ N نفسها فقط. لا يُدّعى أن النسخة كاملة؛ لا تراجع عن السلوك الحالي. المعالجة (صفحات أو فحص `count` مقابل طول القائمة قبل الحفظ) خارج P2.2 — مرشّح لـ P3/P4.
- لا مؤشر «نسخة محفوظة» على الشاشة (تغيير واجهة). لا إعادة محاولة تلقائية عند عودة الشبكة بعد فشل أول قراءة. فقدان المفتاح → نسخة الحساب معطّلة حتى حذفه (§7M-3، P2.5). AES-CBC + CRC كما في Hive، بلا MAC.

### الملفات (غير مدمجة)

- جديد: `lib/src/services/encrypted_account_list_cache.dart`، `lib/src/services/offers_local_cache.dart`، `test/lists/offers_local_first_test.dart`
- معدّل: `lib/src/services/requests_local_cache.dart`، `lib/src/services/ScreenServices/request_service.dart`، `lib/src/services/ScreenServices/offer_service.dart`، `lib/src/viewmodels/ListScreens/list_offers_viewmodel.dart`، `lib/src/services/deleted_account_local_data_cleaner.dart`، `test/lists/requests_local_first_test.dart`، وهذا الملف.

**الحالة:** P2.2 = **CODE_PROVEN / READY FOR COMMIT REVIEW** / Samsung D-13..D-17 **DEFERRED BY OWNER**. **STOP** — لا commit/push/merge/deploy؛ لا P2.3.

**توافق Requests مع `0579b5b` (فُحص قبل الـ commit):** بادئة الصندوق `cached_requests_`، بادئة المفتاح `requests_cache_key_v1_`، مفتاح القائمة `requests_v1`، الحقول الـ 19 وترميزها/فكّها، خيارات secure storage، `HiveAesCipher`، `crashRecovery: false`، ترميز المفتاح base64 وفحص 32 بايت — كلها مطابقة. لا ترحيل بيانات. يُودَع P2.2 في commit واحد بموافقة المالك (`feat(offline): add encrypted account-scoped Offers cache`).

---

## 7P) P2.3 — قراءة Owners من نسخة محلية مشفّرة — 2026-11-02 (CODE_PROVEN، غير مدمج)

**تصريح المالك:** «Implement P2.3: Encrypted Owners Offline Reading» — إعادة استخدام `encrypted_account_list_cache.dart` بغلاف رفيع، بلا تغيير في معمارية الكاش أو صيغ P2.1/P2.2، بلا commit قبل موافقة.

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `df1c45c` (دفعه المالك)، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0)، stashes = 2.

**التدقيق:** `OwnersListViewModel` ← `OwnerService.getUserOwners()` ← `getOwners()` = `_refreshedStream(_fetchOwners)`: استعلام واحد بلا صفحات، `order created_at desc`، كل قراءة تُسلَّم كاملة أو تفشل. صفوف القائمة بلا وسائط (`_ownerFromRow`: `mediaUrl: null`، `mediaUrls: []`). الملكية = `owner_id` (معرّف حساب Supabase) في حقل `userId`؛ معرّف سجل الـ Owner (`id`) منفصل. لا status للـ Owner؛ لا فلاتر في الـ VM غير الحذف.

**التغيير:**
- جديد `lib/src/services/owners_local_cache.dart`: غلاف رفيع على `EncryptedAccountListCache` — صندوق `cached_owners_<uid>`، مفتاح منفصل `owners_cache_key_v1_<uid>`، `owners_v1`. يحفظ حقول القائمة فقط: الاسم، الهاتف، رمز الدولة، أنواع العقارات، موقع العقار، الملاحظات، موقع/إحداثيات/عنوان الاستلام، `uploadedFileName` القديم (اسم ملف، ليس رابطاً)، التواريخ. **لا `mediaUrl`/`mediaUrls`، لا روابط موقّعة، لا بايتات، لا روابط Plan، لا tokens.** الهوية = `userId` (الحساب)، لا معرّف سجل الـ Owner.
- `OwnerService`: معاملان اختياريان (`localCache`، `currentUserId`؛ الافتراضي هوية `RepositoryProvider.authRepository.currentUserId`) + `watchUserOwnersLocalFirst()` عبر `localFirstList`. **`getUserOwners()` بلا تغيير** (Home filters/counts وFavorites).
- `OwnersListViewModel`: سطر واحد → `watchUserOwnersLocalFirst()`.
- `DeletedAccountLocalDataCleaner`: خطوة `const OwnersLocalCache().forgetAccount(deletedUid)`.
- **بلا تغيير:** النواة المشتركة، صيغ/أسماء P2.1 وP2.2، وسائط Owner، Plan، Share، الفيديو، backend، Auth/Single Active Device، الواجهة.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/owners_local_first_test.dart` — 22/22 PASS:** offline يُبقي النسخة ولا يمسحها؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محلها، **والفارغة تُحفظ فارغة**؛ فشل بعد قائمة يُبقيها؛ عزل الحسابات؛ سجلات حساب آخر لا تُحفظ (فُحص النص المخزَّن بعد فك التشفير)؛ **الكاش للحساب لا لمعرّف سجل الـ Owner** (سجل `id` = معرّف حساب Bob يبقى في صندوق Alice، ولا صندوق/مفتاح لـ Bob)؛ لا حفظ بعد تغيّر الحساب؛ لا عرض إن تغيّر الحساب أثناء القراءة؛ بلا حساب لا قراءة/حفظ؛ إغلاق الشاشة أثناء القراءة لا يطلب الخادم؛ **قراءة تنتهي بعد إغلاق الشاشة لا تحفظ شيئاً**؛ الحقول تُسترجع حرفياً بعد إعادة التشغيل (lat=null، عربي، اسم ملف قديم/null)؛ لا وسائط ولا `https://` ولا `token` في النص المخزَّن؛ مشفّر على القرص (لا اسم/هاتف/ملاحظة/موقع/معرّف حساب بنص واضح)، مفتاح 32 بايت في secure storage فقط، لا شيء في SharedPreferences؛ مفاتيح وصناديق Owners/Offers/Requests منفصلة (كتابة Owners لا تُنشئ مفاتيح غيره)؛ مخزن آمن غير متاح/مفتاح مفقود/مفتاح آخر/تلف → fail-closed والملف لم يتغير بايت-بايت؛ حذف الحساب يزيل صندوق ومفتاح Owners له فقط.
- **فحص الطفرات (2/2 التُقطت؛ أُعيدت الملفات بايت-بايت):** الشاشة على `getUserOwners()` → فشل 3 اختبارات offline؛ حفظ `mediaUrl` → فشل «لا وسائط». (فلتر المالك في النواة مُثبت بالطفرة في §7O.)
- **مجموعات مرتبطة:** `test/lists/` (تشمل Requests 27 وOffers 21 وentity list VMs وowners_list_view)، `test/owners/`، `r5c_owners_responsive`، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test` → **670 PASS، 3 FAIL، كلها قائمة قبل P2.3:**
  - التاريخي: `delete_account_test` — `Deletion job migration and hosted validation script (setUpAll)` (ملف أُعيدت تسميته في `0d7fb17`).
  - **جديد في السجل، قائم في `df1c45c`:** `r5c_owners_responsive_test` — «Owner swipe confirmation stays usable without deleting» (`Bad state: No element` عند `find.byType(Dismissible).first`) و«Owner list keeps items on failed refresh and shows local deletion presentation». **أُثبت أنه قائم قبل P2.3:** بإرجاع الملفات الثلاثة المعدّلة إلى نسخ HEAD (`git show HEAD:<file>`) فشل الاختباران نفسهما؛ ثم أُعيدت نسخ P2.3 بايت-بايت. لم يُشخَّص سببه (خارج النطاق) — يحتاج نقطة فرز منفصلة.
- **Analyzer** (5 ملفات) → No issues. **Format:** الملفات الجديدة/المعدّلة نظيفة؛ انحراف تنسيق سابق في `owner_service.dart` (`uploadCompletions`، موجود في HEAD) لم يُلمس. **`git diff --check`:** نظيف. كل الملفات CRLF.

**offline الآن (داخل جلسة اعتمدها الخادم):** قوائم Requests وOffers وOwners (آخر نسخة خادم لهذا الحساب) + صور البطاقات المحفوظة مسبقاً في كاش الوسائط. **online فقط:** cold start (Retry)، التفاصيل، روابط الوسائط الجديدة والفيديو، Plan، Home filters والأعداد الحية، البحث، Favorites، Related Items، Offices/Brokers/Watchmen، كل الكتابات.

**الحدود:** النسخة = آخر قائمة أعادها الخادم وليست بالضرورة كل سجلات الحساب (`max_rows`، §7O). لا مؤشر «نسخة محفوظة». لا إعادة محاولة تلقائية. فقدان المفتاح → معطّل حتى الحذف (P2.5).

**الملفات (غير مدمجة):** جديد `lib/src/services/owners_local_cache.dart`، `test/lists/owners_local_first_test.dart`؛ معدّل `lib/src/services/ScreenServices/owner_service.dart`، `lib/src/viewmodels/ListScreens/list_owners_viewmodel.dart`، `lib/src/services/deleted_account_local_data_cleaner.dart`، وهذا الملف.

**الحالة:** P2.3 = **CODE_PROVEN / READY FOR COMMIT REVIEW** / Samsung D-18..D-21 **DEFERRED BY OWNER**. **STOP** — لا commit/push/merge/deploy؛ لا P2.4.

### 7P-1) قبل الـ commit — الإخفاقات القائمة ونقطة متابعة

- **التحقق قبل الـ commit:** `perf/phase-1-startup-baseline` @ `df1c45c`، مطابق لـ `origin` (0/0)؛ النواة المشتركة وكل ملفات Requests وOffers (cache، service، view model) **مطابقة لـ HEAD بايت-بايت** (`git diff --quiet HEAD`) → صيغ P2.1/P2.2 وأسماء مفاتيحها وصناديقها لم تتغير. يُودَع P2.3 بموافقة المالك (`feat(offline): add encrypted account-scoped Owners cache`).
- **الإخفاقات الثلاثة في تشغيل المجموعات المرتبطة — FAIL، لا تُحسب ناجحة:**
  1. `test/account/delete_account_test.dart` — «Deletion job migration and hosted validation script (setUpAll)»: `PathNotFoundException` لـ `supabase/migrations/20260913000100_account_deletion_jobs.sql` (أُعيدت تسميته إلى `20260913175221_account_deletion_jobs.sql` في `0d7fb17`). **تاريخي**، قائم منذ ما قبل R-02.
  2. `test/responsive/r5c_owners_responsive_test.dart` — «Owner swipe confirmation stays usable without deleting»: `Bad state: No element` من `find.byType(Dismissible).first` (سطر 541 في الاختبار).
  3. `test/responsive/r5c_owners_responsive_test.dart` — «Owner list keeps items on failed refresh and shows local deletion presentation».
- **دليل أن (2) و(3) قائمان قبل P2.3:** بعد وضع نسخ HEAD (`df1c45c`) للملفات الثلاثة المعدّلة (`owner_service.dart`، `list_owners_viewmodel.dart`، `deleted_account_local_data_cleaner.dart`) عبر `git show HEAD:<file> > <file>` — والملفات الجديدة غير مستخدمة من كود HEAD — فشل الاختباران نفسهما (`+50 -2`)؛ ثم أُعيدت نسخ P2.3 وتحقق `cmp` من تطابقها بايت-بايت. وقبل ذلك فشل (2) أيضاً مع إرجاع سطر الـ view model وحده.
- **نقطة متابعة مركّزة — FU-OWNERS-R5C (OPEN، غير مُشخَّصة):** تشخيص سبب فشل اختبارَي `r5c_owners_responsive_test` (2) و(3) على `df1c45c`، وتحديد هل هو خلل في الواجهة أو في الاختبار، وإصلاحه في نقطة منفصلة بموافقة المالك. لا تُعدّل في P2.3. لم يُحدَّد بعدُ الـ commit الذي بدأ فيه الفشل.

---

## 7Q) P2.4a — قراءة Offices من نسخة محلية مشفّرة — 2026-11-02 (CODE_PROVEN، غير مدمج)

**قرار المالك (استمرارية):** خارطة Performance + Offline-First الأصلية سارية؛ نحن نُكمل P2 (Smart Local Caching)، **ولا يُدّعى أن Offline-First الكامل منجز.** التسلسل: P2.4a Offices ← P2.4b Brokers ← P2.4c Watchmen ← P2.5 موثوقية الكاش واستعادته ← P3/P4 أداء ← فحص جهاز مجمّع ← معمارية كتابة/مزامنة offline كاملة بموافقة منفصلة.

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `10f2f15` (دفعه المالك)، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0)، stashes = 2.

**التدقيق:** `OfficesListViewModel` ← `OfficeService.getUserOffices()` ← `getOffices()` = `_refreshedStream(_fetchOffices)`: استعلام واحد بلا صفحات، `order created_at desc`، يُسلَّم كاملاً أو يفشل. **لا وسائط للـ Offices أصلاً.** الملكية = `owner_id` في `userId` (**nullable** في `OfficeModel`)؛ `createdAt`/`updatedAt` nullable أيضاً. `OfficeService` كان بلا constructor.

**التغيير:**
- جديد `lib/src/services/offices_local_cache.dart`: غلاف رفيع على `EncryptedAccountListCache` — `cached_offices_<uid>`، مفتاح منفصل `offices_cache_key_v1_<uid>`، `offices_v1`. يحفظ حقول القائمة فقط (اسم المكتب، المدير، رمز الدولة، الهاتف، الموقع، الملاحظات، موقع/إحداثيات/عنوان الاستلام، التواريخ nullable). **سجل بلا حساب (`userId == null`) لا يُحفظ أبداً.**
- `OfficeService`: constructor بمعاملين اختياريين (`localCache`، `currentUserId`؛ الافتراضي هوية `RepositoryProvider.authRepository.currentUserId`) + `watchUserOfficesLocalFirst()` عبر `localFirstList`. **`getUserOffices()` بلا تغيير** (Home filters/counts).
- `OfficesListViewModel`: سطر واحد → `watchUserOfficesLocalFirst()`.
- `DeletedAccountLocalDataCleaner`: خطوة `const OfficesLocalCache().forgetAccount(deletedUid)`.
- **بلا تغيير:** النواة المشتركة، صيغ/أسماء Requests وOffers وOwners، backend، Auth/Single Active Device، الواجهة.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/offices_local_first_test.dart` — 21/21 PASS:** offline يُبقي النسخة ولا يمسحها؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محلها، **والفارغة تُحفظ فارغة**؛ فشل بعد قائمة يُبقيها؛ عزل الحسابات؛ **سجلات حساب آخر أو بلا حساب لا تُحفظ** (فُحص النص المخزَّن بعد فك التشفير)؛ لا حفظ بعد تغيّر الحساب؛ لا عرض إن تغيّر الحساب أثناء القراءة؛ بلا حساب لا قراءة/حفظ؛ إغلاق الشاشة أثناء القراءة لا يطلب الخادم؛ قراءة تنتهي بعد إغلاق الشاشة لا تحفظ؛ الحقول تُسترجع حرفياً بعد إعادة التشغيل (lat=null، **تواريخ null**، عربي)؛ نسخة تالفة = لا شيء؛ مشفّر على القرص (لا مدير/هاتف/ملاحظة/موقع/معرّف حساب بنص واضح)، مفتاح 32 بايت في secure storage فقط، لا شيء في SharedPreferences؛ **المفاتيح والصناديق الأربعة منفصلة** وكتابة Offices لا تُنشئ مفاتيح غيره؛ **كاش Owners الموجود لا يتأثر** بكتابة/قراءة Offices (مفتاحه ومحتواه كما هما)؛ مخزن آمن غير متاح/مفتاح مفقود/مفتاح آخر/تلف → fail-closed والملف لم يتغير بايت-بايت؛ حذف الحساب يزيل صندوق ومفتاح Offices له فقط.
- **فحص الطفرات (2/2 التُقطت؛ أُعيدت الملفات بايت-بايت):** الشاشة على `getUserOffices()` → فشل 3 اختبارات offline؛ حذف حقل من الترميز → فشل 3 اختبارات (الاسترجاع الحرفي وغيره).
- **مجموعات مرتبطة:** `test/lists/` (تشمل كاشات Requests 27 وOffers 21 وOwners 22 وentity list VMs)، `r5d_offices_responsive`، `r5c_owners_responsive` (للتأكد من FU فقط)، `test/home/`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test` → **539 PASS، 4 FAIL، كلها قائمة قبل P2.4a:**
  1. التاريخي: `delete_account_test` — `Deletion job migration and hosted validation script (setUpAll)`.
  2. و3. FU-OWNERS-R5C: «Owner swipe confirmation stays usable without deleting» و«Owner list keeps items on failed refresh and shows local deletion presentation» — لم تتغير.
  4. **جديد في السجل:** `r5d_offices_responsive_test` — «Office swipe cancel dialog 280.0x600.0 ar light 2.0x inset=EdgeInsets.zero keyboard=0.0» — `Bad state: No element` (النمط نفسه لفشل Owners swipe). **أُثبت أنه قائم في `10f2f15`:** بوضع نسخ HEAD للملفات الثلاثة المعدّلة (`git show HEAD:<file> > <file>`) فشل الاختبار نفسه (`+40 -1`)؛ ثم أُعيدت نسخ P2.4a وتحقق `cmp` من تطابقها بايت-بايت. يُضاف إلى **FU-OWNERS-R5C** (يُرجَّح سبب مشترك في اختبارات/واجهة السحب Dismissible عند 280×600 عربي 2×؛ غير مُشخَّص).
- **Analyzer** (5 ملفات) → No issues. **Format** (5 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. كل الملفات CRLF.

**offline الآن (داخل جلسة اعتمدها الخادم):** قوائم Requests وOffers وOwners وOffices + صور البطاقات المحفوظة في كاش الوسائط. **online فقط:** cold start (Retry)، التفاصيل، روابط الوسائط الجديدة والفيديو، Plan، Home filters والأعداد الحية، البحث، Favorites، Related Items، **Brokers وWatchmen**، كل الكتابات (لا outbox).

**الحدود:** النسخة = آخر قائمة أعادها الخادم وليست بالضرورة كل سجلات الحساب (`max_rows`، §7O). لا مؤشر «نسخة محفوظة». لا إعادة محاولة تلقائية. فقدان المفتاح → معطّل حتى الحذف (P2.5).

**الملفات (غير مدمجة):** جديد `lib/src/services/offices_local_cache.dart`، `test/lists/offices_local_first_test.dart`؛ معدّل `lib/src/services/ScreenServices/office_service.dart`، `lib/src/viewmodels/ListScreens/list_offices_viewmodel.dart`، `lib/src/services/deleted_account_local_data_cleaner.dart`، وهذا الملف.

**الحالة:** P2.4a = **CODE_PROVEN / READY FOR COMMIT REVIEW** / Samsung D-22..D-26 **DEFERRED BY OWNER**. **FU-OWNERS-R5C: OPEN** (3 اختبارات swipe: Owners ×2 + Offices ×1). **STOP** — لا commit/push/merge/deploy؛ لا Brokers/Watchmen.

---

## 7R) P2.4b — قراءة Brokers من نسخة محلية مشفّرة — 2026-11-02 (CODE_PROVEN، غير مدمج)

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `1abba8c` (دفعه المالك)، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0)، stashes = 2.

**التدقيق:** `BrokersListViewModel` ← `BrokerService.getUserBrokers()` ← `getBrokers()` = `_refreshedStream(_fetchBrokers)`: استعلام واحد بلا صفحات، `order created_at desc`، يُسلَّم كاملاً أو يفشل. **لا وسائط للـ Brokers.** الملكية = `owner_id` في `userId` (**nullable**)؛ `createdAt`/`updatedAt` nullable. **خاص بالـ Brokers:** الـ view model يستبدل `createdAt == null` بـ `DateTime.now()` للعرض فقط (`.map` على الـ stream). `BrokerService` كان بلا constructor.

**التغيير:**
- جديد `lib/src/services/brokers_local_cache.dart`: غلاف رفيع على `EncryptedAccountListCache` — `cached_brokers_<uid>`، مفتاح منفصل `brokers_cache_key_v1_<uid>`، `brokers_v1`. يحفظ حقول القائمة فقط (الاسم، رمز الدولة، الهاتف، الملاحظات، التواريخ nullable) **كما أعادها الخادم**. سجل بلا حساب لا يُحفظ.
- `BrokerService`: constructor بمعاملين اختياريين (`localCache`، `currentUserId`؛ الافتراضي هوية `RepositoryProvider.authRepository.currentUserId`) + `watchUserBrokersLocalFirst()` عبر `localFirstList`. **`getUserBrokers()` بلا تغيير** (Home filters/counts).
- `BrokersListViewModel`: يستمع إلى `watchUserBrokersLocalFirst()` مع **الإبقاء على تحويل العرض نفسه** (`createdAt == null` → now) فوقه — فالبديل يبقى للعرض ولا يُحفظ أبداً كبيانات.
- `DeletedAccountLocalDataCleaner`: خطوة `const BrokersLocalCache().forgetAccount(deletedUid)`.
- **بلا تغيير:** النواة المشتركة، صيغ/أسماء Requests وOffers وOwners وOffices، backend، Auth/Single Active Device، الواجهة.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/brokers_local_first_test.dart` — 22/22 PASS** (مبني على بنية اختبار Offices المُثبتة): offline يُبقي النسخة ولا يمسحها؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محلها، **والفارغة تُحفظ فارغة**؛ فشل بعد قائمة يُبقيها؛ عزل الحسابات؛ سجلات حساب آخر أو بلا حساب لا تُحفظ (فُحص النص المخزَّن)؛ لا حفظ بعد تغيّر الحساب؛ لا عرض إن تغيّر الحساب أثناء القراءة؛ بلا حساب لا قراءة/حفظ؛ إغلاق الشاشة أثناء القراءة لا يطلب الخادم؛ قراءة تنتهي بعد إغلاق الشاشة لا تحفظ؛ الحقول تُسترجع حرفياً بعد إعادة التشغيل (عربي، تواريخ null)؛ **التاريخ المفقود من الخادم يبقى null في النسخة (`"createdAt":null` في النص المخزَّن) بينما تعرض الشاشة البديل**؛ نسخة تالفة = لا شيء؛ مشفّر على القرص (لا اسم/هاتف/ملاحظة/معرّف حساب بنص واضح)، مفتاح 32 بايت في secure storage فقط، لا شيء في SharedPreferences؛ **المفاتيح والصناديق الخمسة منفصلة** وكتابة Brokers لا تُنشئ مفاتيح غيره؛ كاش Owners الموجود لا يتأثر؛ مخزن آمن غير متاح/مفتاح مفقود/مفتاح آخر/تلف → fail-closed والملف لم يتغير بايت-بايت؛ حذف الحساب يزيل صندوق ومفتاح Brokers له فقط.
- **فحص الطفرات (2/2 التُقطت؛ أُعيدت الملفات بايت-بايت):** الشاشة على `getUserBrokers()` → فشل 4 اختبارات؛ حفظ تاريخ بديل (`createdAt ?? now`) → فشل «الاسترجاع الحرفي» و«التاريخ المفقود يبقى مفقوداً».
- **مجموعات مرتبطة:** `test/lists/` (تشمل كاشات Requests وOffers وOwners وOffices وentity list VMs)، `r5d_brokers_responsive`، `r5d_offices_responsive` و`r5c_owners_responsive` (للتأكد من FU فقط)، `test/home/`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test` → **601 PASS، 5 FAIL، كلها قائمة قبل P2.4b:**
  1. التاريخي: `delete_account_test` — `Deletion job migration and hosted validation script (setUpAll)`.
  2.–4. FU-OWNERS-R5C (بلا تغيير): Owners swipe confirmation، Owner list keeps items on failed refresh، Office swipe cancel dialog 280×600 ar 2.0x.
  5. **جديد في السجل:** `r5d_brokers_responsive_test` — «Broker swipe cancel dialog 280.0x600.0 ar light 2.0x inset=EdgeInsets.zero keyboard=0.0» — `Bad state: No element`. **أُثبت أنه قائم في `1abba8c`:** بوضع نسخ HEAD للملفات الثلاثة المعدّلة فشل الاختبار نفسه (`+40 -1`، `Bad state: No element`)؛ ثم أُعيدت نسخ P2.4b وتحقق `cmp` من تطابقها بايت-بايت. **أُضيف إلى FU-OWNERS-R5C** (الآن 4 اختبارات swipe: Owners ×2، Offices ×1، Brokers ×1 — يُرجَّح سبب مشترك في سحب Dismissible عند 280×600 عربي 2×؛ غير مُشخَّص).
- **Analyzer** (5 ملفات) → No issues. **Format** (5 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. كل الملفات CRLF.

**offline الآن (داخل جلسة اعتمدها الخادم):** قوائم Requests وOffers وOwners وOffices وBrokers + صور البطاقات المحفوظة في كاش الوسائط. **online فقط:** cold start (Retry)، التفاصيل، روابط الوسائط الجديدة والفيديو، Plan، Home filters والأعداد الحية، البحث، Favorites، Related Items، **Watchmen**، كل الكتابات (لا outbox).

**الحدود:** النسخة = آخر قائمة أعادها الخادم وليست بالضرورة كل سجلات الحساب (`max_rows`، §7O). لا مؤشر «نسخة محفوظة». لا إعادة محاولة تلقائية. فقدان المفتاح → معطّل حتى الحذف (P2.5).

**الملفات (غير مدمجة):** جديد `lib/src/services/brokers_local_cache.dart`، `test/lists/brokers_local_first_test.dart`؛ معدّل `lib/src/services/ScreenServices/broker_service.dart`، `lib/src/viewmodels/ListScreens/list_brokers_viewmodel.dart`، `lib/src/services/deleted_account_local_data_cleaner.dart`، وهذا الملف.

**الحالة:** P2.4b = **CODE_PROVEN / READY FOR COMMIT REVIEW** / Samsung D-27..D-30 **DEFERRED BY OWNER**. **FU-OWNERS-R5C: OPEN** (4 اختبارات swipe). التاريخي (Delete Account migration-file): OPEN. **STOP** — لا commit/push/merge/deploy؛ لا Watchmen ولا P2.5.

---

## 7S) P2.4c — قراءة Watchmen من نسخة محلية مشفّرة — 2026-11-02 (CODE_PROVEN، غير مدمج) — آخر قوائم الكيانات

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `978b2b9` (دفعه المالك)، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0)، stashes = 2.

**التدقيق:** `WatchmenListViewModel` ← `WatchmenService.getUserWatchmen()` ← `getWatchmen()` = `_refreshedStream(_fetchWatchmen)`: استعلام واحد بلا صفحات، `order created_at desc`، يُسلَّم كاملاً أو يفشل. **لا وسائط للـ Watchmen.** الملكية = `owner_id` في `userId` (**nullable**)؛ `createdAt`/`updatedAt` والإحداثيات nullable. لا تحويل عرض في الـ view model. `WatchmenService` كان بلا constructor.

**التغيير:**
- جديد `lib/src/services/watchmen_local_cache.dart`: غلاف رفيع على `EncryptedAccountListCache` — `cached_watchmen_<uid>`، مفتاح منفصل `watchmen_cache_key_v1_<uid>`، عقد قائمة مُرقَّم `watchmen_v1`. يحفظ حقول القائمة فقط **كما أعادها الخادم** (الاسم، رمز الدولة، الهاتف، اسم المبنى، الملاحظات، موقع المبنى، موقع/إحداثيات/عنوان الاستلام، التواريخ nullable) — **لا قيم بديلة دائمة**. سجل بلا حساب لا يُحفظ.
- `WatchmenService`: constructor بمعاملين اختياريين (`localCache`، `currentUserId`؛ الافتراضي هوية `RepositoryProvider.authRepository.currentUserId`) + `watchUserWatchmenLocalFirst()` عبر `localFirstList`. **`getUserWatchmen()` بلا تغيير** (Home filters/counts).
- `WatchmenListViewModel`: سطر واحد → `watchUserWatchmenLocalFirst()`.
- `DeletedAccountLocalDataCleaner`: خطوة `const WatchmenLocalCache().forgetAccount(deletedUid)`.
- **بلا تغيير:** النواة المشتركة، صيغ/أسماء/مفاتيح Requests وOffers وOwners وOffices وBrokers، backend، Auth/Single Active Device، الواجهة. لا حذف لبيانات قديمة.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/watchmen_local_first_test.dart` — 21/21 PASS** (مبني على بنية اختبار Offices المُثبتة): offline يُبقي النسخة ولا يمسحها؛ بلا نسخة → خطأ التحميل كما كان؛ قائمة الخادم تحل محلها، **والفارغة تُحفظ فارغة**؛ فشل بعد قائمة يُبقيها؛ عزل الحسابات؛ سجلات حساب آخر أو بلا حساب لا تُحفظ (فُحص النص المخزَّن)؛ لا حفظ بعد تغيّر الحساب؛ لا عرض إن تغيّر الحساب أثناء القراءة؛ بلا حساب (sign-out) لا قراءة/حفظ؛ إغلاق الشاشة أثناء القراءة لا يطلب الخادم؛ قراءة تنتهي بعد إغلاق الشاشة لا تحفظ؛ الحقول تُسترجع حرفياً بعد إعادة التشغيل (عربي، lat=null، **تواريخ null تُخزَّن `null` لا بديلاً**)؛ نسخة تالفة = لا شيء؛ مشفّر على القرص (لا اسم/هاتف/ملاحظة/موقع/معرّف حساب بنص واضح)، مفتاح 32 بايت في secure storage فقط، لا شيء في SharedPreferences؛ **المفاتيح والصناديق الستة منفصلة** وكتابة Watchmen لا تُنشئ مفاتيح غيره؛ كاش Owners الموجود لا يتأثر؛ مخزن آمن غير متاح/مفتاح مفقود/مفتاح آخر/تلف → fail-closed والملف لم يتغير بايت-بايت؛ حذف الحساب يزيل صندوق ومفتاح Watchmen له فقط.
- **فحص الطفرات (2/2 التُقطت؛ أُعيدت الملفات بايت-بايت):** الشاشة على `getUserWatchmen()` → فشل 3 اختبارات offline؛ حفظ تاريخ بديل (`createdAt ?? now`) → فشل «الاسترجاع الحرفي».
- **مجموعات مرتبطة:** `test/lists/` (الكاشات الست وentity list VMs)، `r5d_watchmen_responsive`، و`r5d_brokers`/`r5d_offices`/`r5c_owners` (للتأكد من FU)، `test/home/`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test` → **662 PASS، 6 FAIL، كلها قائمة قبل P2.4c:**
  1. التاريخي: `delete_account_test` — `Deletion job migration and hosted validation script (setUpAll)`.
  2.–5. FU-OWNERS-R5C (بلا تغيير): Owner swipe confirmation، Owner list keeps items on failed refresh، Office swipe cancel dialog، Broker swipe cancel dialog (280×600 ar 2.0x).
  6. **جديد في السجل:** `r5d_watchmen_responsive_test` — «Watchmen swipe cancel dialog 280.0x600.0 ar light 2.0x inset=EdgeInsets.zero keyboard=0.0» — `Bad state: No element`. **أُثبت أنه قائم في `978b2b9`:** بوضع نسخ HEAD للملفات الثلاثة المعدّلة فشل الاختبار نفسه (`+40 -1`، `Bad state: No element`)؛ ثم أُعيدت نسخ P2.4c وتحقق `cmp` من تطابقها. **أُضيف إلى FU-OWNERS-R5C** (الآن **5** اختبارات swipe: Owners ×2، Offices، Brokers، Watchmen — نمط واحد عند 280×600 عربي 2×؛ غير مُشخَّص؛ لم تُعدَّل توقعات أي اختبار).
- **Analyzer** (5 ملفات) → No issues. **Format** (5 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. كل الملفات CRLF.

**offline الآن (داخل جلسة اعتمدها الخادم):** قوائم الكيانات الست — Requests وOffers وOwners وOffices وBrokers وWatchmen — + صور البطاقات المحفوظة في كاش الوسائط. **online فقط:** cold start (Retry)، شاشات التفاصيل، روابط الوسائط الجديدة والفيديو، Plan، Home filters والأعداد الحية (للأعداد كاش R-02)، البحث، Favorites، Related Items، Toolkit cloud، كل الكتابات (لا outbox ولا مزامنة). **Offline-First الكامل غير منجز.**

**حدود الكاش (معروفة):**
- **الاكتمال:** النسخة = آخر قائمة أعادها الخادم، ليست بالضرورة كل سجلات الحساب (`max_rows`، §7O).
- **الحداثة:** لا مؤشر «نسخة محفوظة»؛ لا إعادة محاولة عند عودة الشبكة بعد فشل أول قراءة؛ لا عمر/TTL للنسخة.
- **الأمان:** AES-CBC + CRC (Hive) بلا MAC؛ يحمي الملف خارج التطبيق لا جهازاً مخترقاً أثناء التشغيل. النسخ تبقى بعد logout (معزولة) وتُزال عند حذف الحساب.
- **فقدان المفتاح:** صندوق موجود بلا مفتاح/بمفتاح آخر/تالف → معطّل (لا قراءة/لا كتابة) حتى حذف الحساب؛ لا حذف أو إعادة توليد تلقائي.

**الملفات (غير مدمجة):** جديد `lib/src/services/watchmen_local_cache.dart`، `test/lists/watchmen_local_first_test.dart`؛ معدّل `lib/src/services/ScreenServices/watchmen_service.dart`، `lib/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart`، `lib/src/services/deleted_account_local_data_cleaner.dart`، وهذا الملف.

**الحالة:** P2.4c = **CODE_PROVEN / READY FOR COMMIT REVIEW** / Samsung D-31..D-35 **DEFERRED BY OWNER**. **FU-OWNERS-R5C: OPEN** (5 اختبارات swipe). التاريخي (Delete Account migration-file): OPEN. **STOP** — لا commit/push/merge/deploy؛ لا P2.5 تلقائياً.

### النقطة التالية (بموافقة منفصلة): P2.5 — موثوقية الكاش واستعادته

النطاق المقترح (من حدود §7M-3، §7O، §7S): (1) **استعادة فقدان المفتاح** — قرار صريح من المالك بين حذف الصندوق غير القابل للفك وبدء نسخة جديدة أو إبقائه معطّلاً، بلا استبدال صامت؛ (2) **سياسة النسخ الاحتياطي** — استبعاد صناديق `cached_*` (وقواعد `dataExtractionRules`/`fullBackupContent`) من Android Auto Backup كي لا تُستعاد بلا مفتاحها؛ (3) **البيانات القديمة** — عمر النسخة/TTL ووسم «محفوظة» (أي عنصر واجهة يحتاج موافقة المالك)؛ (4) **التحديث عند عودة الشبكة** — إعادة قراءة بعد فشل أول قراءة دون تكرار الطلبات؛ (5) **الاكتمال** — فحص `count` مقابل طول القائمة أو صفحات قبل اعتبار النسخة كاملة؛ (6) **مراجعة موثوقية مركّزة للنواة المشتركة** (`encrypted_account_list_cache.dart`). لا تبدأ دون موافقة.

---

## 7T) P2.5a — مراجعة أمان الكاش المشفّر والنسخ الاحتياطي والاستعادة — 2026-11-02 (REVIEWED، بلا تغيير كود)

**Git قبل البدء:** `perf/phase-1-startup-baseline` @ `7ad15cc` (دفعه المالك)، شجرة نظيفة، مطابق لـ `origin` بعد fetch (0/0)، stashes = 2. **بعد المراجعة:** لا تغيير في أي ملف كود أو اختبار؛ هذا الملف فقط.

### نتائج مُتحقَّق منها (VERIFIED)

- **V-1 — التشفير غير مُصادَق، والتعديل المتعمّد يمرّ (VERIFIED_TEST، تجربة مؤقتة حُذفت):** إطار Hive المشفّر = `[length u32][key][IV 16 + AES-256-CBC/PKCS7][CRC32]`؛ الـ CRC32 يُحسب على الإطار بقيمة ابتدائية مشتقة من المفتاح (`Crc32(sha256(key))`). **CRC32 دالة affine**: `crc(m⊕Δ) = crc(m) ⊕ crc₀(Δ) ⊕ crc₀(0ⁿ)` — يُحسب التصحيح **بلا المفتاح**. و**CBC قابل للتلاعب (malleable)**: تعديل بايت في الـ IV يقلب البايت المقابل في أول كتلة نص صريح بدقة. **التجربة:** كتابة `RequestsLocalCache` بسجل `id: 'a1'`، ثم تعديل بايت واحد في الـ IV (`'a'→'z'`) وتصحيح الـ CRC بلا مفتاح → `cache.read` أعاد **`[z1]`** (قُبل التعديل). **الضابط:** التعديل نفسه بلا تصحيح CRC → `null` (رُفض). **الخلاصة:** Hive يعطي **سرّية فقط**؛ الـ CRC يكشف التلف العرضي لا التلاعب المتعمّد. **لا يُدّعى «تشفير مُصادَق».**
  - **الأثر الفعلي:** يتطلب قدرة كتابة على تخزين التطبيق الخاص (جهاز rooted، أو نسخة احتياطية مُعدَّلة تُستعاد). النتيجة: عرض قائمة offline معدّلة **حتى أول قراءة ناجحة من الخادم** (تستبدلها). فلتر المالك يمنع حقن سجلات حساب آخر؛ الكاش لا يمنح صلاحيات ولا يكتب للخادم. **الخطورة: منخفضة–متوسطة (سلامة العرض offline).**
- **V-2 — صناديق الكاش تُنسخ احتياطياً، ومفاتيحها لا تعود (VERIFIED_SOURCE + VERIFIED_TEST للفرع):**
  - `AndroidManifest.xml`: `allowBackup` غير مُعطَّل (Auto Backup مفعّل)؛ `backup_rules.xml` و`data_extraction_rules.xml` تستثني **فقط** `offer_media`، `offer_media_uploads.*`، `scanner`، `combine_pdfs`، `image_to_pdf`، `signature_pdfs`، `mlkit_docscan_ui_client`. **صناديق `app_flutter/cached_{requests,offers,owners,offices,brokers,watchmen}_<uid>.hive` غير مستثناة** → تذهب إلى النسخ السحابي ونقل الجهاز.
  - `flutter_secure_storage` 10.3.1 (Android): `resetOnError` **افتراضياً `true`**؛ عند فشل فك قيمة (مثلاً استعادة على جهاز آخر حيث مفتاح Android Keystore لا ينتقل) **يحذف القيمة ويعيد `null`** (من مصدر `FlutterSecureStorage.java`، `handleStorageError`/`deleteAllDataAndKeys`).
  - مع قاعدة النواة «صندوق موجود بلا مفتاح → لا قراءة ولا كتابة ولا مفتاح جديد» (مُختبرة في الكاشات الست): **بعد استعادة Android أو نقل جهاز، كاش كل حساب يصبح معطّلاً دائماً** (حتى حذف الحساب)، ويبقى نص مشفّر غير قابل للفك على القرص. **لم يُنفَّذ على جهاز** (Samsung مؤجّل) — السلسلة مُثبتة من المصدر والاختبارات.
  - ملاحظة جانبية (سلوك قائم، خارج النطاق): جلسة Supabase في التخزين نفسه تُفقد كذلك بعد الاستعادة (تسجيل دخول جديد) — لم يُغيَّر.
- **V-3 — دورة الحياة سليمة (VERIFIED_TEST):** الكاشات الست + `delete_account_test` → **167 PASS، 1 FAIL** (التاريخي فقط). logout لا يمسّ الكاشات (بالتصميم؛ معزولة ومشفّرة)؛ تبديل الحساب/sign-out/مفتاح مفقود/مفتاح آخر/غير متاح/تلف → fail-closed؛ حذف الحساب يزيل `cached_*_<uid>` ومفاتيحه المسبوقة فقط؛ **لا `deleteAll` لـ secure storage في أي مكان من `lib/`**؛ Toolkit والوسائط لا تُمسّ.

### مخاطر نظرية (غير مُتحقَّق منها)

- **T-1:** إبطال Keystore على بعض أجهزة Samsung (تغيير قفل الشاشة/تحديثات) → السلوك نفسه كـ V-2. يحتاج جهازاً.
- **T-2:** iOS: المفاتيح بـ `first_unlock` (قابلة للنقل) تنتقل مع النسخ المشفّرة/ترحيل الجهاز → متّسقة؛ نسخة iTunes غير مشفّرة لا تنقل Keychain → حالة V-2 نفسها. لم يُختبر iOS.
- **T-3:** صناديق Hive غير الكسولة تُبقي القيم المفكوكة في الذاكرة حتى إغلاقها؛ بعد logout يبقى صندوق الحساب السابق مفتوحاً حتى إعادة تشغيل التطبيق (لا يُقرأ إلا عبر API الكاش بمعرّف ذلك الحساب).
- **T-4:** مثيلا secure storage (جلسة Supabase ومفاتيح الكاش) يتشاركان ملف التخزين؛ `resetOnError` في أيٍّ منهما قد يمسح مفاتيح الكاش أيضاً عند فشل التشفير.

### القرارات المطلوبة من المالك (حدود موافقة — لم يُنفَّذ شيء منها)

- **D-1 — سياسة النسخ الاحتياطي:** قواعد Android لا تدعم wildcards، وأسماء الصناديق تحتوي `uid`. الخيارات: (أ) نقل الصناديق الجديدة إلى مجلد فرعي (مثلاً `app_flutter/offline_lists/` عبر `Hive.openBox(path:)`) واستثناؤه في القاعدتين — **تغيير موقع** + ما يُفعل بالصناديق القديمة في الجذر؛ (ب) تخزينها في مجلد لا يُنسخ (cache/no-backup) مع قبول أن النظام قد يحذفها عند نقص المساحة (مقبول لكاش مشتق من الخادم)؛ (ج) إبقاء الوضع الحالي وقبول V-2. **أي خيار يغيّر manifest أو الموقع يحتاج موافقة.**
- **D-2 — سياسة الاستعادة لصندوق غير قابل للفك** (مفتاح مفقود/مفتاح آخر/تلف): لأن المحتوى **مشتق من الخادم وللقراءة فقط**، الاسترداد الآمن المقترح = **حذف صريح** لذلك الصندوق (مع سجل debug بفئة ثابتة) ثم مفتاح جديد عند أول قائمة ناجحة من الخادم، **للحساب نفسه فقط وبعد اعتماد الخادم للجلسة**. البديل: الإبقاء على التعطيل الحالي. **حذف = قرار المالك.**
- **D-3 — تشفير مُصادَق (AEAD):** `crypto` و`pointycastle` موجودتان **كاعتماديات انتقالية فقط** (لا مباشرة). خيار متوافق للخلف: عقد قائمة جديد `*_v2` (encrypt-then-MAC بـ HMAC-SHA256، أو AES-GCM) داخل الصندوق نفسه؛ القراءة تقبل `v1` إن لم يوجد `v2`، والكتابة تكتب `v2` فقط وتحذف `v1` من الصندوق نفسه. **يحتاج: إضافة اعتمادية مباشرة + تغيير الصيغة + موافقة.** البديل: قبول V-1 (الأثر محدود بعرض offline حتى أول تحديث).
- (اختياري) **D-4:** `resetOnError: false` لمخزن مفاتيح الكاش وحده — فائدته محدودة بسبب T-4 (الملف مشترك)؛ لا يُوصى به منفرداً.

### الحالة و NOW / NEXT / STOP

- **P2.5a:** REVIEWED — V-1 وV-2 **مُتحقَّق منهما**؛ لا تغيير كود (كل إصلاح فعلي يعبر حدّ موافقة: صيغة/موقع/حذف/اعتمادية/manifest). Samsung (V-2 على جهاز، T-1) **DEFERRED BY OWNER** — يُضاف للقائمة المجمّعة عند قرار D-1/D-2.
- **NOW:** المالك يقرر D-1 وD-2 وD-3.
- **NEXT:** تنفيذ القرارات المعتمدة فقط، بنقطة منفصلة (P2.5a-impl) مع اختبارات؛ ثم P2.5b (الحداثة/TTL، التحديث عند عودة الشبكة، الاكتمال).
- **STOP:** لا تغيير صيغ/مفاتيح/مواقع، لا حذف ملفات كاش، لا manifest، لا اعتماديات، لا commit. **FU-OWNERS-R5C** (5 اختبارات swipe) **OPEN**؛ التاريخي (Delete Account migration-file) **OPEN**.

### 7T-1) تنفيذ D-1a + D-2 المعتمدَين بشروط المالك — 2026-11-02 (CODE_PROVEN، غير مدمج)

**موافقة المالك:** D-1a (نقل التخزين واستثناؤه من النسخ) وD-2 (استرداد مشروط) — بشروط سلامة البيانات. **D-3 غير معتمد:** ضعف AES-CBC + CRC32 (V-1) **يبقى OPEN**؛ لا يُدّعى تشفير مُصادَق؛ لم يُغيَّر أي خوارزمية أو اعتمادية أو صيغة مخزَّنة.

**Git قبل البدء:** `7ad15cc`، مطابق لـ `origin`، نظيف، stashes = 2.

**D-1a — التنفيذ (`encrypted_account_list_cache.dart`):**
- كل صناديق القوائم الست تُفتح الآن في `<documents>/offline_lists/` (`EncryptedAccountListCache.directoryName`) عبر `Hive.openBox(path:)`؛ `<documents>` = `getApplicationDocumentsDirectory()` (على Android = `<data>/app_flutter`، وهو home الذي يضبطه `Hive.initFlutter()` في `main.dart`، كما يستخدمه طابور رفع الوسائط). **الأسماء المنطقية، المفاتيح، والصيغ لم تتغير.**
- **ترحيل متوافق وآمن من الانقطاع** (`_moveEarlierBox`، مرة عند كل استخدام داخل طابور الصندوق): إن وُجد `<documents>/<box>.hive` القديم ولم يكن الصندوق مفتوحاً → نسخ إلى `offline_lists/<box>.hive.moving` → مقارنة بايت-بايت (إن اختلف: تُحذف النسخة ويبقى القديم) → `rename` ذري إلى `<box>.hive` → **لا يُحذف القديم إلا إن كان مطابقاً بايت-بايت للمنقول** (ومعه `.lock` القديم). الانقطاع في أي خطوة يُستكمل أو يُعاد في الاستخدام التالي. **صندوق مفتوح لا يُنقل أبداً.** حالة نادرة (انقطاع بعد rename ثم كتابة لاحقة): يُستخدم المنقول ويبقى القديم بلا مساس (يُسجَّل).
- **قواعد النسخ (Android):** أُضيف `<exclude domain="root" path="app_flutter/offline_lists" />` إلى `backup_rules.xml` (Android ≤11) وإلى قسمَي `cloud-backup` و`device-transfer` في `data_extraction_rules.xml` (Android 12+)، مع تعليق السبب. **كل الاستثناءات السابقة باقية**؛ لا تغيير في `AndroidManifest.xml`. الملفان صالحان كـ XML (فُحصا بـ parser): 9 و18 استثناءً على التوالي.

**D-2 — التنفيذ (`write` + `_recover`):**
- **متى فقط:** صندوق موجود لكنه غير قابل للقراءة (مفتاح مفقود — الـ key store أجاب `null` — أو فشل الفك بـ `HiveError`: مفتاح آخر/تلف) **و** الكتابة آتية من `localFirstList` بعد **قائمة ناجحة من الخادم** للحساب نفسه، **ولا يزال هو المسجّل** (`mayRecover: () => currentUserId() == uid`). القراءة لا تسترد أبداً؛ كتابة مباشرة بلا `mayRecover` لا تسترد؛ **offline لا استرداد** (لا قائمة ناجحة).
- **لا استرداد على عطل عابر:** أي استثناء من الـ key store أو نظام الملفات يوقف الكتابة دون لمس شيء؛ و**تأكيد ثانٍ** قبل الاستبدال: الـ key store يجب أن يعطي الإجابة نفسها (لا مفتاح، أو المفتاح نفسه)، والصندوق لا يزال موجوداً، ومع مفتاح يجب أن يفشل الفك مرة ثانية (إن انفتح الآن → كتابة عادية، لا استبدال).
- **الإجراء المُتحقَّق منه:** (1) بناء البديل بمفتاح جديد في `offline_lists/.recovery/` وقراءته للتحقق؛ (2) حفظ المفتاح الجديد وقراءته للتحقق — فشل → حذف البديل، والأصل بلا مساس؛ (3) نقل الملف غير القابل للفك جانباً إلى `.recovery/<box>.hive.unreadable` (**لا حذف**)؛ (4) نقل البديل مكانه — فشل → إعادة الأصل؛ (5) فتح الصندوق بالمفتاح الجديد والتحقق من المحتوى؛ **(6) عندها فقط** حذف النسخة الجانبية. أي فشل يترك البيانات مشفّرة ومحمية مع سجل debug بفئة ثابتة. للحساب ونوع القائمة المعنيين فقط.
- **Delete Account** (`forgetAccount`): يحذف الصندوق في `offline_lists`، والصندوق القديم في الجذر إن بقي، و`.moving`، وبقايا `.recovery` لذلك الحساب، ثم المفتاح. لا شيء آخر.
- **لم يُمسّ:** Toolkit، الوسائط، طوابير الرفع، المسودات، المفضلة، SharedPreferences، الجلسة.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/offline_lists_storage_test.dart` — 25/25 PASS (3 تشغيلات):** صندوق جديد في `offline_lists` لا الجذر؛ **الكاشات الست كلها** في `offline_lists`؛ نقل صندوق قديم بالمفتاح نفسه وبايتات مطابقة ويُقرأ بعد إعادة التشغيل؛ نقل مقطوع بعد النسخ (نسخة جزئية `.moving`) يُستأنف؛ نقل مقطوع قبل حذف القديم يُستكمل؛ نسختان مختلفتان → المنقول مستخدم والقديم بلا مساس؛ **صندوق مفتوح لا يُنقل**؛ قواعد Android ≤11 و12+ (cloud + transfer) تستثني المجلد مرة واحدة مع بقاء الاستثناءات الثمانية السابقة؛ الـ manifest يشير إلى الملفين؛ المسار المستثنى = المجلد الفعلي للصناديق؛ **استرداد** مفتاح مفقود/مفتاح آخر/تلف بعد قائمة خادم ناجحة؛ قائمة خادم فارغة → استرداد إلى قائمة فارغة؛ الاسترداد يمسّ ذلك الحساب وتلك القائمة فقط (صندوق ومفتاح Bob، ومفتاح Owners لـ Alice بلا تغيير)؛ **لا استرداد**: offline، عند القراءة، كتابة بلا قائمة خادم، بعد تغيّر الحساب، عند عطل عابر في الـ key store (عند كتابة المفتاح أو التأكيد الثاني — ثم يتم الاسترداد عند توفر التخزين)، حين لا يثبت التأكيد الثاني، وحين يفشل حفظ المفتاح الجديد (الأصل بلا مساس ولا نسخة جانبية)؛ Delete Account بعد النقل يزيل المنقول والقديم وبقايا `.recovery` والمفتاح لذلك الحساب فقط؛ ملفات غير ذات صلة (طابور الوسائط، صندوق المفضلة، صورة Offer، PDF توقيع، مسودة image-to-pdf) لا تُمسّ عبر النقل والاسترداد والحذف.
- **فحص الطفرات (4/4 التُقطت؛ الملف أُعيد بايت-بايت):** إزالة شرط «قائمة خادم مُتحقَّق منها» → فشل اختبارَي «لا استرداد»؛ إزالة التأكيد الثاني → فشل اختباره؛ حذف القديم دون تطابق → فشل «نسختان مختلفتان»؛ نقل صندوق مفتوح → فشل «لا يُنقل».
- **الكاشات الست:** اختباراتها حُدِّثت لمسار `offline_lists` (جذر التخزين + `path:` فقط) → **134/134 PASS**.
- **مجموعات مرتبطة:** `test/lists/`، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test`، وشاشات القوائم الست (`r5a`/`r5b`/`r5c`/`r5d`×3) → **842 PASS، 6 FAIL — المعروفة فقط:** التاريخي (Delete Account migration-file) + FU-OWNERS-R5C الخمسة. لا فشل جديد.
- **Analyzer** (9 ملفات) → No issues. **Format** (8 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. كل الملفات CRLF.

**المخاطر المتبقية:**
- **V-1 (D-3) OPEN:** التشفير غير مُصادَق؛ التعديل المتعمّد مع تصحيح CRC يمرّ (لا يُعدّ «تلفاً» فلا يُسترد منه). نقطة منفصلة: عقد `*_v2` مُصادَق متوافق للخلف.
- **غير مُتحقَّق على جهاز:** أن Android يطبّق الاستثناء فعلياً (cloud backup + device transfer)، والترحيل والاسترداد على Samsung — **DEFERRED BY OWNER** (D-36..D-38 أدناه).
- **iOS:** لم يُضبط استثناء النسخ (`NSURLIsExcludedFromBackupKey`)؛ مفاتيح `first_unlock` تنتقل مع النسخ المشفّرة فتبقى متّسقة؛ النسخ غير المشفّرة → صندوق بلا مفتاح → الآن **يُسترد** بعد قائمة خادم ناجحة.
- الصناديق المستعادة قبل هذا التحديث (من نسخ سابقة) في الجذر تُنقل ثم تُسترد عند أول قائمة ناجحة.
- **T-3/T-4** (ذاكرة الصناديق المفتوحة بعد logout؛ ملف secure storage مشترك) باقية كما في §7T.

**الملفات (غير مدمجة):** `lib/src/services/encrypted_account_list_cache.dart`؛ `android/app/src/main/res/xml/backup_rules.xml`؛ `android/app/src/main/res/xml/data_extraction_rules.xml`؛ جديد `test/lists/offline_lists_storage_test.dart`؛ اختبارات الكاشات الست (`test/lists/{requests,offers,owners,offices,brokers,watchmen}_local_first_test.dart` — المسار فقط)؛ وهذا الملف.

**الحالة:** **D-1a + D-2 = CODE_PROVEN / READY FOR COMMIT REVIEW**؛ D-3 OPEN؛ Samsung **DEFERRED BY OWNER**؛ FU-OWNERS-R5C (5) والتاريخي **OPEN**. **STOP** — لا commit؛ لا D-3؛ لا P2.5b.

### 7T-2) خلل وُجد في المراجعة النهائية قبل الـ commit وإصلاحه — 2026-11-02

- **الخلل (VERIFIED بتجربة مؤقتة حُذفت):** `Hive.openBox` في Hive 2.2.3 يعيد **الصندوق المفتوح بالاسم متجاهلاً `path:` والمفتاح** (`if (isBoxOpen(name)) return box(name)`). إن اختفى مفتاح حساب من secure storage **والصندوق مفتوح** في العملية (مثلاً `resetOnError` بعد عطل عابر)، فإن خطوة «بناء البديل في `.recovery`» كانت تكتب **في الصندوق الرئيسي المفتوح بمفتاحه القديم** ثم تغلقه، ثم يفشل التحقق ويتوقف الاسترداد («replacement not verified»)؛ المفتاح يبقى مفقوداً ولا قراءة، والاسترداد ينجح فقط عند **قائمة الخادم الثانية**. لا كشف بيانات ولا تداخل حسابات ولا نص صريح، لكنه يخالف قاعدة «لا يتغير شيء قبل بناء البديل والتحقق منه». أُوقف الـ commit بطلب المالك.
- **الإصلاح (`_recover`):** بعد التأكيد الثاني وقبل بناء البديل: `if (Hive.isBoxOpen(name)) await Hive.box<String>(name).close();` — **صندوق ذلك الحساب وتلك القائمة فقط**، تحت طابور عمليات ذلك الصندوق (كل قراءة/كتابة له تمر به، والكاش لا يعطي مراجع صناديقه لأي مستدعٍ، فلا عملية جارية أو مرجع قديم يكتب فيه). الإغلاق لا يغيّر الملف. كل شروط D-2 الأخرى بلا تغيير.
- **اختباران جديدان (في `offline_lists_storage_test.dart`):** (1) مفتاح يُفقد والصندوق مفتوح → **يُسترد عند أول قائمة خادم** (مفتاح جديد، القائمة تُقرأ، لا بقايا في `.recovery`)، ويُقرأ بعد إغلاقه وبعد إعادة تشغيل محاكاة؛ (2) استرداد فاشل (فشل حفظ المفتاح الجديد) لصندوق كان مفتوحاً → **ملفه المشفّر بايت-بايت كما كان**، المفتاح يبقى مفقوداً، لا نسخة جانبية، وحساب Bob (صندوقه ومفتاحه وقائمته) بلا مساس.
- **فحص الطفرة:** حذف سطر الإغلاق → **فشل الاختباران الجديدان**؛ أُعيد الملف بايت-بايت.
- **النتائج:** `offline_lists_storage_test.dart` **27/27 PASS** (3 تشغيلات). المجموعات المرتبطة (`test/lists/` بالكاشات الست، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test`، شاشات القوائم الست) → **844 PASS، 6 FAIL — المعروفة فقط** (التاريخي + FU-OWNERS-R5C الخمسة). Analyzer (9 ملفات) → No issues. Format → 0 تغييرات. `git diff --check` → نظيف. CRLF.
- **يُودَع** بموافقة المالك: `fix(offline): harden encrypted cache backup and recovery` (11 ملفاً). **D-3 OPEN** (لا تشفير مُصادَق). Samsung D-36..D-38 **DEFERRED BY OWNER**.

---

## 7U) D-3 — تصميم التشفير المُصادَق والتحقق التقني — 2026-11-02 (DESIGN VALIDATED، لا تغيير إنتاجي)

**Git:** `perf/phase-1-startup-baseline` @ `dc4c95d` (دفعه المالك)، مطابق لـ `origin` (0/0)، نظيف، stashes = 2. **لا تغيير في أي ملف إنتاجي أو صيغة أو مفتاح.** تجربتان مؤقتتان (`test/lists/zz_d3_*`) شُغّلتا في مجلد مؤقت ثم حُذفتا؛ الشجرة نظيفة بعدهما.

### نقطة الدمج الحالية

- كل قائمة = قيمة `String` واحدة (JSON) تحت `<entity>_v1` داخل صندوق Hive مشفّر بـ `HiveAesCipher(master)` (AES-256-CBC، IV عشوائي لكل إطار، CRC32 غير تشفيري). `master` = مفتاح 32 بايت لكل حساب ولكل نوع في `flutter_secure_storage`. **نقطة الدمج الصحيحة = القيمة** (`_encode` → JSON → `put`) داخل `EncryptedAccountListCache.read/write` — لا يتغير الصندوق ولا مفتاحه ولا مساره ولا قواعد D-1a/D-2.

### البدائل المُقيَّمة (بقياس فعلي)

- **الاعتماديات المتاحة دون إضافة شيء جديد للتطبيق:** `pointycastle` 4.0.0 (انتقالية — يجلبها Hive نفسه و`dart_jsonwebtoken`؛ فيها `GCMBlockCipher` و`HKDFKeyDerivator`)، و`crypto` 3.0.7 (انتقالية — حزمة dart-lang الرسمية؛ فيها `Hmac(sha256)`). حزمة `cryptography` غير موجودة.
- **(A) AES-256-GCM عبر `pointycastle`:** AEAD قياسي. **تحقّق (VERIFIED_TEST مؤقت):** round-trip سليم؛ رُفض بـ `InvalidCipherTextException` كل من تعديل الـ ciphertext والـ tag والـ nonce، والحساب الخاطئ والكيان الخاطئ (AAD)، والمفتاح الخاطئ، واستعمال المفتاح الأصلي بدل المشتق؛ 20,000 nonce عشوائي فريدة؛ يتعايش مع `_v1` في الصندوق نفسه. **لكن الأداء:** قائمة 482 KB (2000 Request): **seal ≈ 762–829 ms، open ≈ 1114 ms** (desktop JIT، Dart خالص)؛ داخل `Isolate.run` ≈ 1345 ms زمن حائط (يحرّر الواجهة لا الزمن). خطر حقيقي على زمن ظهور القائمة offline.
- **(B) MAC بـ HMAC-SHA256 (`crypto`) فوق تشفير Hive الحالي:** **HMAC على 482 KB ≈ 9 ms** (≈ 7% فوق كلفة اليوم: Hive AES put ≈ 44 ms، فتح+فك ≈ 119 ms). السرّية تبقى AES-256-CBC من Hive (IV عشوائي لكل كتابة)، والسلامة من HMAC بمفتاح مشتق منفصل. التركيب هنا MAC-then-encrypt داخل صندوق مشفّر؛ ثغرات MtE المعروفة (padding oracle) تتطلب طرفاً يجيب عن فك تشفير مُعدَّل تفاعلياً — غير موجود في تخزين محلي يُقرأ فقط بالتطبيق، وأي تعديل يُرفض قبل استعمال المحتوى.
- **(C) Encrypt-then-MAC «صحيح» بتشفير CBC يدوي ثم HMAC على الـ ciphertext:** أبطأ قليلاً من (B) وأكثر شيفرة تركيبية مخصّصة؛ لا مكسب أمني عملي على (B) في هذا النموذج. غير موصى به.

### التوصية (واحدة)

**(B): وسم HMAC-SHA256 مُصادِق، بمفتاح مشتق، داخل صندوق Hive المشفّر الحالي** — بلا تغيير في صيغة الصندوق أو مفتاحه أو مساره، وبكلفة ≈ 9 ms للقوائم الكبيرة. البديل (A) مقبول أمنياً إن فضّل المالك AEAD قياسياً على الأداء (مع `Isolate.run` وقبول زمن أطول للقوائم الكبيرة).

**صيغة v2 المقترحة (قيمة تحت `<entity>_v2`، بجانب `<entity>_v1` أثناء الانتقال):**
- `{"v":2,"p":"<JSON القائمة>","t":"<base64url HMAC-SHA256>"}` — كلها داخل الصندوق المشفّر (لا نص صريح على القرص؛ لا tokens؛ لا metadata حساسة خارج التشفير).
- `t = HMAC-SHA256(K_mac, "bw-offline-list|v2|" + listKey + "|" + uid + "|" + p)` — **يربط** الصيغة والكيان والحساب بالمحتوى.
- `K_mac = HMAC-SHA256(master, "broker_wallet/offline_lists/v2/mac")` (KDF بـ HMAC كدالة PRF — NIST SP 800-108، كتلة واحدة) — **لا مفتاح جديد في secure storage**، فـ D-2 (مفتاح جديد عند الاسترداد) يشتق K_mac جديداً تلقائياً.
- المقارنة بزمن ثابت؛ أي فشل (صيغة/وسم/حساب/كيان) = «غير صالح» → `read` يعيد `null` (fail-closed). الـ «nonce» = IV إطار Hive العشوائي (كل كتابة).
- **CRC32 لا يُعتمد عليه للسلامة** (يبقى فقط لكشف تلف الإطار داخل Hive).

### الانتقال من v1 (آمن من الانقطاع، بلا حذف تلقائي غير مُتحقَّق)

- **القراءة:** `_v2` موجود → تحقق الوسم ثم الفك؛ فشل → `null` (لا رجوع إلى `_v1`). `_v2` غائب و`_v1` موجود → قرار المالك (أدناه).
- **الكتابة (فقط من قائمة خادم ناجحة كما اليوم):** `put(_v2)` ثم قراءة وتحقق → ثم `delete(_v1)` → ثم `compact()` لإزالة بايتات v1 من الملف. انقطاع بين الخطوات → `_v2` يُفضَّل و`_v1` يُزال في الكتابة التالية.
- **لا تحويل محلي لـ v1 إلى v2 أبداً:** v1 بلا وسم، فـ«فكّه وتوقيعه» يُضفي صفة الأصالة على بيانات ربما عُدّلت. v2 يُنشأ **فقط من قائمة خادم مُتحقَّق منها**.
- **مفاضلة توفر offline (قرار المالك):** (S1 صارم) لا يُعرض v1 offline بعد التحديث → القوائم offline فارغة حتى أول تحديث ناجح بشبكة؛ (S2 انتقالي، **موصى به**) يُعرض v1 حتى أول تحديث ناجح ثم يُستبدل بـ v2 ويُحذف — خطره ليس أعلى من اليوم ويختفي بعد أول اتصال.
- **D-1a وD-2 بلا تغيير:** نفس الصناديق في `offline_lists`، نفس النقل، نفس الاسترداد (مع الإغلاق قبل البناء — §7T-2) ونفس `guardedOpen` الضيق.

### حدود صريحة

- **إعادة التشغيل (replay):** الوسم لا يكشف استبدال القيمة بنسخة **أقدم صالحة** للحساب والكيان نفسيهما (مُثبت في التجربة: نسخة أقدم فُتحت بنجاح). الأثر: عرض قائمة أقدم للحساب نفسه حتى أول تحديث. D-1a يقلّل مصادر النسخ القديمة. علاج اختياري لاحق: عدّاد رتيب في secure storage داخل مدخل الـ MAC (كتابة keystore إضافية لكل حفظ) — **غير موصى به الآن**.
- (B) يبقي السرّية على AES-CBC من Hive (بلا تغيير)، والسلامة على HMAC؛ ليس «AEAD» بالمعنى الحرفي لنمط واحد، لكنه مُصادَق تشفيرياً. لا يُدّعى أكثر من ذلك.
- ذاكرة الصناديق المفتوحة بعد logout (T-3) والملف المشترك لـ secure storage (T-4) خارج D-3.

### نطاق الشيفرة المقدَّر (عند الموافقة)

- **إنتاج:** `lib/src/services/encrypted_account_list_cache.dart` (~100–140 سطراً: اشتقاق K_mac، ترميز/تحقق الظرف، قراءة v2/v1 حسب S1/S2، كتابة v2 ثم حذف v1 ثم compact)؛ الأغلفة الست بلا تغيير غالباً (اسم `_v2` يُشتق من `listKey`). `pubspec.yaml`: ترقية `crypto` إلى **اعتمادية مباشرة** (بالإصدار المقفل نفسه 3.0.7 — لا كود جديد في التطبيق؛ يتغير وسم `pubspec.lock` إلى direct). **لا `pointycastle` مباشر** مع (B).
- **اختبارات:** ملف جديد (~20): round-trip v2؛ رفض تعديل الـ payload/الوسم/الصيغة/الحساب/الكيان؛ فشل الوسم = `null` بلا رجوع لـ v1؛ S1/S2؛ الانتقال v1→v2 بعد قائمة خادم فقط مع حذف v1 وcompact؛ انقطاع بين put(v2) وdelete(v1)؛ الاسترداد D-2 يشتق K_mac جديداً؛ القوائم الست؛ حذف الحساب. **تعديل اختبارات قائمة:** الاختبارات التي تقرأ `<entity>_v1` الخام (فحوص «لا تُحفظ صفوف حساب آخر»، «لا وسائط» في Offers/Owners، «التاريخ المفقود يبقى null» في Brokers/Watchmen، «damaged entry») تُحدَّث لتقرأ `_v2` عبر مساعد اختبار.
- **موافقات مطلوبة:** (1) اعتماد (B) أو (A)؛ (2) S2 أو S1؛ (3) ترقية `crypto` إلى اعتمادية مباشرة (تغيير pubspec/lock)؛ (4) تغيير صيغة القيم المخزَّنة (v2) وحذف v1 بعد التحقق.

**الحالة:** D-3 = **OPEN — التصميم مُتحقَّق منه وجاهز للموافقة المنفصلة والتنفيذ.** **STOP** عند حدّ تغيير التشفير الإنتاجي؛ لا P2.5b.

### 7U-1) تنفيذ D-3 — الخيار B + سياسة S2 (موافقة المالك) — 2026-11-02 (CODE_PROVEN، غير مدمج)

**Git قبل البدء:** `dc4c95d` (دفعه المالك)، مطابق لـ `origin`، الشجرة فيها هذا الملف فقط، stashes = 2.

**التصنيف الأمني (مُلزِم):** هذا التصميم **يصادق حمولة كل قائمة داخل صندوق Hive المشفّر**؛ **ليس** مكافئاً لـ AES-GCM ولا لـ Encrypt-then-MAC على الملف كاملاً (إطارات Hive تبقى AES-256-CBC + CRC32 كما هي). **لا حماية من rollback/replay** لنسخة سابقة صالحة للحساب والقائمة نفسيهما. السجلات المحلية **ليست مرجعاً** لصلاحيات أو اشتراكات أو billing أو حالة الخادم (كما كانت دائماً).

**التغيير:**
- `pubspec.yaml`: `crypto: ^3.0.7` اعتمادية مباشرة (تعليق السبب). `flutter pub get --offline` غيّر في `pubspec.lock` **سطراً واحداً**: `crypto` من `transitive` إلى `"direct main"` — **الإصدار 3.0.7 والـ sha256 نفسهما**؛ لا حزمة جديدة في التطبيق؛ لم تتغير ملفات plugin registrant.
- `lib/src/services/encrypted_account_list_cache.dart` (النواة المشتركة فقط؛ الأغلفة الست بلا تغيير):
  - **صيغة v2** تحت `<entity>_v2` (يُشتق من `listKey`: `requests_v1` → `requests_v2`): `{"v":2,"p":<JSON القائمة>,"t":<base64url HMAC-SHA256>}` داخل الصندوق المشفّر.
  - **مفتاح الوسم مشتق ومفصول المجال:** `K_mac = HMAC-SHA256(boxKey, "broker_wallet/offline_lists/v2/mac")` — مفتاح الصندوق لا يُستخدم مفتاحاً للـ MAC أبداً؛ لا مفتاح جديد في secure storage (D-2 بمفتاح جديد يشتق K_mac جديداً تلقائياً).
  - **مدخل الوسم بترميز غير ملتبس:** كل جزء مسبوق بطوله (uint32 big-endian): `"bw-offline-list"`، `"2"`، `listKey` (الكيان)، معرّف الحساب القانوني، **بايتات الحمولة UTF-8 حرفياً**.
  - **التحقق:** يُفك الظرف (3 حقول بالضبط، `v == 2` رقمياً، `p` و`t` نصوص، `t` base64url صالح) ويُقارن الوسم كاملاً **بزمن ثابت** (طول مختلف = رفض) **قبل** فك أي سجل. أي فشل → `null` (تسجيل debug بفئة ثابتة) — **لا تُكشف بيانات v2 غير مُصادَقة أبداً**.
  - **القراءة (S2):** وجود `_v2` → هو المصدر الوحيد (فشل = لا شيء، **لا رجوع إلى v1 أبداً**)؛ `_v2` غائب → `_v1` القديم يُقرأ كما كان (مؤقتاً، داخل جلسات معتمدة فقط)؛ **القراءة لا تنشئ وسماً ولا تكتب أبداً**.
  - **الكتابة:** من `localFirstList` فقط بعد قائمة خادم ناجحة للحساب النشط (كما قبل): `put(_v2)` ← قراءة وتحقق الوسم ← **عندها فقط** `delete(_v1)` + `compact()` (إزالة بايتات v1 من الملف). **لا يُنشأ وسم لسجلات v1 محلية أبداً.**
  - **فشل السلامة ليس إذناً بإعادة الضبط:** صندوق مقروء فيه `_v2` يفشل التحقق → كتابة بلا `mayRecover` تُتخطّى (القيمة تبقى كما هي وتُقرأ كلا شيء)؛ يُستبدل فقط بقائمة خادم مُتحقَّق منها للحساب النشط (شرط D-2 نفسه).
  - **D-2:** البديل يُبنى ويُتحقق منه بصيغة v2 (`_seal`/`_verify`) بالمفتاح الجديد، قبل التبديل وبعده؛ «مقروء رغم كل شيء» يكتب v2 عبر `_store`. الإغلاق قبل البناء (§7T-2)، `guardedOpen` الضيق، طابور العمليات، العزل، D-1a، وحذف الحساب **بلا تغيير**.
- **الاختبارات القائمة** (الكاشات الست): الوصول الخام لـ `<entity>_v1` صار لحمولة `<entity>_v2` (امتداد `payload` في كل ملف)، و«damaged entry» يزرع v2 تالفاً؛ اختبار Requests «لا تُقرأ صفوف حساب آخر» صار يزرع **قائمة v1 قديمة مختلطة** ليختبر فلتر المالك على مسار S2.

**الأدلة (شغّلها الوكيل؛ تصريح دائم §7L):**
- **جديد `test/lists/offline_lists_integrity_test.dart` — 18/18 PASS (3 تشغيلات):** قائمة الخادم تُخزَّن v2 (3 حقول، وسم 32 بايت) ولا v1؛ **الوسم = HMAC-SHA256 تحت K_mac المشتق على الأجزاء المسبوقة بطولها، ولا يساوي الحساب نفسه تحت مفتاح الصندوق**؛ يُقرأ بعد إعادة التشغيل؛ **رفض:** تعديل أول/آخر بايت من الوسم؛ تعديل الحمولة إلى قائمة صالحة للحساب نفسه؛ 11 صيغة مشوّهة (ليس JSON، قائمة JSON، بلا وسم، وسم فارغ، ليس base64، وسم قصير/طويل، `v:3`، `v:"2"`، حمولة غير نصية، حقل زائد)؛ **v2 معدّل مع v1 قديم موجود → لا شيء (لا رجوع)**؛ **حساب آخر بالمفتاح نفسه**؛ **قائمة نوع آخر بالمفتاح والحساب نفسيهما** (قائمة فارغة تُفك لأي نوع — فلا يرفضها إلا الوسم)؛ **قائمة صالحة بمفتاح سابق**؛ **S2:** v1 قديم يبقى مقروءاً و**القراءة لا تنشئ v2** (وبعد إعادة التشغيل)؛ فشل الخادم يُبقي v1 بلا وسم؛ أول قائمة خادم تستبدل v1 بـ v2 وتُزيل v1 (وبعد إعادة التشغيل)؛ قائمة خادم فارغة تستبدل v1 بـ v2 فارغ؛ **انقطاع بعد كتابة v2 وقبل حذف v1** → يُقرأ v2، والقائمة التالية تُزيل v1؛ **فشل سلامة** لا تُعيد ضبطه كتابة غير آتية من الخادم، وتستبدله قائمة خادم مُتحقَّق منها؛ **كتابة مبتورة في آخر الملف** → لا تُقرأ، وقائمة الخادم التالية تسترد (D-2)؛ **الكاشات الست** تخزّن v2 وتقرؤه، وكلٌّ يقرأ v1 القديم.
- **فحص الطفرات (7/7 التُقطت بعد تشديد اختبارين؛ الملف أُعيد بايت-بايت):** الرجوع إلى v1 عند فشل v2؛ قبول أي وسم؛ إسقاط الحساب من مدخل الوسم؛ **إسقاط الكيان** (نجا أولاً لأن فك حمولة Requests كـ Offers يفشل — شُدّد الاختبار بقائمة فارغة)؛ **مفتاح الصندوق مفتاحاً للـ MAC** (نجا أولاً — شُدّد بتثبيت الصيغة الدقيقة)؛ عدم إزالة v1؛ السماح بإعادة ضبط فشل السلامة دون قائمة خادم.
- **الكاشات الست + التخزين/الاسترداد:** **161/161 PASS** على صيغة v2.
- **مجموعات مرتبطة:** `test/lists/`، `test/home/`، `delete_account_test`، `test/favorites/`، `canonical_identity_test`، `supabase_secure_storage_test`، شاشات القوائم الست → **862 PASS، 6 FAIL — المعروفة فقط** (التاريخي + FU-OWNERS-R5C الخمسة). لا فشل جديد.
- **Analyzer** (9 ملفات) → No issues. **Format** (8 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. CRLF.
- **الأداء (تجربة مؤقتة حُذفت؛ desktop JIT — لا يمثّل الجهاز):** 2000 Request (حمولة ≈ 1.05 MB): قراءة v2 (فتح + تحقق + فك) **≈ 217 ms** مقابل قراءة v1 **≈ 184 ms** (≈ +32 ms، +18%؛ جزء منه هروب JSON للحمولة داخل الظرف)؛ كتابة v2 ≈ 205 ms. قياس الجهاز ضمن جلسة Samsung المجمّعة.

**الحدود المتبقية:** rollback/replay لنسخة v2 أقدم صالحة (غير محمي)؛ v1 القديم **غير مُصادَق** حتى أول تحديث ناجح بعد الترقية (S2)، وقد يظهر v1 مزروع بتلاعب على مستوى الإطار في صندوق لم يُنشأ فيه v2 بعد؛ التشفير على مستوى الملف يبقى AES-CBC + CRC32 (Hive)؛ T-3/T-4 كما في §7T.

**Samsung (DEFERRED BY OWNER):** D-39 الترقية فوق قوائم v1: تظهر offline حتى أول تحديث ثم تُخزَّن v2؛ D-40 زمن فتح القوائم الكبيرة offline على Samsung (v1 مقابل v2).

**الملفات (غير مدمجة):** `pubspec.yaml`؛ `pubspec.lock` (وسم الاعتمادية فقط)؛ `lib/src/services/encrypted_account_list_cache.dart`؛ جديد `test/lists/offline_lists_integrity_test.dart`؛ `test/lists/{requests,offers,owners,offices,brokers,watchmen}_local_first_test.dart`؛ وهذا الملف.

**الحالة:** D-3 (B + S2) = **CODE_PROVEN / READY FOR COMMIT REVIEW**. FU-OWNERS-R5C (5) والتاريخي **OPEN**. **STOP** — لا commit؛ لا P2.5b.

---

## 7V) P2.5b — إعادة القراءة التلقائية بعد فشل الشبكة وعند عودة التطبيق — 2026-11-02 (retry/resume CODE_PROVEN، COMMITTED؛ FU-P2.5B-CONNECTIVITY OPEN)

**نقطة البداية:** `d51a499` (`fix(lists): align and size date dividers consistently`)، مطابق لـ `origin` (0/0)، الشجرة نظيفة، stashes = 2 (لم تُلمس). **إصلاحات الواجهة في `d51a499` محفوظة:** `git diff d51a499 -- lib/src/views lib/src/viewmodels` = 0 سطر؛ لا تغيير في أي واجهة أو ViewModel.

**FU-OWNERS-R5C — RESOLVED عند `d51a499`:** الاختبارات الخمسة (Owner swipe confirmation stays usable، Owner list keeps items on failed refresh، Office/Broker/Watchmen swipe cancel dialog 280×600 ar 2.0x) **تنجح** على `d51a499` قبل أي تغيير (تشغيل الأساس: الشاشات الست + delete_account → 287 PASS، 1 FAIL = التاريخي فقط)، **وتبقى ناجحة مع P2.5b**. لم تُعدَّل توقعات أي منها. **التاريخي** (`delete_account_test` — «Deletion job migration and hosted validation script (setUpAll)») **OPEN** ومنفصل، لا علاقة له بالقوائم.

### التنفيذ (آلية واحدة مشتركة للقوائم الست)
- **جديد `lib/src/services/list_refresh_signals.dart`:** `ListRefreshSignals.instance` — مصدر واحد لإشارة «عاد التطبيق إلى المقدمة» (`WidgetsBindingObserver`، `AppLifecycleState.resumed` فقط)؛ يُربط المراقب فقط ما دامت قائمة تستمع، ويُفك عند آخر إلغاء. `appIsActive` = التطبيق في المقدمة (true إن تعذّر معرفة الحالة). الإشارة تلميح فقط، لا تثبت إمكان الوصول للخادم.
- **`lib/src/services/encrypted_account_list_cache.dart` → `localFirstList`** (الأغلفة الست وخدماتها وViewModels **بلا تغيير** — تستعمل القيم الافتراضية):
  - **بلا حساب (`uid == null`):** السلوك السابق حرفياً.
  - **حساب مسجّل:** النسخة المحفوظة أولاً (كما قبل)، ثم قراءة الخادم نفسها (`getUserX`) والحفظ نفسه (v2 HMAC عبر `cache.write(..., mayRecover: stillTheAccount)`) — **لا مسار شبكة أو حفظ جديد.**
  - **بعد فشل شبكة** (`SocketException`/`TimeoutException`/`HandshakeException`/`HttpException`/`http.ClientException` فقط): محاولات محدودة بعد 5 ث، 15 ث، 45 ث، 2 د (4 كحد أقصى، مؤقّت واحد)؛ فشل القراءة الأولى **لم يعد يُنهي** قائمة الشاشة.
  - **عند العودة إلى المقدمة:** قراءة إذا فشلت آخر قراءة أو مضى على آخر نجاح ≥ 30 ث؛ تلميحات أقرب من 2 ث من بدء آخر قراءة تُعدّ مرة؛ العودة تُصفّر عدّاد المحاولات.
  - **منع التكرار:** قراءة واحدة في أي لحظة (`inFlight`)؛ مؤقّت محاولة واحد؛ لا polling ولا فحص شبكة.
  - **في الخلفية:** محاولة يحين وقتها والتطبيق ليس في المقدمة **لا تقرأ**؛ القراءة تأتي من إشارة العودة.
  - **عدم تحديث الواجهة بلا داعٍ:** قائمة مطابقة لآخر ما عُرض (`fingerprintOf` = الصيغة المخزّنة) لا تُعرض ثانية؛ الفشل المتكرر يُمرَّر **مرة واحدة** حتى نجاح تالٍ.
  - **الحفاظ على البيانات:** الفشل لا يمسّ النسخة المعروضة ولا المحفوظة (`EntityListState` يُبقي آخر قائمة)؛ القائمة الفارغة الآتية من الخادم **تُعرض وتُحفظ فارغة** (مرجعية).
  - **المصادقة منفصلة عن الشبكة:** أي خطأ آخر (لا جلسة، `PostgrestException` بما فيه JWT/401، `session_superseded`، خطأ خادم) **يوقف** كل القراءات التلقائية لتلك القائمة نهائياً — لا محاولة لجلسة مرفوضة. P2.5b لا يطلب تجديد token ولا يغيّر Auth أو Single Active Device؛ القراءات بالجلسة الحالية للعميل كما قبل.
  - **تبديل الحساب / الخروج / الإغلاق:** إن تغيّر الحساب عن حساب فتح القائمة → توقف نهائي، ولا قراءة (حتى من محاولة معلّقة)، وأي جواب متأخر لا يُعرض ولا يُحفظ. إغلاق الشاشة يلغي المؤقّت والإشارة والاشتراك.
- **تغيير مقصود في 6 اختبارات قائمة** (`test/lists/*_local_first_test.dart`، «a saved copy is not shown if the account changed while reading it»): كانت تنتظر قراءة خادم لحساب غادر؛ الآن **لا تُجرى تلك القراءة أصلاً**، فصار الاختبار يتحقق أن `reads` فارغ. ليس إخفاءً لفشل — السلوك الجديد أكثر تحفّظاً.

### ماذا يحدث عند عودة الشبكة (صريح)
- **خلال نافذة المحاولات (~3 د 5 ث بعد أول فشل) والتطبيق في المقدمة:** القائمة تتحدّث وحدها عند المحاولة التالية.
- **بعد استنفاد المحاولات والتطبيق ما زال في المقدمة:** **لا تحديث تلقائي** (مُثبت باختبار). تبقى النسخة المحفوظة — أو شاشة الخطأ إن لم توجد نسخة — حتى: الخروج من التطبيق والعودة، أو إعادة فتح الشاشة. عملية حفظ/حذف على تلك القائمة لا تعيد قراءتها في هذه الحالة (تدفق الخادم انتهى بعد فشله، كما قبل P2.5b).
- **السبب:** لا توجد حزمة connectivity في المشروع، ولا إشارة نظام موثوقة بدونها، والفحص الدوري ممنوع. «إعادة الاتصال التلقائية الكاملة» **غير مُدّعاة**؛ دعمها يحتاج قراراً منفصلاً (حزمة مثل `connectivity_plus` بموافقة المالك).

### التحديثات الصريحة القائمة (بلا تغيير)
- إعادة القراءة بعد كل إضافة/تعديل/حذف (`CoreEntityMutationNotifier` داخل تدفق الخادم) — تبقى كما هي، وكل قراءة جديدة تشترك فيها.
- فتح الشاشة من جديد = قراءة جديدة. **لا يوجد** pull-to-refresh ولا زر Retry في شاشات القوائم الست (لم يُضَف — لا تغيير واجهة).

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)
- **جديد `test/lists/list_refresh_test.dart` — 16/16 PASS:** فشل أول ثم محاولة ناجحة تُحفظ v2 (`"v":2`)؛ بقاء النسخة المحفوظة عبر محاولات فاشلة مع تمرير الفشل مرة؛ المحاولات محدودة ثم العودة تقرأ؛ قائمة فارغة مرجعية بعد فشل تُعرض وتُحفظ فارغة؛ العودة: قائمة حديثة (10 ث) لا تُقرأ وقديمة (>30 ث) تُقرأ وتُحفظ؛ تلميحات متتالية = قراءة واحدة ولا قراءتان معاً؛ فجوة 2 ث؛ قائمة مطابقة لا تُعرض ثانية؛ محاولة في الخلفية لا تقرأ والعودة تقرأ؛ **استنفاد المحاولات في المقدمة → لا قراءة حتى العودة (الحدّ مُثبت)**؛ خطأ غير شبكي (`StateError`، `session_superseded`) يوقف المحاولات والعودة؛ تبديل الحساب (محاولة معلّقة + جواب متأخر لا يُعرض ولا يُحفظ)؛ الخروج؛ إغلاق الشاشة (لا قراءة، الإشارة مفكوكة)؛ **الشاشات الست** (ViewModels الحقيقية مع `ListRefreshSignals.instance.debugResume()`) تتعافى من فشل القراءة الأولى عند العودة.
- **فحص الطفرات — 13/13 التُقطت** (كلها بفشل اختبار محدد، لا بانتهاء مهلة؛ الملف أُعيد من نسخة احتياطية و`cmp` = مطابق بايت-بايت؛ لا `git restore/reset`): إلغاء منع التكرار؛ إلغاء فجوة 2 ث؛ إلغاء تخطّي القائمة الحديثة؛ محاولات غير محدودة؛ محاولة لأي خطأ؛ قراءة لحساب غادر؛ قراءة بعد إغلاق الشاشة؛ عرض قائمة مطابقة؛ تمرير كل فشل؛ إنهاء القائمة بعد الفشل؛ قبول جواب متأخر؛ إبقاء الإشارة مفتوحة؛ قراءة في الخلفية.
- **مجموعات مرتبطة** (قبل إضافة شرط الخلفية): `test/lists/`، `test/home/`، `test/favorites/`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test`، الشاشات الست → **881 PASS، 1 FAIL — التاريخي فقط**؛ FU-OWNERS-R5C الخمسة PASS.
- **بعد شرط الخلفية (نهائي، مركّز — التغيير يمسّ مؤقّت المحاولة في `localFirstList` فقط):** `test/lists/` + الشاشات الست (`r5a`/`r5b`/`r5c`/`r5d`×3) → **493/493 PASS** (FU-OWNERS-R5C الخمسة ضمنها، PASS). `test/home/`، `test/favorites/`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test` لم تُعَد (لا تستورد المسار المتغيّر؛ نتيجتها أعلاه).
- **Analyzer** (الملفان + `test/lists/`) → No issues. **Format** (9 ملفات) → 0 تغييرات. **`git diff --check`** → نظيف. CRLF في كل الملفات.

### الحدود المتبقية
1. لا مشغّل «عادت الشبكة» (أعلاه) — بعد ~3 د من الفشل في المقدمة لا تحديث حتى العودة أو إعادة فتح الشاشة.
2. خطأ الخادم (5xx) لا يُعاد تلقائياً (تحفّظ: لا تمييز موثوق عن رفض الجلسة).
3. محاولة تحين في الخلفية تُستهلك من العدّاد دون قراءة؛ العودة تصفّره.
4. السلوك على Samsung غير مُقاس — D-41..D-45 في §7N (DEFERRED BY OWNER).

**الملفات (غير مدمجة):** `lib/src/services/encrypted_account_list_cache.dart`؛ جديد `lib/src/services/list_refresh_signals.dart`؛ جديد `test/lists/list_refresh_test.dart`؛ `test/lists/{requests,offers,owners,offices,brokers,watchmen}_local_first_test.dart`؛ وهذا الملف. **بلا تغيير:** صيغ الكاش ومفاتيحه، D-1a/D-2/D-3، Auth، Single Active Device، الواجهة، `pubspec`، الخادم.

**الحالة:** P2.5b retry/resume = **CODE_PROVEN** (محاولات محدودة بعد فشل الشبكة + العودة إلى المقدمة + التحديثات القائمة) — commit `feat(offline): add bounded retries and app-resume list refresh` (2026-11-02، بموافقة المالك). **FU-P2.5B-CONNECTIVITY — OPEN:** مشغّل «عادت الشبكة» غير منفّذ (لا حزمة connectivity؛ الفحص الدوري ممنوع)؛ يحتاج قرار المالك بإضافة حزمة. FU-OWNERS-R5C: **RESOLVED** (الاختبارات الخمسة PASS على `d51a499` ومع P2.5b). التاريخي (Delete Account migration-file): **OPEN**. Samsung D-41..D-45: **DEFERRED BY OWNER**.
- **NEXT:** P2.5c (بموافقة منفصلة؛ لم يبدأ). FU-P2.5B-CONNECTIVITY ينتظر قرار المالك.
- **STOP:** لا commit/push/merge/deploy؛ لا APK ولا Samsung؛ لا P2.5c.

---

## 7W) P2.5b-2 — إشارة «عادت الشبكة» (FU-P2.5B-CONNECTIVITY) — 2026-11-02 (CODE_PROVEN بالاختبارات الآلية فقط؛ البناء الأصلي UNVERIFIED؛ COMMITTED)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `42f31a3` (P2.5b، دفعه المالك)، مطابق لـ `origin` (0/0 بعد `git fetch`)، stashes = 2؛ الشجرة فيها تعديل واحد غير مدمج: تقييم §7W السابق في هذا الملف (يُستبدل هنا).

**الأدوات (من المستودع لا من الملاحظات):** `android/settings.gradle:21` → **AGP 8.11.1**؛ Kotlin 2.2.20؛ Gradle 8.14.5؛ compileSdk 36، targetSdk 35، Java 17؛ iOS 15.0؛ Flutter 3.47.2 / Dart 3.13.2.

### لماذا رُفض 7.3.1
- توثيق `connectivity_plus` 7.x الرسمي يشترط **AGP ≥ 8.12.1** (ملف الحزمة يذكر `com.android.tools.build:gradle:8.12.1`) والتطبيق على 8.11.1 — قرار المالك: لا ترقية لـ AGP، فلا 7.x. (7.3.2 كان أصلاً غير قابل للحل: `nm ^0.6.0` → `dbus ^0.8.0` يتعارض مع `flutter_local_notifications ^19.5.0`.)

### الإصدار المختار: `connectivity_plus: 6.1.5` (مثبّت تماماً، بموافقة المالك)
- **dry-run** (`flutter pub add connectivity_plus:6.1.5 --dry-run`؛ `pubspec.yaml`/`pubspec.lock` مطابقان بعده): +3 حزم فقط — `connectivity_plus 6.1.5` (direct main)، `connectivity_plus_platform_interface 2.1.0`، `nm 0.5.0` (transitive)؛ `dbus 0.7.15` قائم بلا تغيير؛ **لا تغيير في أي إصدار آخر** (`flutter_local_notifications` كما هو). ثم `flutter pub get --offline` → «Changed 3 dependencies»، والفرق في `pubspec.lock` = هذه الإدخالات الثلاثة فقط.
- **متطلبات 6.1.5:** Dart ≥3.2، Flutter ≥3.7؛ Android: `classpath gradle:8.3.1` (مثل `share_plus`/`device_info_plus`/`package_info_plus`/`wakelock_plus` المستعملة حالياً)، compileSdk 34 للمكتبة، minSdk 19، Java 17، كود Java فقط؛ iOS 12.0 (podspec وSPM). **لا ترقية Flutter/Gradle/AGP/Kotlin/Xcode.**
- **إذن Android:** `ACCESS_NETWORK_STATE` مُعلن أصلاً في manifest التطبيق.
- **ملفات plugin registrant المتتبَّعة (تغيير محتوى فعلي، مطلوب للحزمة — ليس أثر CRLF):** `macos/Flutter/GeneratedPluginRegistrant.swift` (+2: `import connectivity_plus`، تسجيل `ConnectivityPlusPlugin`)؛ `windows/flutter/generated_plugin_registrant.cc` (+3: include وتسجيل `ConnectivityPlusWindowsPlugin`)؛ `windows/flutter/generated_plugins.cmake` (+1: `connectivity_plus`). `linux/` بلا تغيير (الحزمة Dart فقط على Linux). Android/iOS registrants غير متتبَّعة. **قرار تضمينها في الـ commit للمالك** (بدونها لا تُسجَّل الحزمة على macOS/Windows).

### التنفيذ
- **`lib/src/services/list_refresh_signals.dart` (الآلية المشتركة نفسها):**
  - **اشتراك connectivity واحد** يُربط مع أول قائمة تستمع ويُلغى مع آخر قائمة (مع مراقب دورة الحياة نفسه) — لا ستة اشتراكات.
  - **تلميح فقط عند «لا شبكة → شبكة ما»:** أول حدث بعد الاشتراك = الحالة الحالية (Android يرسلها فور الاشتراك) فلا يُعدّ تغييراً؛ Wi-Fi ↔ mobile ليس عودة؛ **debounce 1 ث** — انقطاع وعودة متتاليان داخلها = تلميح واحد، وانقطاع قبل انتهائها يلغيها؛ بعد آخر إلغاء تُنسى الحالة ولا يصل تلميح متأخر لمستمع جديد.
  - **التفعيل صريح:** `ListRefreshSignals.instance.useConnectivity()` في `initializeAppServices` (`lib/main.dart`، سطر واحد + import) — لا اشتراك قبل فتح قائمة؛ الاختبارات التي لا تستدعيه لا تلمس قناة الحزمة (وإلا فشلت اختبارات الواجهة بـ MissingPlugin عبر `FlutterError.reportError`).
  - خطأ من مصدر connectivity يُتجاهل (لا تلميحات منه فقط؛ إشارة العودة تبقى).
  - **ليس دليلاً:** الاتصال لا يثبت الإنترنت ولا الخادم ولا صلاحية الجلسة.
- **`localFirstList`:** تلميح يصل والتطبيق ليس في المقدمة **لا يقرأ** (سطر واحد في `onHint`؛ العودة بعده تقرأ). كل الحواجز الباقية كما هي: قراءة واحدة، فجوة 2 ث، تخطّي القائمة الأحدث من 30 ث، تصفير المحاولات (المحدودة) عند التلميح، التوقف عند تبديل الحساب/الخروج/خطأ غير شبكي، الإلغاء عند الإغلاق، الحفظ v2 HMAC نفسه.
- **بلا تغيير:** الواجهة (`lib/src/views`، `lib/src/viewmodels` = 0 سطر عن `d51a499`)، الأغلفة الست، صيغ الكاش ومفاتيحه، D-1a/D-2/D-3، Auth، Single Active Device.

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)
- **جديد `test/lists/list_connectivity_test.dart` — 18/18 PASS:** الإشارة: الحالة عند الاشتراك ليست تلميحاً و«لا شبكة → شبكة» تلميح واحد؛ التنقل بين الشبكات ليس عودة؛ تقلبات سريعة = تلميح واحد؛ عودة تنقطع قبل الـ debounce = لا شيء؛ **اشتراك واحد لكل المستمعين** يُلغى مع الأخير ويبدأ الجديد من حالة مجهولة؛ لا تلميح متأخر لمستمع جديد؛ مصدر فاشل لا يوقف إشارة العودة؛ بلا `useConnectivity` لا اشتراك، وتفعيله المتأخر يبدأ فوراً. القائمة: **بعد استنفاد المحاولات → العودة تقرأ مرة واحدة، والقائمة تُعرض وتُحفظ v2**؛ لا قراءة إضافية عند فتح القائمة؛ قائمة حديثة لا تُقرأ؛ تقلبات سريعة = قراءة واحدة ولا قراءتان معاً؛ **قائمتان مفتوحتان تتشاركان الاشتراك نفسه وكلٌّ تقرأ مرة**؛ في الخلفية لا قراءة والعودة إلى المقدمة تقرأ؛ تبديل الحساب والخروج → لا قراءة ولا عرض؛ فشل القراءة بعد العودة (اتصال بلا إنترنت) يُبقي النسخة المحفوظة ولا يُمرَّر الفشل ثانية؛ جلسة مرفوضة توقف القائمة نهائياً؛ إغلاق الشاشة → لا قراءة ويُلغى اشتراك connectivity.
- **`test/lists/list_refresh_test.dart` — 17/17 PASS:** أُضيف: **الشاشات الست** (ViewModels الحقيقية على `ListRefreshSignals.instance`) تتعافى من فشل القراءة الأولى عند عودة الشبكة **عبر اشتراك connectivity واحد**؛ واختبار العودة إلى المقدمة للشاشات الست بلا تغيير في جوهره (أُعيد تنظيمه ليشترك في الدالة نفسها).
- **فحص الطفرات — 10/10 التُقطت** (كلٌّ بفشل اختبار محدد، لا مهلة؛ الملفان أُعيدا من نسخة احتياطية و`cmp` مطابق؛ لا `git restore/reset`): أول حدث يُعدّ تغييراً؛ التنقل بين الشبكات يُعدّ؛ بلا debounce؛ الانقطاع لا يلغي عودة معلّقة؛ إبقاء الاشتراك بعد آخر قائمة؛ إبقاء الحالة القديمة بعد إعادة الربط؛ القراءة في الخلفية؛ تلميح متأخر بعد آخر قائمة (**نجا أولاً** — الاختبار لم يكن يوصل حدث العودة قبل الإلغاء؛ شُدّد ثم التُقط)؛ عدم بدء `useConnectivity` المتأخر؛ عدم معالجة خطأ المصدر.
- **مجموعات مرتبطة:** `test/lists/`، `test/home/`، `test/favorites/`، `map_sdk_warmup_test` (يقرأ `main.dart`)، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test`، الشاشات الست → **907 PASS، 1 FAIL — التاريخي فقط** (Delete Account migration-file، OPEN ومنفصل). **FU-OWNERS-R5C الخمسة PASS.** لا خطأ من قناة connectivity؛ ضجيج `MissingPluginException` (حذف الكاش في الاختبارات) = 120 سطراً قبل التغيير وبعده.
- **Analyzer** (`main.dart`، الملفان، `test/lists/`) → No issues. **Format** (5 ملفات Dart) → 0 تغييرات (لا format عارٍ على ملفات متتبَّعة). **`git diff --check`** → نظيف. CRLF في ملفات Dart و`pubspec.yaml`.

### حدود استعادة الشبكة المتبقية
1. **عودة الإنترنت دون تغيّر مرئي في حالة الاتصال** (الراوتر يستعيد خطه والهاتف ما زال على Wi-Fi نفسه، captive portal، DNS/الخادم يعود): لا حدث → لا تلميح؛ تغطيه المحاولات المحدودة (~3 د) ثم العودة إلى المقدمة أو إعادة فتح الشاشة فقط.
2. «متصل» قد لا يعني إنترنت: القراءة تفشل كفشل شبكة عادي (النسخة تبقى، محاولات محدودة جديدة)؛ كل عودة حقيقية جديدة قد تبدأ دورة محاولات محدودة أخرى.
3. عودة الشبكة في الخلفية لا تقرأ؛ القراءة عند العودة إلى المقدمة.
4. خطأ الخادم (5xx) والجلسة المرفوضة لا يُعادان (كما في §7V).

### تحقق مؤجَّل (لم يُشغَّل)
- **البناء الأصلي: UNVERIFIED** — لا بناء Android/iOS/macOS/Windows دون موافقة منفصلة (AGP 8.11.1 مع classpath 8.3.1 للحزمة، تسجيل iOS/Windows/macOS).
- **Samsung/الجهاز: DEFERRED BY OWNER** — D-46..D-48 في §7N (وD-42 حُدِّث).

**الملفات (غير مدمجة):** `pubspec.yaml`؛ `pubspec.lock`؛ `lib/main.dart`؛ `lib/src/services/list_refresh_signals.dart`؛ `lib/src/services/encrypted_account_list_cache.dart`؛ جديد `test/lists/list_connectivity_test.dart`؛ `test/lists/list_refresh_test.dart`؛ registrants: `macos/Flutter/GeneratedPluginRegistrant.swift`، `windows/flutter/generated_plugin_registrant.cc`، `windows/flutter/generated_plugins.cmake`؛ وهذا الملف.

**الحالة:** FU-P2.5B-CONNECTIVITY = **CODE_PROVEN بالاختبارات الآلية فقط** — commit `feat(offline): refresh cached lists when connectivity returns` (2026-11-02، بموافقة المالك، مع ملفات registrant الثلاثة). توافق البناء الأصلي (Android/iOS/macOS/Windows) **UNVERIFIED** حتى بناء فعلي. **الحدّ قائم:** عودة الإنترنت دون تغيّر في حالة الاتصال لا تُطلق تحديثاً. **FU-OWNERS-R5C: RESOLVED** — الاختبارات الخمسة PASS في انحدار P2.5b-2 (907 PASS). التاريخي (Delete Account migration-file) **OPEN**. Samsung D-41..D-48 **DEFERRED BY OWNER**. **STOP** — لا push/merge/deploy؛ لا APK ولا Samsung؛ لا P2.5c.

---

## 7X) P2.5c — حداثة الكاش واتساقه وإشارات الاكتمال — 2026-11-02 (CODE_PROVEN بالاختبارات الآلية؛ غير مدمج)

**Git عند البدء (تحقق مباشر):** `perf/phase-1-startup-baseline` @ `9d45059`، مطابق لـ `origin/perf/phase-1-startup-baseline` (0/0)، الشجرة نظيفة، stashes = 2 (لم تُلمس). **إصلاحات `d51a499` محفوظة:** لا تغيير في `lib/src/views` ولا `lib/src/viewmodels` ولا الأغلفة الست ولا خدماتها.

### التدقيق (قبل التغيير — من المصدر)
| الحالة | قبل P2.5c |
|---|---|
| لا نسخة محفوظة | `read` → `null`؛ الشاشة تنتظر الخادم |
| نسخة محفوظة فارغة | `read` → `[]` (مختلفة عن `null`) |
| نسخة قديمة | تُعرض أولاً ثم يستبدلها الخادم — **لا يُعرف متى جاءت من الخادم** (لا وقت محفوظ) |
| تحديث جارٍ | لا تمثيل؛ الشاشة لا تميّز النسخة المحفوظة عن قائمة الخادم |
| قائمة فارغة مرجعية من الخادم | تُعرض وتُحفظ فارغة (P2.5b) |
| فشل التحديث مع نسخة | النسخة تبقى معروضة ومحفوظة؛ الخطأ يُمرَّر مرة |
| نجاح التحديث | تُحفظ v2 + HMAC |
| تبديل الحساب / الإغلاق | الجواب المتأخر لا يُعرض ولا يُحفظ (P2.5b) |
| كتابة مقطوعة | D-2/D-3: لا تُقرأ، وتُسترد بقائمة خادم مُتحقَّق منها |
| CRUD | `CoreEntityMutationNotifier.notify()` بعد كل create/update/delete → `_refreshedStream` يعيد القراءة على الاشتراك نفسه → `localFirstList` يحفظ القائمة الجديدة |
| **الاكتمال** | **القراءات الست** (`_fetchRequests/_fetchOffers/_fetchOwners/_fetchOffices/_fetchBrokers/_fetchWatchmen` في `supabase_core_entities_service.dart`): `select … eq(owner_id) isFilter(deleted_at, null) order(created_at desc)` — **بلا `limit` ولا `range` ولا count**. PostgREST يقصّها بصمت عند `max_rows` (`supabase/config.toml`: 1000 محلياً؛ **القيمة المستضافة غير مقاسة**). الترتيب `created_at desc` بلا مفتاح ثانٍ. ⇒ **لا يمكن ادعاء اكتمال أي قائمة.** |

### التنفيذ (النواة المشتركة فقط: `lib/src/services/encrypted_account_list_cache.dart`)
- **سجل وقت مُصادَق متوافق للخلف** تحت مفتاح جديد `<entity>_sync_v1` (مثل `requests_sync_v1`) **داخل الصندوق المشفّر نفسه**: `{"v":1,"p":"{\"serverReadAt\":\"<ISO UTC>\",\"completeness\":\"unknown\",\"list\":\"<وسم قائمة v2>\"}","t":"<HMAC-SHA256>"}`.
  - الوسم بمفتاح الـ MAC المشتق نفسه (`K_mac`) لكن **بتسمية مستقلة** `bw-offline-list-sync` وإصدار `1` (أجزاء مسبوقة بطولها: التسمية، الإصدار، `listKey`، الحساب، الحمولة) — فلا يُقبل سجل مكان قائمة ولا العكس، ولا سجل حساب آخر.
  - **مربوط بالقائمة الدقيقة** عبر وسم قائمة v2 (`list`): أي قائمة مختلفة ⇒ الوقت **غير معروف**، لا يُنقل وقت قديم إلى قائمة أخرى.
  - يُكتب **فقط** بعد `put(_v2)` والتحقق منه، **وفقط** مع قائمة خادم ناجحة (`write(..., serverReadAt:)` من `localFirstList`)، وكذلك داخل بديل الاسترداد D-2. كتابة بلا وقت تغيّر القائمة ⇒ الوقت غير معروف (القائمة نفسها ⇒ يبقى).
  - **لا تغيير** في `<entity>_v1`/`<entity>_v2`، الصناديق، المسارات، المفاتيح، الوسم v2 (بايت-بايت؛ اختبار الصيغة الدقيقة في `offline_lists_integrity_test` ما زال يمرّ)، D-1a/D-2/D-3/S2، أو حذف الحساب (السجل داخل الصندوق فيُحذف معه). النسخ السابقة تتجاهل المفتاح الجديد.
- **`readSaved(uid)` → `SavedList<T>?`** (`read` صار غلافاً عليه بسلوكه نفسه): `null` = لا نسخة أو لا نسخة آمنة (≠ قائمة فارغة)؛ `SavedListInfo { authenticated (v2 أم v1 قديم), serverReadAt (UTC أو null), completeness, ageAt(now) }`. سجل مفقود/تالف/مزوّر/لقائمة أخرى/وقت ليس UTC ⇒ `serverReadAt = null` **ولا يخفي القائمة أبداً**.
- **الساعة:** الوقت = ساعة الجهاز لحظة وصول قائمة الخادم، **مؤشّر فقط** — لا يُستخدم لأي قرار وصول أو تحديث أو صلاحية. `ageAt` يعيد `null` إن كان الوقت بعد «الآن» (رجوع الساعة) بدل عمر مختلق. **الأحدث بالترتيب يفوز لا الأكبر وقتاً:** رجوع الساعة بين قراءتين يسجّل وقت القراءة الأحدث (لا تجمّد).
- **`ListCompleteness { unknown }`:** كل قائمة **unknown** دائماً (بما فيها 1000 صف بالضبط)؛ القيمة المخزّنة `"unknown"` للتوافق المستقبلي، وهذا الإصدار يقرأ أي قيمة كـ unknown. **لا طلبات count ولا تغيير خادم.**
- **`localFirstList`:** يمرّر `serverReadAt: now()` مع كل حفظ قائمة خادم؛ ومعامل اختياري داخلي `onStatus(LocalListStatus)` = `{showing: nothing|savedCopy|server, refreshing, lastReadFailed, lastServerReadAt, completeness}` — للحساب المسجّل فقط، لا يُبلَّغ بعد تبديل الحساب/الإيقاف/الإغلاق. **لا مستهلك له في الإنتاج الآن** (لا واجهة)؛ الخدمات الست لا تمرّره. لا مستمع جديد، لا polling، لا اعتمادية؛ إشارات P2.5b/P2.5b-2 بلا تغيير.

### ما يُدّعى وما لا يُدّعى
- **مدعوم:** «آخر قراءة خادم ناجحة لهذه القائمة الدقيقة لهذا الحساب، بساعة الجهاز»؛ التمييز بين لا نسخة / نسخة فارغة / فشل التحديث / قائمة خادم فارغة مرجعية؛ v1 القديم = غير مُصادَق وبلا وقت.
- **غير مدعوم:** أن القائمة **كاملة**؛ أن الوقت صحيح إن كانت ساعة الجهاز خاطئة؛ الحماية من **replay** لنسخة v2 أقدم مع سجلها (تُقرأ كتلك النسخة بوقتها — مُثبت باختبار، حدّ معروف منذ D-3)؛ أن النسخة تعكس الخادم الآن.

### اتساق CRUD (مُدقَّق، بلا تغيير كود)
- **يعمل:** حذف/إضافة/تعديل ناجح والشاشة مفتوحة ⇒ إعادة قراءة على الاشتراك نفسه ⇒ القائمة والوقت يتقدّمان (مُثبت باختبار). الشاشة مغلقة ⇒ تُحدَّث عند الفتح التالي.
- **فجوات محدودة (مسجّلة، غير منفّذة — تحتاج O-work):** (G1) عملية ناجحة ثم فشل إعادة القراءة (انقطاع فوري) ⇒ النسخة المحفوظة تبقى ما قبل العملية حتى قراءة ناجحة، وقد يعود عنصر محذوف offline — وقتها يبقى الأقدم فهي صادقة «حتى t0». (G2) بعد فشل القراءة الأولى واستنفاد المحاولات، عملية لا تعيد القراءة (كما في §7V). (G3) شاشتان متزامنتان للقائمة نفسها قد تحفظان بترتيب الوصول لا بترتيب بدء القراءة — لا يحدث في التنقل الحالي (اشتراك واحد لكل ViewModel). (G4) `order(created_at desc)` بلا مفتاح ثانٍ: ترتيب الصفوف المتساوية غير محدد (P4).

### اقتراح واجهة — **قرار مالك منفصل، لم يُنفَّذ أي شيء**
سطر صغير بنمط caption القائم أعلى أول بطاقة في الشاشات الست، يُحاذى للبداية (يمين في RTL، يسار في LTR)، الوقت بصيغة المنطقة عبر `intl`، ولا يظهر إلا حين `showing == savedCopy`:
| الحالة | العربية | English |
|---|---|---|
| نسخة محفوظة بوقت معروف | «نسخة محفوظة — آخر تحديث {الوقت}» | "Saved copy — last updated {time}" |
| نسخة بلا وقت (v1/قديمة/ساعة راجعة) | «نسخة محفوظة على هذا الجهاز» | "Saved copy on this device" |
| فشل التحديث مع نسخة | «تعذّر التحديث — تُعرض النسخة المحفوظة» | "Couldn't refresh — showing saved copy" |
| الاكتمال | «قد لا تظهر كل السجلات» — **لا يُوصى به الآن** (سيظهر دائماً لأن كل قائمة unknown)؛ بعد P4 فقط وعند بلوغ الحد | "Some records may not be shown" |

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)
- **جديد `test/lists/offline_lists_freshness_test.dart` — 20/20 PASS:** لا نسخة = `null` وقائمة خادم فارغة = **محفوظة فارغة بوقتها** (حالة `nothing → server`)؛ الوقت UTC مع وسم القائمة الدقيقة ويبقى بعد إعادة التشغيل، و**الصيغة الدقيقة مثبّتة** (وسم مُعاد بناؤه مستقلاً)؛ فشل التحديث يُبقي القائمة ووقتها (حالة `savedCopy` + `lastReadFailed`)؛ بلا نسخة الفشل ليس قائمة فارغة؛ قائمة لاحقة على الشاشة نفسها (إعادة القراءة بعد CRUD) تستبدل وتقدّم الوقت؛ جلسة مرفوضة لا تمسّ القائمة ولا وقتها؛ حذف الحساب يزيلهما؛ **v1 القديم** = غير مُصادَق بلا وقت، وأول قائمة خادم تستبدله بـ v2 بوقت؛ **v2 بلا سجل** (نسخة `9d45059`) يُقرأ بلا وقت؛ كتابة بلا وقت تغيّر القائمة ⇒ وقت غير معروف، والقائمة نفسها ⇒ يبقى؛ **11 سجلاً تالفاً/مزوّراً** (وسم معدّل، ليس JSON، `v:2`، حقل زائد، بلا وسم، حمولة معدّلة، قائمة أخرى، وقت ليس UTC، وقت ليس نصاً، وقت غير مقروء، حمولة قائمة) ⇒ لا وقت **والقائمة تُقرأ**؛ سجل صالح لحساب Bob ⇒ مرفوض؛ قائمة مكان السجل ⇒ مرفوضة، وسجل مكان القائمة ⇒ لا قائمة؛ سجل أقدم بجانب قائمة أحدث ⇒ لا وقت، وreplay لنسخة كاملة أقدم ⇒ تُقرأ كتلك النسخة بوقتها (حدّ معروف)؛ `ageAt` لوقت مستقبلي = `null`؛ رجوع الساعة بين قراءتين يسجّل الأحدث؛ جواب بعد تبديل الحساب لا يكتب لأي حساب ولا يُبلَّغ؛ إغلاق الشاشة قبل الجواب لا يكتب؛ **استرداد D-2** بعد فقد المفتاح يحمل وقت قائمة الخادم المستردّة؛ **1000 صف ⇒ completeness unknown**؛ **الشاشات الست عبر خدماتها الحقيقية** (ساعة حقيقية) تسجّل الوقت تحت `<entity>_sync_v1` وفشل التحديث يُبقيهما.
- **فحص الطفرات — 10/10 التُقطت** (الملف أُعيد من نسخة احتياطية، `Get-FileHash` مطابق؛ لا `git restore/reset`): السجل غير مربوط بالقائمة؛ قبول وقت ليس UTC؛ عمر سالب؛ عدم فحص وسم السجل؛ عدم تمرير وقت الخادم؛ سجل الاسترداد غير مربوط؛ إسقاط وقت النسخة المحفوظة من الحالة؛ تسمية السجل = تسمية القائمة؛ الحساب خارج وسم السجل؛ الفشل يقدّم الوقت.
- **مجموعات مرتبطة** (`test/lists/`، `test/home/`، `test/favorites/`، `map_sdk_warmup_test`، `delete_account_test`، `canonical_identity_test`، `supabase_secure_storage_test`، الشاشات الست + `r5d_related_cards_test`) → **951 PASS، 1 FAIL — التاريخي فقط** (`delete_account_test` setUpAll: `PathNotFoundException … 20260913000100_account_deletion_jobs.sql`؛ لا علاقة بالقوائم). **FU-OWNERS-R5C الخمسة PASS.** ضجيج `MissingPluginException` = 120 سطراً كما قبل.
- **بعد تصحيح التنسيق اليدوي** (4 مواضع في أسطري الجديدة؛ `_syncTag` صار جسماً بكتلة بالمعنى نفسه): `test/lists/` + الشاشات الست → **532/532 PASS**.
- **Analyzer** (الملف + `test/lists/`) → No issues. **Format:** الملف الجديد مُنسَّق؛ الملف المتتبَّع **لم يُنسَّق آلياً** — نسخة منسَّقة في مجلد مؤقت مطابقة له بالمحتوى (الفرق نهايات أسطر CRLF فقط). **`git diff --check`** → نظيف.

### الملفات (غير مدمجة)
`lib/src/services/encrypted_account_list_cache.dart`؛ جديد `test/lists/offline_lists_freshness_test.dart`؛ وهذا الملف (§7N D-49/D-50 و§7X). **بلا تغيير:** الأغلفة الست، خدماتها، ViewModels، الواجهة، `pubspec`، Supabase/RLS، Auth، Single Active Device، R2، Firebase، Toolkit.

### الحالة و NOW / NEXT / STOP
- **P2.5c = CODE_PROVEN / READY FOR COMMIT REVIEW** — بالاختبارات الآلية؛ **ليس VERIFIED_REAL_DEVICE**. Samsung D-7..D-50 **DEFERRED BY OWNER**. البناء الأصلي لـ `connectivity_plus 6.1.5` **UNVERIFIED**. FU-OWNERS-R5C **RESOLVED** (PASS في هذا الانحدار). التاريخي (Delete Account migration-file) **OPEN** ومنفصل.
- **NOW:** مراجعة المالك ثم موافقة منفصلة على commit محلي (ملفان + هذا الملف).
- **NEXT:** قرار المالك في اقتراح الواجهة أعلاه (أو تأجيله)؛ ثم **P2.5e** (مراجعة تكامل/خصوصية القوائم الست + تحقق نهائي من D-1a/D-2/D-3/P2.5b/P2.5c). بعدها: P3 (استعلامات Supabase/N+1/أعداد Home المكررة)، P4 (ترقيم الصفحات + `max_rows` + اكتمال حقيقي + مفتاح ترتيب ثانٍ)، P5 (Samsung/iOS المجمّع)، ثم O0..O7 (كتابة offline وOutbox ومزامنة) — **كلها غير مبدوءة**.
- **STOP:** لا commit/push/merge/deploy؛ لا APK ولا Samsung؛ لا P2.5e/P3/P4 تلقائياً.
- **أُودع** بموافقة المالك: `ffaa1a8` `feat(offline): track cached list freshness and sync status` (3 ملفات)، ودفعه المالك (`origin` = `ffaa1a8`، تحقق بـ `git fetch` في §7Y).

---

## 7Y) P2.5e — مراجعة تكامل القوائم الست قبل إغلاق P2 — 2026-11-02 (REVIEWED؛ لا تغيير كود إنتاجي؛ قرار مالك مطلوب لفجوة CRUD)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `ffaa1a8` = `origin` (0/0)، الشجرة نظيفة، stashes = 2 (لم تُلمس).

### التكامل عبر القوائم الست (مُتحقَّق من المصدر + الاختبارات)
| الخاصية | Requests | Offers | Owners | Offices | Brokers | Watchmen | الدليل |
|---|---|---|---|---|---|---|---|
| غلاف على النواة المشتركة نفسها (`boxPrefix` `cached_<e>_`، `listKey` `<e>_v1`، مفتاح `<e>_cache_key_v1_<uid>`) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | المصدر |
| فلترة المالك = `userId` القانوني (`?? ''` لـ Offices/Brokers/Watchmen ⇒ صف بلا مالك يُسقط) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `*_local_first_test` (13–20 حالة «حساب آخر» لكل ملف) |
| `localFirstList(server: getUserX, cache, currentUserId: authRepository.currentUserId)` بلا معاملات خاصة | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | المصدر |
| تشفير Hive + v2 HMAC + قراءة v1 (S2) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `offline_lists_integrity_test` «all six» |
| D-1a `offline_lists/` + D-2 استرداد | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `offline_lists_storage_test` «every one of the six» |
| retry / resume / connectivity | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `list_refresh_test` «the six list screens» (ViewModels حقيقية، اشتراك واحد) |
| سجل الوقت `<e>_sync_v1` + فشل التحديث يُبقيه | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `offline_lists_freshness_test` «all six lists» (الخدمات الحقيقية) |
| قائمة خادم فارغة مرجعية تُحفظ فارغة | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `*_local_first_test` + freshness |
| تبديل الحساب / الخروج / الإغلاق | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | `*_local_first_test` + `list_refresh_test` + freshness |
| حذف الحساب (`DeletedAccountLocalDataCleaner` يستدعي `forgetAccount` للست) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | كل `*_local_first_test` يمرّ بالمنظّف |
- **الوقت ليس مرجعاً:** لا يستخدم أي كود خارج النواة `SavedListInfo`/`LocalListStatus`/`serverReadAt`/`readSaved`/`onStatus`؛ داخل النواة يُكتب ويُبلَّغ فقط. `lastSuccess` (P2.5b، في الذاكرة) يحدّ قراءات العودة فقط. **لا قرار وصول أو اكتمال من أي وقت.** الاكتمال `unknown` دائماً.
- **بلا تغيير:** الواجهة وإصلاحات `d51a499`، الأغلفة الست، خدماتها، ViewModels، صيغ الكاش.

### فجوة CRUD — التحقيق
- **المسار:** `EntityListState.deleteEntity` → `XService.deleteX` → `SupabaseCoreEntitiesService._softDeleteAndNotify` = `update({deleted_at}).eq('id', id)` ثم `CoreEntityMutationNotifier.notify()` → `_refreshedStream` يعيد القراءة على الاشتراك نفسه → `localFirstList` يحفظ.
- **مُثبت باختبار (characterization، لا إصلاح):** حذف مقبول ثم فشل إعادة القراءة ⇒ النسخة المحفوظة **تبقى بالعنصر المحذوف ووقتها ما قبل الحذف**، وشاشة لاحقة offline تعرضه (`savedCopy`، `lastServerReadAt = t0`). داخل الجلسة يخفيه `EntityListState._deleted`. المحاولة التالية الناجحة (retry/resume/connectivity/إعادة الفتح) تزيله وتقدّم الوقت. الإضافة/التعديل: النسخة **تُظهر أقل أو أقدم، لا بيانات مختلقة** حتى القراءة التالية.
- **اكتشاف مهم (يحدّد الحل):** `_softDelete` **بلا `.select()`** ⇒ PostgREST يُرجع نجاحاً حتى إن **لم يتأثر أي صف** (رفض RLS أو صف غير موجود). إذن «نجح استدعاء الحذف» **ليس تأكيداً من الخادم** بأن السجل حُذف. ⇒ أي حذف محلي من النسخة على هذا الأساس = اعتبار تعديل محلي مرجعاً — **ممنوع بنص المهمة**.
- **لماذا لم يُنفَّذ إصلاح (حدّ قرار):** أصغر إصلاح صحيح يحتاج **قرارين خارج النطاق الآمن**:
  1. **تأكيد الحذف من الخادم** — `update(...).eq('id', id).select('id')` والتحقق من صف واحد بالضبط. يغيّر عقد CRUD المشترك وشكل طلب الخادم؛ وقد تُخفي سياسة SELECT (عادةً `deleted_at is null`) الصف بعد تحديثه فيعود فارغاً رغم النجاح ⇒ **يحتاج تحققاً على قاعدة حقيقية/مؤقتة (pgTAP أو rollback-only) قبل أي اعتماد**.
  2. **تعديل نسخة v2 محلياً** — إزالة عنصر ثم إعادة وسمها يخالف قاعدة D-3 «v2 يُنشأ فقط من قائمة خادم مُتحقَّق منها» (المُدخل مُتحقَّق منه والإزالة تُضيّق فقط، لكنها سياسة أمنية قرّرها المالك).
- **البدائل للمالك:**
  - **(A) الموصى به عند الموافقة:** (1) + (2) معاً: بعد حذف **مؤكَّد بصف واحد** من الخادم، إزالة ذلك المعرّف فقط من نسخة v2 المُتحقَّق منها، تحت طابور الصندوق نفسه، **دون** وقت (يصير الوقت «غير معروف» لأن القائمة لم تعد مطابقة لقائمة خادم)، ولا تعديل لـ v1 (يُترك حتى أول قائمة خادم). لا إضافة ولا تعديل محلي للسجلات. الملفات المتوقعة: النواة (`removeWhere` مقيّد)، `_softDelete`، الخدمات الست (سطر بعد الحذف)، اختبارات + تحقق SQL.
  - **(B)** بلا تغيير على الخادم: إسقاط النسخة المحفوظة كلها بعد حذف «ناجح» ثم فشل القراءة ⇒ لا عنصر محذوف offline لكن لا قائمة offline حتى القراءة التالية (خسارة توفر).
  - **(C)** إبقاء الوضع (حدّ موثّق ومحدود): النسخة صادقة «حتى t0»، والتصحيح عند أول قراءة ناجحة؛ ومع موافقة اقتراح واجهة §7X يظهر للمستخدم أنها نسخة محفوظة بوقتها.

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)
- `offline_lists_freshness_test.dart` **23/23 PASS** (+3 characterization: حذف ثم فشل ⇒ العنصر باقٍ بوقت ما قبل الحذف ويظهر offline؛ المحاولة الناجحة تزيله وتقدّم الوقت؛ الإضافة/التعديل ⇒ أقل/أقدم لا مختلق). Analyzer → No issues. التغيير الوحيد: هذا الملف (+72 سطراً، وسطر `retryDelays` صار معاملاً).
- **FU-OWNERS-R5C — RESOLVED، مؤكَّد بالاسم:** `r5c` + `r5d` (Offices/Brokers/Watchmen) → **177/177 PASS**، منها الخمسة: Owner swipe confirmation stays usable، Owner list keeps items on failed refresh، Office/Broker/Watchmen swipe cancel dialog 280×600 ar 2.0x.
- **لم يُعَد الانحدار الواسع:** لا تغيير في `lib/` منذ تشغيل `ffaa1a8` (532/532 لـ `test/lists/` + الشاشات الست؛ 951 PASS / 1 تاريخي للمجموعات المرتبطة — §7X).
- **التاريخي** (`delete_account_test` setUpAll: `20260913000100_account_deletion_jobs.sql` غير موجود بعد إعادة التسمية في `0d7fb17`) **OPEN** ومنفصل.

### المخاطر المتبقية (غير محلولة)
1. فجوة CRUD أعلاه (تنتظر A/B/C).
2. `_softDelete` لا يؤكد عدد الصفوف — يؤثر أيضاً على عرض «حُذف» داخل الجلسة (`_deleted`) حين لا يحذف الخادم شيئاً فعلاً؛ القراءة التالية تعيده. (ملاحظة لـ P3/عقد CRUD، لا تغيير الآن.)
3. الاكتمال غير معروف (`max_rows` المستضاف غير مقاس؛ بلا ترقيم) — P4.
4. replay لنسخة v2 أقدم كاملة (حدّ D-3).
5. البناء الأصلي لـ `connectivity_plus 6.1.5` **UNVERIFIED**؛ Samsung D-7..D-50 **DEFERRED BY OWNER** — كل ما سبق **CODE_PROVEN لا REAL_DEVICE_VERIFIED**.

### الحالة و NOW / NEXT / STOP
- **P2 (القوائم الست offline) = CODE_PROVEN** بالتكامل أعلاه؛ **ليس REAL_DEVICE_VERIFIED**. يُغلق بعد قرار فجوة CRUD (أو قبولها كحدّ موثّق — C).
- **NOW:** قرار المالك: A (مع تحقق SQL منفصل) أو B أو C؛ وموافقة منفصلة على commit لهذا الملف + ملف الاختبار.
- **NEXT:** **P3 — Supabase Query Optimization** (أعداد Home المكررة، N+1، عدد الطلبات، ملاحظة `_softDelete` بلا تأكيد) — لم يبدأ. ثم P4، P5 (Samsung/iOS المجمّع)، O0..O7.
- **STOP:** لا commit/push/merge/deploy؛ لا APK ولا Samsung؛ لا P3 تلقائياً.

### 7Y-1) قرار المالك — الخيار C **حدّاً مؤقتاً موثّقاً** — 2026-11-02
- **الخيار C معتمد مؤقتاً فقط، وليس حلاً نهائياً.** لم يُنفَّذ A ولا B. **لا تغيير كود إنتاجي.**
- **FU-P2.5E-CRUD-STALE — OPEN (خطر صحة مفتوح، غير محلول):** حذف «ناجح» ثم فشل إعادة القراءة ⇒ النسخة المحفوظة تُبقي العنصر بوقت ما قبل الحذف وقد يظهر offline حتى أول قراءة خادم ناجحة؛ الإضافة/التعديل ⇒ نسخة أقل/أقدم. الاختبارات الثلاثة (characterization) في `offline_lists_freshness_test.dart` تثبت هذا السلوك وتبقى؛ **إن تغيّر السلوك عمداً لاحقاً تُحدَّث صراحةً، لا تُحذف**.
- **قاعدة إثبات:** استجابة PostgREST ناجحة **دون دليل على صف متأثر** (`_softDelete` = `update(...).eq('id', id)` بلا `.select()`/count) **ليست دليلاً كافياً** على أن الحذف المرن عدّل سجلاً (رفض RLS أو معرّف غير موجود يُرجعان نجاحاً بلا صفوف).
- **قاعدة D-3 محفوظة:** بيانات v2 المُصادَقة تُنشأ **فقط من قائمة خادم مُتحقَّق منها**؛ **لا إعادة كتابة محلية** للقائمة المحفوظة بعد حذف غير مؤكَّد.
- **الحل الصحيح مؤجَّل إلى P3.0** (تحقيق مركّز، غير مصرّح به بعد): عقد `_softDelete` المشترك، التحقق من الصفوف المتأثرة (`.select('id')` أو count)، وسلوك RLS (سياسة SELECT بعد ضبط `deleted_at`) على قاعدة حقيقية/مؤقتة قبل أي تغيير؛ ثم قرار منفصل في تعديل النسخة المحلية.
- **باقٍ لـ P3/P4:** حدّ نتائج Supabase (`max_rows` المستضاف غير مقاس) والاكتمال `unknown` والترقيم.
- **FU-OWNERS-R5C:** الخمسة **RESOLVED** (177/177 في §7Y). **التاريخي** (Delete Account migration-file): **OPEN**.
- **الحالة:** P2.5e = **CLOSED مع FU-P2.5E-CRUD-STALE OPEN**؛ P2 = CODE_PROVEN، ليس REAL_DEVICE_VERIFIED؛ Samsung D-7..D-50 والبناء الأصلي **DEFERRED / UNVERIFIED**.
- **NEXT (غير مصرّح به بعد):** **P3.0 — Supabase Query and CRUD Contract Audit.** **STOP:** لا P3 تلقائياً.
- **أُودع** بموافقة المالك: `722b59a` `test(offline): document CRUD cache consistency limitation`، ودفعه المالك (`origin` = `722b59a`، §7Z).

---

## 7Z) P3.0 — تدقيق استعلامات Supabase وعقد الحذف المشترك — 2026-11-02 (AUDIT؛ لا تغيير كود إنتاجي)

**Git (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `722b59a` = `origin` (0/0)، الشجرة نظيفة، stashes = 2. **الأدوات المثبّتة:** `supabase_flutter 2.17.2`، `postgrest 2.9.1`، `gotrue 2.27.2`.

**تصنيف الأدلة:** **SQL-EXECUTED** = نُفّذ على PostgreSQL 17.5 محلي (PGlite) بسلسلة الـ migrations الحقيقية (19/19 طُبّقت، 0 فشل؛ 24 فحصاً — انظر «الأدلة المنفّذة») وبدور `authenticated` مع JWT claims كما يفعل PostgREST — **ليس Supabase ولا PostgREST ولا الخادم المستضاف**؛ **TESTED** = اختبار Dart؛ **CODE** = من المصدر (بما فيه مصدر الحزم المثبّتة)؛ **MEASURED** = لا شيء في هذه النقطة (لا أعداد طلبات فعلية مقاسة).

### A) عقد `_softDelete` المشترك
- **التنفيذ:** `SupabaseCoreEntitiesService._softDelete(table, id)` = `update({'deleted_at': now}).eq('id', id)` ثم `notify()` عبر `_softDeleteAndNotify`؛ تستعمله **الكيانات الست** (`deleteRequest/Offer/Owner/Office/Broker/Watchman`). بلا `.select()`، بلا count، بلا فلتر `deleted_at`، بلا فلتر مالك (RLS وحده)، والخطأ يُرمى كما هو. **TESTED** (`core_entity_query_contract_test`: PATCH بـ `id=eq.<id>` فقط، Prefer بلا `return=representation`/`count`، و**204 بلا صف = نجاح** ويُبلَّغ كل القوائم).
- **RLS (من الـ migrations):** سياسات SELECT/UPDATE للجداول الست = `owner_id = (select auth.uid())` — **لا تذكر `deleted_at`**؛ لا سياسة DELETE؛ فوقها `app_session_gate` **restrictive** على كل الجداول = `is_current_app_session()`، والدالة **تُرجع false ولا ترمي خطأ**. trigger `bump_sync_version` يزيد `version` ويضبط `updated_at` عند كل UPDATE.
- **SQL-EXECUTED (الحذف بالشكل الحالي، بلا RETURNING):** صف حي للمالك ⇒ 1 صف؛ **صف حساب آخر ⇒ 0 صف بلا خطأ**؛ **معرّف غير موجود ⇒ 0 بلا خطأ**؛ **صف محذوف مسبقاً ⇒ 1 صف: يُعاد ختم `deleted_at` ويزيد `version`** (2→3→4)؛ **جلسة مُزاحة (Single Active Device) ⇒ 0 بلا خطأ والصف يبقى حياً**؛ الإدراج من جلسة مُزاحة ⇒ خطأ RLS صريح. ⇒ **استجابة ناجحة يمكن أن تمثّل صفر صفوف — مُثبت.** PostgREST يُرجع 204 لـ PATCH بلا تمثيل في الحالتين (CODE/وثائق؛ لم يُشغَّل PostgREST).
- **SQL-EXECUTED (مع `RETURNING id` = ما يرسله `.select('id')`):** صف حي للمالك ⇒ **يُرجَع الصف رغم ضبط `deleted_at`** (سياسة SELECT لا تُخفي المحذوف)؛ مع `and deleted_at is null`: حي ⇒ 1، محذوف مسبقاً ⇒ 0؛ حساب آخر ⇒ 0؛ غير موجود ⇒ 0؛ جلسة مُزاحة ⇒ 0؛ Brokers (منحة أعمدة تشمل `deleted_at`) ⇒ 1. ⇒ **سؤال «هل تُخفي SELECT الصف بعد الحذف المرن؟» = لا، تحت السياسات الحالية.**
- **التمييز:** صف واحد مُرجَع = **حذف حقيقي مؤكَّد**؛ صفر صفوف = {محذوف مسبقاً، ليس للحساب/غير موجود، جلسة غير حالية} — لا يُفرَّق بينها إلا بطلب متابعة (`select id, deleted_at where id`: صف بـ `deleted_at` ⇒ محذوف مسبقاً للحساب نفسه؛ لا صف ⇒ ليس له أو جلسة غير حالية — و`is_current_app_session` يفرّق الأخيرة)؛ انقطاع الشبكة = استثناء نقل كما اليوم.
- **API المثبّت (CODE، `postgrest 2.9.1`):** `update(...).eq(...).select('id')` يضيف `Prefer: return=representation` ويُرجع `List`؛ و`.count(CountOption.exact)` متاح على transform builder (Content-Range) — **لا حزمة جديدة**.
- **أصغر حل مدعوم بالدليل (للموافقة، لم يُنفَّذ) — P3.1a:** داخل `_softDelete` فقط: `.eq('id', id).isFilter('deleted_at', null).select('id')`؛ صف واحد ⇒ مؤكَّد؛ صفر ⇒ طلب متابعة واحد: محذوف مسبقاً للحساب ⇒ مؤكَّد **بلا إعادة ختم**؛ غير ذلك ⇒ خطأ نوعي («لم يُحذف») بدل نجاح صامت، مع `validateNow()` لكشف الإزاحة. الأثر: الكيانات الست، وواجهة الحذف تُظهر الفشل الحقيقي بدل «حُذف» (تغيير سلوك مرئي — قرار مالك). **لا تغيير RLS/SQL.** **ما يبقى غير مُتحقَّق:** طبقة PostgREST نفسها ⇒ تحقق على staging بحساب `authenticated` عادي (بلا service role) قبل الاعتماد.
- **FU-P2.5E-CRUD-STALE: يبقى OPEN.** بعد P3.1a يصير «حذف مؤكَّد بصف» دليلاً خادمياً؛ إزالة ذلك المعرّف من نسخة v2 تبقى **قراراً منفصلاً** (استثناء D-3). **لا تعديل لنسخة v2 بناءً على حذف غير مؤكَّد.**

### A2) اكتشاف جديد — قائمة فارغة «مرجعية» من جلسة مُزاحة (F-SAD-EMPTY) — خطر صحة، OPEN
- **SQL-EXECUTED:** جلسة A الأولى بعد أن ادّعى جهاز A الثاني الجلسة: قراءة القائمة ⇒ **0 صف بلا خطأ** (الحساب يملك صفين حيين)؛ الجهاز الحالي ⇒ 2؛ بلا `session_id` ⇒ 0.
- **CODE:** `SupabaseCoreEntitiesService` (القوائم، الأعداد، الحذف) لا يفحص `isAuthorized` ولا يمرّر الأخطاء لـ `AppSessionCoordinator`؛ الكشف = Realtime على `user_active_sessions` (قد يكون منقطعاً/في الخلفية) + فحص العودة إلى المقدمة. **قبل الكشف**، `localFirstList` يستقبل `[]` والحساب ما زال حالياً ⇒ **يعرضها ويحفظها v2 فارغة بوقت P2.5c فوق النسخة الجيدة**؛ وأعداد Home ⇒ أصفار تُحفظ في كاش الأعداد. **بعد الكشف** الهوية تصير null فيُسقط الجواب (P2.5b). سباق واقعي: العودة إلى المقدمة تطلق قراءة القائمة (P2.5b) وفحص الجلسة معاً.
- **الأثر:** لا تسريب بيانات (يُعرض أقل)؛ لكنه **ينقض دلالة «القائمة الفارغة المرجعية»** ويمسح نسخة offline جيدة حتى أول قراءة ناجحة بعد إعادة الدخول. **قاعدة صالحة:** قائمة **غير فارغة** دليل على أن البوابة سمحت وقت الاستعلام (البوابة كلّ-أو-لاشيء لكل طلب)؛ **الفارغة وحدها غامضة**.
- **حل مقترح (P3.1b، للموافقة):** قبل حفظ قائمة خادم **فارغة** (أو أعداد صفرية) تأكيد `is_current_app_session` (RPC واحد فقط عند الفراغ؛ نادر)؛ false ⇒ لا حفظ ولا عرض كمرجعية + `supersede()`. عميل فقط؛ لا تغيير RLS/Auth؛ يمسّ تفاعل SAD ⇒ قرار مالك.

### B) جرد الاستعلامات (CODE ما لم يُذكر خلافه؛ **لا أعداد مقاسة**)
| # | المسار (ملف) | المُطلِق | الطلبات | الحكم | الأثر المتوقع | التحسين الآمن |
|---|---|---|---|---|---|---|
| Q1 | `HomeViewModel._initializeSupabaseCountsWhenReady` + `_loadSupabaseCounts` (`home_viewmodel.dart`) | بدء Home | **1 + R دفعات × 7**: تحميل مباشر، ثم `onAuthStateChange` = **`ReplaySubject` غير محدود في gotrue 2.27.2** يعيد لكل مستمع جديد **كل** أحداث المصادقة السابقة (initialSession، signedIn، كل tokenRefreshed) وكل حدث بجلسة يطلق تحميلاً؛ لا دمج للطلبات الجارية | **تكرار مُثبت من المصدر** (لا مقاس) | 7–21+ طلباً عند البدء بدل 7 | دمج in-flight + تجاهل الأحداث المعادة/`tokenRefreshed` لنفس الحساب |
| Q2 | `SupabaseHomeCountsService._countActiveRows` | كل تحميل أعداد | 7 GET `select=id` + `count=exact` — **تُرجع صفوف المعرّفات أيضاً** (TESTED) | ضروري، **حمولة زائدة** | حتى 7×(حد الصفوف) معرّفاً بلا داعٍ | `from(t).count(CountOption.exact).isFilter('deleted_at', null)` = HEAD (CODE: postgrest 2.9.1) |
| Q3 | `app_routes.dart` → `refreshCounts()` | كل عودة إلى تبويب Home + السحب | 7 (+ قراءة الفلتر عند السحب) | محتمل التكرار | 7 لكل تنقل | حدّ أدنى للفاصل/الاعتماد على إشعار التعديل |
| Q4 | `CoreEntityMutationNotifier` (عام) | **أي** إضافة/تعديل/حذف | 7 أعداد + إعادة قراءة **كل** قائمة مفتوحة لكل الكيانات + الصلة + Search (6) إن حُمّل + فلتر Home | **انتشار مُثبت** | عملية Broker تعيد قراءة Requests/Offers إن كانت مفتوحة | إشعار بنوع الكيان (لاحقاً؛ يمسّ العقد) |
| Q5 | `favorites_service.dart` (`for type … await`) + `favorites_viewmodel._load*WithMetadata` | فتح المفضلة | **6 متسلسلة + N متسلسلة** (`getX(id)` لكل مفضل) + حلّ وسائط لكل Offer (`getOffer` → `resolveOfferMediaFor`) ولكل Owner | **N+1 مُثبت من المصدر** (لا مقاس) | خطّي في عدد المفضلات | `inFilter('id', ids)` لكل نوع + المسح الستة بالتوازي؛ الوسائط كسولة |
| Q6 | `getRelatedItemsCount` | تفاصيل سجل (العناصر المرتبطة) | 2 count **متسلسلان** بـ `select=id` | ضروري، متسلسل | زمن مضاعف | `Future.wait` + HEAD |
| Q7 | `DefaultSearchDataSource.load` | فتح Search/بعد تعديل | 6 قراءات **كاملة** للقوائم (كل الأعمدة + المناطق) ثم فلترة محلية | ضروري حالياً، ثقيل | حمولة كل البيانات | P4 (بحث خادمي/ترقيم) — لا تغيير الآن |
| Q8 | القوائم الست `_fetchX` عبر `_refreshedStream` | فتح القائمة/إشعار تعديل/P2.5b | 1 لكل قائمة، القائمة كاملة | ضروري؛ لا N+1 (الوسائط ليست في قائمة Offers/Owners) | — | P4 |
| Q9 | `HomeViewModel._createCombinedStream` | **فقط** حين `USE_SUPABASE_AUTH=false` | polling كل 2 ث لست قوائم كاملة | **مسار قديم ميت في الإنتاج** (الافتراضي true) | 0 حالياً | إزالته لاحقاً بقرار منفصل |

**الأعداد: فعلية = غير مقاسة؛ المستنتجة من المصدر أعلاه.** القياس (عدّاد طلبات مؤقت محلي أو Supabase API logs) يحتاج موافقة؛ لا تسجيل واسع أُضيف.

### C) اكتمال النتائج
- **TESTED:** القراءات الست `select … owner_id=eq.<uid>&deleted_at=is.null&order=created_at.desc.nullslast` — **بلا `limit`/`offset`/Range/count**، **ومفتاح ترتيب واحد** (صفوف بنفس `created_at` بلا ترتيب ثابت).
- **الحد:** PostgREST يقصّ عند `max_rows` بصمت (200 مع الصفوف الأولى = **الأحدث** حسب الترتيب)؛ `supabase/config.toml` المحلي = 1000 (وهو افتراضي Supabase الموثّق)؛ **القيمة المستضافة غير مُتحقَّق منها** (قراءتها read-only عبر Dashboard → API settings أو Management API `GET /v1/projects/{ref}/postgrest` بحساب المالك — إجراء المالك). ⇒ **أي قائمة/بحث/مفضلات (لكل نوع) فوق الحد قد تكون ناقصة بصمت**؛ أعداد Home (`count=exact`) **لا تتأثر** بالحد. النسخة المحفوظة تبقى `completeness = unknown`.
- **خيارات آمنة (P4، لم تُنفَّذ):** (1) `count=exact` مع الصفحة الأولى ⇒ كشف النقص (`length < count`) — كلفة count على الخادم؛ (2) ترقيم keyset بـ `(created_at desc, id desc)` مع مفتاح ترتيب ثانٍ؛ (3) `range()` بأحجام ≤ الحد. كلها تحافظ على فلتر `owner_id` وRLS/البوابة كمرجع. لا خطر صحة يفرض تقديمها قبل P4 **ما لم** يتجاوز حساب حقيقي ~1000 سجل في نوع واحد (غير معروف).

### الأدلة المنفّذة
- **SQL-EXECUTED (PGlite — PostgreSQL 17.5 محلي، ليس Supabase/PostgREST/الخادم المستضاف):** سكربت مؤقت في scratchpad (لم يُضف للمستودع): bootstrap لأدوار/مخطط auth، 19/19 migration، و**24 فحصاً**: 5 فحوص إعداد/حالة جلسة (ادعاء جلسات A/B ثم A على جهاز ثانٍ، و`is_current_app_session` قبل الإزاحة وبعدها) + **19 سيناريو حذف/قراءة** (S1–S4 بما فيها S1b/S1c، R1–R6، X1–X7) + فحص إعادة ختم `deleted_at` عند الحذف المكرر. (تصحيح: ذكر تقرير سابق «22 سيناريو» خطأً.) لا SQL على أي قاعدة مستضافة؛ لا service role لمحاكاة المستخدم.
- **جديد `test/lists/core_entity_query_contract_test.dart` — 3/3 PASS** (characterization، لا تغيير سلوك): الحذف الستة PATCH بلا تأكيد و204 = نجاح + 6 إشعارات؛ القراءات الست بلا limit/range/count و`[]` = قائمة فارغة؛ أعداد Home = 7 GET بـ `select=id` + `count=exact`. مع `core_entity_refresh_stream_test` ⇒ 6/6. Analyzer → No issues. Format → 0 تغييرات.
- **لم يُعَد الانحدار الواسع:** لا تغيير في `lib/`.

### توصيات P3.1 مرتّبة (كلها تنتظر الموافقة)
1. **P3.1a — تأكيد الحذف المرن** (صحة؛ الأعلى): كما في A أعلاه + تحقق staging بحساب عادي. **نقطة البدء الموصى بها.**
2. **P3.1b — F-SAD-EMPTY** (صحة): تأكيد الجلسة قبل حفظ قائمة/أعداد فارغة.
3. **P3.1c — أعداد Home بـ HEAD** (أداء، خطر منخفض، بلا تغيير دلالي).
4. **P3.1d — دمج تحميلات أعداد Home** (أداء؛ إزالة تكرار الإعادة من `ReplaySubject`).
5. **P3.1e — المفضلات بدفعات** (أداء؛ N+1).
6. **P3.1f — `getRelatedItemsCount` متوازٍ + HEAD** (أداء صغير).
7. لاحقاً: إشعار تعديل بنوع الكيان (Q4)؛ إزالة مسار polling الميت (Q9)؛ **P4** للترقيم/الاكتمال/مفتاح الترتيب الثاني.

### قرارات تحتاج المالك
- اعتماد P3.1a (يغيّر عقد CRUD المشترك ويُظهر فشل الحذف الحقيقي للمستخدم) + تحقق staging.
- اعتماد P3.1b (تفاعل مع Single Active Device على العميل فقط).
- بعد P3.1a: هل تُزال المعرّفات المؤكَّد حذفها من نسخة v2 (استثناء D-3) لإغلاق FU-P2.5E-CRUD-STALE.
- قراءة `max_rows` المستضاف (read-only، بحساب المالك).
- قياس أعداد الطلبات الفعلية (أداة مؤقتة محلية أو سجلات Supabase).

### الحالة و NOW / NEXT / STOP
- **نتائج مفتوحة (OPEN، غير محلولة):** (1) **F-SAD-EMPTY** — جلسة مُزاحة قد تُرجع قائمة فارغة مضلِّلة تُحفظ فوق نسخة صالحة؛ (2) **FU-P2.5E-CRUD-STALE** — الحذف المرن قد يُرجع نجاحاً دون تعديل أي صف (والنسخة المحفوظة قد تُبقي محذوفاً)؛ (3) **تكرار محتمل لاستعلامات أعداد Home** (Q1، مُثبت من المصدر، غير مقاس)؛ (4) **N+1 في المفضلات** (Q5)؛ (5) **`max_rows` المستضاف غير مُتحقَّق منه واكتمال القوائم unknown**.
- **P3.0 = AUDIT COMPLETE** (SQL-EXECUTED محلياً + TESTED + CODE؛ لا MEASURED؛ لا REAL_DEVICE). **FU-P2.5E-CRUD-STALE OPEN**؛ **F-SAD-EMPTY OPEN** (جديد). البناء الأصلي لـ `connectivity_plus` **UNVERIFIED**؛ Samsung D-7..D-50 **DEFERRED BY OWNER**. FU-OWNERS-R5C **RESOLVED**؛ التاريخي (Delete Account migration-file) **OPEN**.
- **الملفات (غير مدمجة):** جديد `test/lists/core_entity_query_contract_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك؛ موافقة منفصلة على commit لهذين الملفين.
- **NEXT:** قرار P3.1a (الموصى به أولاً) أو غيره من القائمة.
- **STOP:** لا تغيير لسلوك CRUD أو الاستعلامات الإنتاجي؛ لا P3.1/P4 تلقائياً؛ لا commit/push.
- **أُودع** بموافقة المالك: `b4d7a1c` `test(supabase): document query and CRUD contract risks`، ودفعه المالك (`origin` = `b4d7a1c`، §7AA).

---

## 7AA) P3.1b — منع الكتابة فوق الكاش بقائمة فارغة كاذبة (F-SAD-EMPTY) — 2026-11-02 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `b4d7a1c` = `origin` (0/0)، نظيف، stashes = 2.

### السبب الجذري (من §7Z، SQL-EXECUTED على PGlite)
`app_session_gate` سياسة **restrictive** و`is_current_app_session()` **تُرجع false ولا ترمي**، فقراءة قائمة من جلسة مُزاحة = **0 صف بلا خطأ**. قبل أن يكتشف التطبيق الإزاحة (Realtime منقطع/العودة إلى المقدمة)، كان `localFirstList` يعامل `[]` كقائمة خادم مرجعية: **يعرضها ويحفظها v2 فارغة بوقت P2.5c فوق نسخة صالحة.** **استُنسخ باختبار قبل الإصلاح:** مع تمرير المعامل الجديد دون استعماله، فشل 12 اختباراً، منها «قائمة الجلسة المُزاحة الفارغة لا تستبدل النسخة المحفوظة» (كانت تُحفظ فارغة).

### الإصلاح (أصغر حماية مشتركة؛ السلطة نفسها، لا نظام صلاحيات ثانٍ)
- **القاعدة:** قائمة **بصفوف** = البوابة سمحت (البوابة كل-أو-لاشيء لكل طلب) ⇒ **لا فحص**. قائمة **فارغة** لحساب مسجّل ⇒ تُقبل **فقط** بعد أن تؤكد قاعدة البيانات أن الجلسة ما زالت الحالية.
- **جديد `lib/src/services/list_session_check.dart`:** `ListSessionCheck.confirmCurrent()` يستدعي **`AppSessionCoordinator.validateNow()` القائم** (RPC `is_current_app_session`؛ عند false يستدعي `supersede()` القائم ⇒ مسار تسجيل الخروج المعتاد **يُطلق ولا يُتجاوز**). `null` حين لا يوجد coordinator (لا جلسة تطبيق Supabase ⇒ لا بوابة ⇒ السلوك السابق). **مشاركة فحص واحد جارٍ لكل جلسة** (`shared(sessionId, validate)`)؛ **لا يُحفظ أي جواب بعد وصوله ولا يُشارك بين جلستين**؛ جلسة بلا `session_id` ⇒ غير مؤكَّدة. `ListSessionNotCurrent` = خطأ «القائمة الفارغة غير موثوقة».
- **`lib/src/services/app_session_coordinator.dart`:** **getter قراءة فقط** `static AppSessionCoordinator? get active => _active;` (4 أسطر بالتعليق) — السجل `_active` موجود ويستعمله `reportBackendError` أصلاً. **لا تغيير** في `validateNow`/`authorize`/`supersede`/claim/Realtime أو أي قرار.
- **`localFirstList` (`encrypted_account_list_cache.dart`):** معامل اختياري `confirmEmptyList` (افتراضياً `ListSessionCheck.confirmCurrent`؛ **الخدمات الست بلا تغيير**). قائمة فارغة ⇒ تبقى «refreshing» (`inFlight`؛ لا قراءة ثانية من تلميح/محاولة) والشاشة تُبقي ما تعرضه، ثم:
  - **مؤكَّدة** ⇒ تُعرض وتُحفظ فارغة بوقتها كما قبل (السلوك الصحيح محفوظ).
  - **false** ⇒ **لا عرض، لا حفظ، لا تقدّم للوقت**؛ `ListSessionNotCurrent` يُمرَّر مرة؛ القائمة **تتوقف** (كخطأ جلسة في P2.5b).
  - **فشل شبكة أثناء الفحص** ⇒ كفشل شبكة: النسخة تبقى، محاولات P2.5b المحدودة، ولا تقدّم للوقت. **أي فشل آخر** ⇒ توقف.
  - **تحقق بعد الانتظار:** قائمة أحدث وصلت (عدّاد `deliveries`) ⇒ الجواب القديم يُسقط؛ الشاشة أُغلقت أو القائمة توقفت ⇒ لا شيء؛ **الحساب تغيّر/خرج** ⇒ توقف بلا عرض أو حفظ لأي حساب. مصدر انتهى أثناء الفحص ⇒ يُغلق **بعد** الفحص.
- **بلا تغيير:** صيغ الكاش، v2/HMAC، D-1a/D-2/D-3، المفاتيح، العزل، P2.5b/P2.5b-2، P2.5c، الواجهة، CRUD و`_softDelete`، SQL/RLS/Auth.

### الأدلة (شغّلها الوكيل؛ تصريح دائم §7L)
- **جديد `test/lists/list_false_empty_test.dart` — 19/19 PASS:** مؤكَّدة: فارغة شرعية تستبدل النسخة بوقتها (فحص واحد)؛ بلا نسخة ⇒ فارغة تُعرض وتُحفظ؛ قائمة بصفوف لا تُفحص أبداً (0 فحص)؛ أثناء الفحص الشاشة تُبقي النسخة وrefreshing؛ تلميح أثناء الفحص لا يطلق قراءة ثانية. غير مؤكَّدة: **جلسة مُزاحة ⇒ النسخة [a1,a2] ووقتها t0 باقيان، لا عرض، `ListSessionNotCurrent`، `savedCopy` + `lastReadFailed`**؛ بلا نسخة ⇒ لا عرض ولا حفظ؛ فشل شبكة أثناء الفحص ⇒ النسخة باقية ثم محاولة، ومؤكَّدة بعدها تستبدل؛ فشل آخر ⇒ توقف بلا محاولة. التزامن: تبديل الحساب أثناء الفحص ⇒ لا شيء لأي حساب ولا حالة؛ خروج أثناء الفحص؛ إغلاق الشاشة؛ قائمة أحدث تفوز؛ مصدر ينتهي بعد الفحص. الفحص المشترك: فحص جارٍ واحد للجلسة نفسها، منفصل لجلسة أخرى، ولا احتفاظ بعد الجواب (نجاح أو فشل)؛ جلسة بلا id غير مؤكَّدة؛ بلا coordinator ⇒ `null`، ومع coordinator بلا جلسة ⇒ false. **الشاشات الست عبر خدماتها الحقيقية والفحص الافتراضي:** قائمة بصفوف تُحفظ بلا فحص؛ فارغة غير مؤكَّدة ⇒ النسخة ووقتها باقيان؛ فارغة مؤكَّدة ⇒ تستبدل (فحص واحد لكل قائمة فارغة).
- **فحص الطفرات — 13/13 التُقطت** (الملفان أُعيدا من نسخة احتياطية، `Get-FileHash` مطابق؛ لا `git restore`): عدم فحص الفارغة؛ قبولها حين false؛ إسقاط حارس القائمة الأحدث؛ إسقاط فحص الحساب بعد الانتظار؛ إسقاط فحص الإغلاق؛ فشل شبكة = رفض؛ فحص القوائم ذات الصفوف؛ الإغلاق قبل الفحص؛ عدم إبقاء refreshing (**نجا أولاً** — أُضيف اختبار التلميح فالتُقط)؛ عدم مشاركة الفحص الجاري؛ مشاركته بين جلستين؛ الاحتفاظ بالجواب؛ تأكيد جلسة بلا id.
- **مجموعات مرتبطة** (`test/lists/`، `test/home/`، `test/favorites/`، `map_sdk_warmup_test`، `delete_account_test`، **كل `test/auth/`** لأن `app_session_coordinator.dart` تغيّر، الشاشات الست + `r5d_related_cards_test`) → **1239 PASS، 9 FAIL**، مصنّفة: (1) **`list_refresh_test` «each list recovers … when the app resumes» = تذبذب توقيت تحت الحمل** (شُغّل Analyzer بالتوازي فاستغرق 204 ث): ينجح منفرداً، و**`test/lists/` كاملاً 303/303 PASS** في إعادة نظيفة؛ (2) **التاريخي** `delete_account_test` (migration-file، OPEN)؛ (3) **7 إخفاقات قائمة في `test/auth/` غير مرتبطة** — `email_change_test` (1)، `phone_security_hardening_test` (4، اختبارات ملفات migration)، `session_superseded_dialog_test` (2) — **مُثبت أنها نفسها على `b4d7a1c`**: وُضعت نسختا HEAD من الملفين المعدّلين مؤقتاً (نسخ يدوي، لا `git restore`/stash) ⇒ **السبعة نفسها تفشل** (34 PASS، 7 FAIL)، ثم أُعيدت ملفاتي و`Get-FileHash` مطابق. **مسجّلة كـ FU-AUTH-BASELINE-7 OPEN** (لم تُرصد سابقاً لأن انحدارات P2 لم تشمل `test/auth/` كاملاً). **FU-OWNERS-R5C الخمسة PASS.**
- **Analyzer** (الملفات الثلاثة + `test/lists/`) → No issues. **Format:** الملفان الجديدان مُنسَّقان؛ `encrypted_account_list_cache.dart` مطابق للمنسِّق (عدا CRLF)؛ `app_session_coordinator.dart` **لم يُنسَّق** — فيه انحرافات تنسيق **قائمة في HEAD** (نسخة HEAD تتغيّر أيضاً بالتنسيق)، وأسطري الأربعة ليست ضمنها. **`git diff --check`** → نظيف.

### Home counts — الخطر نفسه، **غير معالج** (موثّق فقط)
`SupabaseHomeCountsService._countActiveRows` (7 جداول، RLS + البوابة) ⇒ جلسة مُزاحة غير مكتشفة تُرجع **أصفاراً بلا خطأ**؛ `HomeViewModel._handleCombinedUpdate` يعرضها ويحفظها في كاش الأعداد (R-02، لكل حساب). **النطاق:** عرض أعداد صفرية وحفظها حتى التحميل المُصرَّح التالي (بعد إعادة الدخول)؛ لا تسريب. **العلاج المقترح (قرار منفصل):** الفحص نفسه قبل قبول مجموعة أعداد **كلها أصفار** (أو أي صفر). لم يُنفَّذ — خارج نطاق القوائم الست.

### المخاطر المتبقية
- **طبقة PostgREST/الخادم المستضاف غير مُتحقَّق منها** (الإثبات SQL محلي + Dart)؛ **Samsung/البناء الأصلي DEFERRED/UNVERIFIED** (D-51 أدناه).
- كلفة: RPC واحد لكل قائمة خادم **فارغة** لحساب مسجّل (يُشارَك أثناء الطيران)؛ القوائم ذات الصفوف بلا كلفة.
- `validateNow` يُرجع false دون RPC إن لم تكن الجلسة مُصرَّحاً بها محلياً بعد (مثلاً أثناء إعادة التحقق عند البدء) ⇒ القائمة الفارغة لا تُقبل وتتوقف القائمة حتى إعادة فتحها — تحفّظ مقصود (fail-closed).
- لا يغطي البحث (`DefaultSearchDataSource`) ولا المفضلات ولا العناصر المرتبطة (لا تكتب الكاش المشفّر).

### الحالة و NOW / NEXT / STOP
- **تاريخ (المراجعة الأمنية النهائية، 2026-11-02 — لم يُودع حينها):** وُجد خلل في P3.1b: **F-SAD-EMPTY-ABA** — الجواب الفارغ لا يُربط **بالجلسة التي أرسلت الطلب**؛ الفحص يؤكد الجلسة **الحالية وقت الفحص** والحساب فقط. **مُثبت باختبار مؤقت (حُذف):** قراءة بدأت تحت `s1` (مُزاحة)، ثم خروج ودخول بالحساب نفسه (`s3`)، ثم وصل جواب `s1` الفارغ ⇒ فُحص `s3` فقط ⇒ **النسخة الصالحة `[a1]` استُبدلت بـ `[]`**. **الوصول عملياً اليوم:** ViewModel القائمة يُنشأ داخل شاشتها (`requests_list_view.dart:32`) والخروج يعيد التوجيه خارج الـ shell، فالشاشة تُغلق قبل الدخول ثانية — **لكن الضمان يعتمد على التنقل لا على `localFirstList`**، ومتطلب «اتساق الجلسة قبل الفحص وبعده» **غير مستوفى**. **الإصلاح المقترح (ينتظر الموافقة):** التقاط `session_id` عند بدء القراءة (`listenToServer`) وتمريره إلى الفحص؛ الفحص يرفض (false) إن اختلفت الجلسة الحالية عنه، ويبقى الفحص المشترك مقيّداً بتلك الجلسة؛ مع اختبار انحدار لهذا السيناريو. ⇒ **F-SAD-EMPTY = PARTIALLY ADDRESSED / NOT COMMITTED** حتى الإصلاح والتحقق.
- **F-SAD-EMPTY (القوائم الست) = CODE_PROVEN** (بعد إصلاح ABA في §7AA-1 ونجاح كل فحوص الانحدار المطلوبة) — ليس REAL_DEVICE_VERIFIED. **Home counts: OPEN** (موثّق). **FU-P2.5E-CRUD-STALE: OPEN.** FU-OWNERS-R5C **RESOLVED**؛ التاريخي (Delete Account migration-file) **OPEN**؛ **FU-AUTH-BASELINE-7 OPEN** (7 إخفاقات `test/auth/` قائمة على `b4d7a1c`، غير مرتبطة). Samsung D-7..D-51 **DEFERRED BY OWNER**؛ `connectivity_plus` الأصلي **UNVERIFIED**.
- **الملفات (غير مدمجة):** جديد `lib/src/services/list_session_check.dart`؛ `lib/src/services/encrypted_account_list_cache.dart`؛ `lib/src/services/app_session_coordinator.dart` (getter فقط)؛ جديد `test/lists/list_false_empty_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك؛ موافقة منفصلة على commit.
- **NEXT:** **P3.1a — تأكيد الحذف المرن** (§7Z)؛ وقرار منفصل لحماية أعداد Home.
- **STOP:** لا P3.1a تلقائياً؛ لا commit/push.

### 7AA-1) إصلاح F-SAD-EMPTY-ABA — ربط كل جواب بالجلسة التي أرسلت الطلب — 2026-11-02 (بموافقة المالك؛ غير مدمج)
- **السبب الجذري:** كان قبول الجواب يتحقق من **الحساب** فقط، والقائمة الفارغة تُفحص على الجلسة **الحالية وقت الفحص**؛ لا شيء يربط الجواب **بالجلسة التي بدأت القراءة**. خروج ثم دخول بالحساب نفسه (جلسة جديدة) أثناء قراءة معلّقة ⇒ جواب الجلسة القديمة الفارغ يُفحص على الجديدة ويُقبل فوق نسخة صالحة.
- **هوية الجلسة:** `session_id` من access token (`AppSessionCoordinator.sessionId`) — **ثابت عبر token refresh** (صف `auth.sessions` نفسه) و**جديد مع كل تسجيل دخول** حتى للحساب نفسه. **مُثبت باختبار** على عميل Supabase حقيقي: refresh بالـ `session_id` نفسه ⇒ الجلسة نفسها؛ دخول جديد ⇒ جلسة أخرى.
- **الإصلاح:**
  - `ListSessionCheck.currentSession()` (جديد): الجلسة الحالية أو null بلا coordinator. `confirmEmptyList` صار **يُعطى جلسة القراءة** (`confirmFor(session)`)؛ `bound(session, current, validate)`: **جلسة غير الحالية ⇒ false دون أي طلب** — فجلسة أقدم لا تُؤكَّد ولا تستطيع إطلاق `supersede()` على أحدث (والـ coordinator نفسه يملك أصلاً حارس `sessionId(current) == id` قبل `supersede`). الفحص المشترك الجاري مقيّد **بالجلسة نفسها بالضبط**.
  - `localFirstList`: معامل `sessionOf` (افتراضياً `currentSession`)؛ **`readSession` يُلتقط في `listenToServer` قبل `server()`** (قبل إرسال الطلب). `stillTheReader()` = الحساب **و**الجلسة كما عند بدء القراءة؛ يُطبَّق على **كل** جواب (فارغ أو بصفوف، **بلا RPC إضافي للقوائم ذات الصفوف**)، وعلى **كل فشل**، و**بعد** الفحص قبل العرض/الحفظ، وفي `mayRecover` (D-2). عدم التطابق ⇒ **يُسقط الجواب بلا عرض ولا حفظ ولا تقدّم للوقت ولا خطأ**، وتتوقف القائمة (شاشة تلك الجلسة انتهت).
  - **بلا تغيير:** الخدمات الست، الواجهة، صيغ الكاش وv2/HMAC، D-1a/D-2/D-3، P2.5b/P2.5b-2، P2.5c، `AppSessionCoordinator` (عدا getter القراءة من §7AA)، SQL/RLS/Auth، `_softDelete`.
- **الأدلة (شغّلها الوكيل):**
  - **استنساخ قبل الإصلاح:** مع المعاملات الجديدة دون الحارس، فشل **4** اختبارات: الجواب الفارغ المتأخر بعد خروج ودخول (**الاستنساخ الأصلي**)، الجواب بصفوف المتأخر، تغيّر الجلسة أثناء الفحص، فشل متأخر من الجلسة القديمة. بعد الحارس: كلها PASS.
  - **`test/lists/list_false_empty_test.dart` — 29/29 PASS** (19 السابقة + 10؛ صارت 31/31 بعد الفحص النهائي لـ D-2 أدناه): جواب `s1` فارغ متأخر بعد `s3` ⇒ النسخة ووقتها باقيان، **0 فحص**؛ جواب `s1` بصفوف متأخر ⇒ مُسقط؛ تغيّر الجلسة أثناء `validateNow` ⇒ الجواب «current» مُسقط والفحص سُئل عن `s1` فقط؛ token refresh (نفس `session_id`) ⇒ يُقبل الفارغ المؤكَّد وذو الصفوف؛ حسابان مختلفان ⇒ لا شيء لأيّهما؛ خروج أثناء قراءة معلّقة ⇒ مُسقط؛ فشل `s1` متأخر ⇒ لا خطأ يُعرض ولا يمسّ `s3`؛ قراءة إعادة المحاولة تحت `s3` تُفحص لـ `s3` وتُقبل؛ `bound`: جلسة أقدم/بلا id ⇒ false **بلا validate**؛ هوية الجلسة على عميل Supabase حقيقي (refresh vs دخول جديد) و`confirmFor` لجلسة أقدم ⇒ false بلا RPC.
  - **فحص الطفرات — 19/19 التُقطت** (13 السابقة بمقاطع محدّثة + 6 جديدة: إسقاط مقارنة الجلسة؛ حارس الجواب/الفشل/نتيجة الفحص بالحساب فقط؛ التقاط الجلسة مرة واحدة لا لكل قراءة؛ السماح بالتحقق لجلسة أقدم). الملفان أُعيدا و`Get-FileHash` مطابق.
  - **انحدار (تشغيل منفرد، بلا Analyzer موازٍ):** `test/lists/`، `test/home/`، `test/favorites/`، `map_sdk_warmup_test`، `delete_account_test`، كل `test/auth/`، الشاشات الست + `r5d_related_cards_test` → **1250 PASS، 8 FAIL = المعروفة فقط بالضبط:** FU-AUTH-BASELINE-7 (السبعة نفسها المُثبتة على `b4d7a1c` في §7AA) + التاريخي (Delete Account migration-file). **لا فشل جديد، ولا تذبذب** هذه المرة. **FU-OWNERS-R5C الخمسة PASS.**
  - **Analyzer** (الملفات الثلاثة + `test/lists/`) → No issues. **Format:** `list_session_check.dart` و`list_false_empty_test.dart` → 0 تغييرات. **`git diff --check`** → نظيف.
- **فحص نهائي مستهدف لمسار D-2 `mayRecover` (موافقة المالك):** نافذة الحارس = بعد أن يقبل `accept()` القائمة (الجلسة مطابقة) وقبل أن تقيّم الكتابة المؤجّلة `mayRecover` داخل طابور الصندوق. **اختباران جديدان** (`list_false_empty_test.dart`، مع مخزن مفاتيح حقيقي يمكن إيقاف قراءته التالية): صندوق Alice موجود ومفتاحه مفقود (غير مقروء)؛ قائمة خادم تحت `s1` تُقبل وتُوقَف كتابتها عند قراءة المفتاح؛ **خروج ودخول بالحساب نفسه ⇒ `s3`**؛ ثم تُطلق ⇒ **لا مفتاح جديد (0 كتابة، المفتاح يبقى null)، ملف الصندوق المشفّر بايت-بايت كما كان، لا شيء في `.recovery`، و`readSaved` = null (لا قائمة ولا وقت)**. **ضابط:** السيناريو نفسه بلا تغيّر جلسة ⇒ **يُسترد** (مفتاح جديد، القائمة ووقتها محفوظان) — يُثبت أن الاختبار يصل فعلاً إلى الاسترداد. **طفرة معزولة** `mayRecover: stillTheReader` → `stillTheAccount` ⇒ **التُقطت** (يفشل اختبار D-2 وحده)؛ الملف أُعيد و`Get-FileHash` مطابق. ⇒ `list_false_empty_test.dart` **31/31 PASS**؛ Analyzer → No issues؛ Format → 0. **لم يُعَد الانحدار الواسع** (لا تغيير إنتاجي منذ تشغيل 1250 PASS / 8 المعروفة).
- **أُودع** بموافقة المالك: `9e45013` `fix(offline): bind server list responses to originating sessions` (5 ملفات)، ودفعه المالك (`origin` = `9e45013`، §7AB).
- **الحدود المتبقية:** عدم التطابق يوقف القائمة حتى إعادة فتح الشاشة (تحفّظ مقصود)؛ طبقة PostgREST وSamsung (D-51) غير مُتحقَّق منهما؛ أعداد Home غير محمية.

---

## 7AB) P3.1a — الحذف المرن المُتحقَّق منه (Verified Soft Delete) — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `9e45013` = `origin` (0/0)، نظيف، stashes = 2.

### المشكلة (من §7Z، مُثبتة)
`_softDelete` = `update({deleted_at}).eq('id', id)` بلا تمثيل: PostgREST يُرجع نجاحاً حتى إن **لم يتغيّر أي صف** (صف حساب آخر، معرّف غير موجود، جلسة مُزاحة)، و**الحذف المكرر يعيد ختم `deleted_at` ويزيد `version`**. **استُنسخ باختبار قبل الإصلاح:** بإضافة نوع الخطأ فقط، فشل **19** اختباراً (منها «لا صف يمكن تعديله ⇒ لم يُحذف» — كان يُعدّ نجاحاً ويُبلَّغ القوائم).

### الإصلاح (مكان واحد مشترك: `SupabaseCoreEntitiesService._softDelete` — 8 مستدعين: الحذف الستة + تراجعا إنشاء Request/Offer)
1. `update({'deleted_at': now}).eq('id', id).isFilter('deleted_at', null).select('id')` ⇒ `PATCH …?id=eq.<id>&deleted_at=is.null&select=id` + `Prefer: return=representation` (`postgrest 2.9.1`). **id مُرجَع = تأكيد الخادم** (طلب واحد كما قبل).
2. **صفر صفوف ⇒ قراءة واحدة** `select('id').eq('id', id).not('deleted_at','is',null)`: صف ⇒ **محذوف مسبقاً لهذا الحساب ⇒ نجاح بلا إعادة ختم** (`deleted_at` و`version` كما هما).
3. غير ذلك ⇒ `CoreEntityNotDeleted` (عام: **لا يذكر الجدول ولا المعرّف ولا السبب** — فلا يكشف وجود سجل لحساب آخر)، **بلا إشعار تعديل**، ويُستدعى فحص الجلسة القائم (`ListSessionCheck.confirmFor` ⇒ `validateNow`) فتُكتشف الإزاحة ويبدأ الخروج المعتاد.
4. أخطاء الشبكة والتفويض (`PostgrestException` 401/403…) **تُمرَّر كما هي**.
- **أثر مرئي (بلا تغيير كود واجهة):** حذف لم يؤكّده الخادم صار يمرّ في **مسار الفشل القائم** (`EntityDeleteOutcome.failed`: العنصر يبقى + رسالة «Unable to delete … Please try again.» الموجودة) بدل «حُذف» الصامت. تنظيف وسائط Offer/Owner المحلية بعد الحذف **لا يجري** لحذف غير مؤكَّد (يجري للمحذوف مسبقاً).
- **بلا تغيير:** الواجهة، واجهات CRUD، `EntityListState`، الخدمات الست، P3.1b، الكاشات وv2/HMAC، D-1a/D-2/D-3، SQL/RLS/Auth/SAD.

### الأدلة
- **SQL-EXECUTED (PGlite — PostgreSQL 17.5 محلي، 19/19 migration، دور `authenticated` بـ JWT claims؛ ليس PostgREST/Supabase/المستضاف)**، بالشكلين الدقيقين اللذين يرسلهما العميل: صف حي للمالك ⇒ **VERIFIED** (version 1→2)؛ **المكرر ⇒ ALREADY DELETED، version وdeleted_at بلا تغيير**؛ محاولة ثانية متتالية (بديل التزامن) ⇒ ALREADY DELETED بلا تغيير؛ معرّف غير موجود ⇒ NOT DELETED؛ **صف حي لحساب آخر ⇒ NOT DELETED وصفّه بلا مساس**؛ **صف محذوف لحساب آخر ⇒ NOT DELETED (الجواب نفسه للمفقود — لا كشف وجود)**؛ Brokers (منحة أعمدة) ⇒ VERIFIED؛ **جلسة مُزاحة ⇒ NOT DELETED والصف حي بلا مساس** (وكذلك للمحذوف مسبقاً)؛ الجهاز الحالي ⇒ VERIFIED؛ بلا `session_id` ⇒ NOT DELETED. **التزامن الحقيقي غير مُنفَّذ** (PGlite اتصال واحد): يعتمد على سلوك PostgreSQL الموثّق في READ COMMITTED — المحدِّث الثاني ينتظر قفل الصف ثم يعيد تقييم `deleted_at is null` على النسخة المحدَّثة ⇒ 0 صف ⇒ القراءة تجده محذوفاً.
- **جديد `test/lists/verified_soft_delete_test.dart` — 31/31 PASS** (بديل PostgREST مسجِّل): لكل كيان من الستة: صف حي ⇒ PATCH واحد بـ `id`، `deleted_at=is.null`، `select=id`، `return=representation`، جسم `deleted_at` فقط ⇒ مُتحقَّق + إشعار، بلا فحص جلسة؛ محذوف مسبقاً ⇒ PATCH واحد بلا إعادة ختم + قراءة `deleted_at=not.is.null` ⇒ نجاح + إشعار؛ لا صف ⇒ `CoreEntityNotDeleted` (نصّه بلا المعرّف ولا الجدول)، PATCH ثم GET، **0 إشعار، فحص جلسة واحد**؛ 401 ⇒ `PostgrestException` كما هو بلا إشعار؛ فشل نقل ⇒ يُمرَّر بلا إشعار ولا فحص. حذفان متتاليان للصف نفسه ⇒ يتغيّر مرة واحدة ولا يُعاد الختم.
- **`core_entity_query_contract_test.dart` (P3.0) حُدِّث عمداً** (لا إخفاء): اختبار الحذف كان يثبّت العقد القديم (204 بلا صف = نجاح)؛ صار يثبّت الجديد (PATCH بالفلاتر والتمثيل، ثم GET، و`CoreEntityNotDeleted`، 0 إشعار). اختبارا القوائم والأعداد بلا تغيير. ⇒ 3/3؛ مع `verified_soft_delete_test` و`core_entity_refresh_stream_test` ⇒ **37/37**.
- **فحص الطفرات — 7/7 ذات معنى التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): إسقاط فلتر «غير محذوف»؛ أي نجاح يُعدّ حذفاً؛ إسقاط قراءة «محذوف مسبقاً»؛ القراءة تتجاهل `deleted_at`؛ إسقاط استدعاء فحص الجلسة؛ الإشعار قبل التأكيد؛ الرفض يُعدّ نجاحاً. **مستبعدتان بصدق:** طفرة «بلا `select`» لم تُترجم (ومغطاة بالطفرة الثانية واختبار المعاملات)، وطفرة إسقاط معالج خطأ الفحص **مكافئة** (الفحص يُطلق عند استدعاء `confirmFor` نفسه).
- **انحدار (منفرد):** `test/lists/`، `test/home/`، `test/favorites/`، `test/offers/`، `test/owners/` (حذف عبر الخدمات)، `test/related_items/`، `delete_account_test`، الشاشات الست + `r5d_related_cards_test` → **1366 PASS، 1 FAIL = التاريخي فقط** (Delete Account migration-file). **FU-OWNERS-R5C الخمسة PASS.** `test/auth/` لم يُعَد (لا يستورد المسار المتغيّر؛ FU-AUTH-BASELINE-7 كما في §7AA).
- **Analyzer** (الملف + الاختباران) → No issues. **Format:** الاختباران 0 تغييرات؛ `supabase_core_entities_service.dart` صُحّح يدوياً سطر واحد من أسطري فصار مطابقاً للمنسِّق (عدا CRLF)، ثم أُعيدت الاختبارات المركّزة ⇒ 37/37. **`git diff --check`** → نظيف.

### FU-P2.5E-CRUD-STALE — تصميم الحل (لم يُنفَّذ؛ **يتطلب استثناءً من D-3 ⇒ قرار المالك**)
- **ما صار ممكناً:** «حذف مُتحقَّق منه» (id مُرجَع، أو صف محذوف مسبقاً مؤكَّد بالقراءة) **دليل خادمي** لكل معرّف.
- **أصغر تصميم آمن:** بعد نجاح `_softDelete` المُتحقَّق منه، خدمة الكيان تستدعي `cache.forgetConfirmedDeletion(uid, id)` (جديد في النواة) تحت طابور الصندوق نفسه: تقرأ v2 **وتتحقق من وسمه**؛ إن وُجد العنصر تُزيله **فقط** وتعيد ختم v2 بمفتاح الـ MAC نفسه، **بلا سجل وقت** (فيصير الوقت «غير معروف» لأن القائمة لم تعد مطابقة لقائمة خادم)؛ **لا إضافة ولا تعديل** لأي سجل؛ v1 القديم وصندوق غير مقروء أو فاشل السلامة **لا يُمسّ**؛ للحساب الحالي فقط وبالجلسة نفسها (P3.1b)؛ يحتاج دالة `idOf` في الأغلفة الست (سطر لكل غلاف).
- **الاستثناء المطلوب من D-3 (نصّاً):** «يجوز كتابة v2 أيضاً من **قائمة v2 مُتحقَّق منها ناقصاً سجلات أكّد الخادم حذفها**» — يضيّق فقط، ولا يُنشئ بيانات.
- **الحدود:** قراءة خادم أقدم (بدأت قبل الحذف) تصل بعد الإزالة قد تعيد العنصر حتى القراءة التالية؛ الإضافة/التعديل يبقيان «أقل/أقدم» (لا كتابة محلية لهما — ذلك O-work).
- **STOP:** لا تنفيذ دون موافقة منفصلة.

### الحالة و NOW / NEXT / STOP
- **مراجعة نهائية مركّزة (2026-11-03، موافقة المالك) — لا خلل جديد:** المستدعون الثمانية روجعوا: الحذف الستة عبر `_softDeleteAndNotify` (الإشعار **بعد** التأكيد فقط)، وتراجعا إنشاء Request/Offer داخل `try/catch` ⇒ `_debugError` ثم إعادة رمي الخطأ الأصلي (العقد الخارجي نفسه؛ تراجع لم يغيّر صفاً صار يُسجَّل فشلاً بدل «rolled back» كاذب). تبديل الحساب بين PATCH والقراءة ⇒ القراءة تحت RLS الحساب الجديد لا ترى الصف ⇒ NOT DELETED (متحفّظ)؛ إعادة الدخول للحساب نفسه ⇒ «محذوف مسبقاً» يعكس حالة الخادم الفعلية لا تفويضاً قديماً؛ الإشعار يُطلق قراءات تحميها P3.1b بالجلسة. **لم يُعَد الانحدار الواسع** (لا تغيير كود منذ 37/37 و1366 PASS).
- **P3.1a = CODE_PROVEN** (SQL محلي + اختبارات Dart + طفرات) — **ليس REAL_DEVICE_VERIFIED ولا STAGING_VERIFIED**. **تحقق PostgREST على staging: PENDING** (أدلة PGlite المحلية ليست تحققاً مستضافاً). **مانع للتحقق الكامل:** تحقق staging بحساب `authenticated` عادي (بلا service role) لشكل `PATCH … select=id` و`deleted_at=not.is.null` على PostgREST الفعلي — إجراء المالك.
- **FU-P2.5E-CRUD-STALE: OPEN** (التصميم أعلاه ينتظر قرار D-3). Home false-zero **OPEN**؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي **OPEN**؛ Samsung/البناء الأصلي **DEFERRED/UNVERIFIED** (D-52 أدناه).
- **الملفات (غير مدمجة):** `lib/src/services/supabase_core_entities_service.dart`؛ جديد `test/lists/verified_soft_delete_test.dart`؛ `test/lists/core_entity_query_contract_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك وموافقة على commit. **NEXT:** قرار استثناء D-3 لـ FU-P2.5E-CRUD-STALE، أو حماية أعداد Home، أو تحقق staging. **STOP:** لا commit/push؛ لا بدء تحسينات Home تلقائياً.
- **أُودع** بموافقة المالك: `7278e15` `fix(supabase): verify affected rows before confirming soft delete` (4 ملفات)، ودفعه المالك (`origin` = `7278e15`، §7AC).

---

## 7AC) P3.1c — حماية أعداد Home من الأصفار الكاذبة (Home False-Zero) — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `7278e15` = `origin` (0/0)، نظيف، stashes = 2.

### السبب الجذري
`SupabaseHomeCountsService._countActiveRows` (7 جداول) يمرّ عبر RLS + `app_session_gate` الذي **يرشّح ولا يفشل** ⇒ جلسة مُزاحة غير مكتشفة تعدّ **0 في كل جدول بلا خطأ**. `HomeViewModel._loadSupabaseCounts` كان يقبل أي جواب للحساب الحالي (حارس `_countsEpoch` للحساب فقط) فيعرض الأصفار و**يحفظها فوق كاش R-02 الصالح**. ملاحظة من المصدر: فشل عدّ جدول (شبكة/تفويض) **لا ينتج صفراً** أصلاً — `getCounts` يستبدله بالقيمة المعروضة (`fallback`). **استُنسخ قبل الإصلاح:** مع المعاملين الجديدين دون استعمال، فشل 10 اختبارات، منها «جواب الجلسة المُزاحة الكلّه أصفار يُبقي الأعداد المعروضة والمحفوظة» (كانت تُستبدل بأصفار).

### الإصلاح (`lib/src/viewmodels/home_viewmodel.dart` فقط؛ السلطة نفسها من P3.1b)
- **ربط بالجلسة:** `session = ListSessionCheck.currentSession()` يُلتقط عند بدء القراءة؛ `stillTheReader()` = حارس الحساب/epoch القائم **و**الجلسة نفسها — يُفحص بعد القراءة، بعد الفحص، **وفي مؤقّت الـ debounce (100 ms)** قبل العرض والحفظ. خروج ودخول بالحساب نفسه، أو تغيّر جلسة بلا حدث مرئي ⇒ الجواب يُسقط.
- **أصفار تحتاج تأكيداً فقط حين تستبدل عدداً معروضاً:** `_zeroesAShownCount` = أي جدول صار 0 وكان معروضاً > 0. عندها فقط `ListSessionCheck.confirmFor(session)` ⇒ `AppSessionCoordinator.validateNow()` (يشارك الفحص الجاري للجلسة نفسها؛ false يبدأ الخروج المعتاد). **غير مؤكَّد ⇒ لا شيء من الجواب يُطبَّق** (لا جزئياً)؛ **فشل الفحص (شبكة)** ⇒ يُلتقط بالـ catch القائم ⇒ الأعداد المعروضة والمحفوظة باقية. الأعداد > 0 تثبت أن البوابة سمحت ⇒ بلا فحص.
- **الصفر الشرعي محفوظ:** حساب فارغ أصفاره معروضة أصلاً ⇒ **بلا فحص**؛ أصفار تستبدل أعداداً بجلسة مؤكَّدة ⇒ تُعرض وتُحفظ.
- **لا RPC أو دفعات جديدة:** فحص واحد فقط لكل جواب يُصفّر عدداً معروضاً؛ لا شيء غير ذلك؛ لم يُمسّ جدول الطلبات (P3/Q1–Q3 تبقى للتحسين لاحقاً).
- **معاملا اختبار** `@visibleForTesting confirmSession`/`sessionOf` (افتراضياً `ListSessionCheck.confirmFor`/`currentSession`). **بلا تغيير:** `SupabaseHomeCountsService`، `CountCacheService` وعزله (R-02)، الفلاتر، الواجهة، P3.1b/P3.1a، SQL/RLS/Auth/SAD.

### الأدلة (شغّلها الوكيل)
- **جديد `test/home/home_false_zero_test.dart` — 16/16 PASS** (HomeViewModel وCountCacheService الحقيقيان): حساب فارغ ⇒ أصفار بلا فحص؛ أصفار تستبدل أعداداً بجلسة مؤكَّدة ⇒ تُعرض وتُحفظ والفحص لجلسة القراءة `s1`؛ أعداد بلا صفر ⇒ بلا فحص؛ جواب مختلط أصفاره كانت صفراً ⇒ بلا فحص؛ **جلسة مُزاحة كلّه أصفار ⇒ المعروض والمحفوظ 4 باقيان**؛ مختلط يُصفّر عدداً معروضاً ⇒ يُفحص، وغير مؤكَّد ⇒ لا يُطبَّق شيء؛ فشل الفحص (شبكة) ⇒ باقٍ؛ فشل قراءة الأعداد (`AuthException`) ⇒ باقٍ بلا فحص؛ جواب جلسة قديمة بعد خروج ودخول للحساب نفسه ⇒ مُسقط؛ تغيّر الجلسة بلا حدث خروج ⇒ مُسقط؛ تغيّر الجلسة أثناء الفحص ⇒ مُسقط؛ تغيّرها أثناء الـ debounce ⇒ مُسقط؛ **فحص متأخر للجلسة القديمة لا يلغي تحديث الجلسة الجديدة** (7 تُعرض وتُحفظ)؛ حساب آخر يدخل أثناء قراءة/فحص ⇒ لا شيء من جواب Alice يصل إلى Bob أو إلى كاش Alice؛ إغلاق Home أثناء الفحص ⇒ لا شيء؛ **فحص واحد فقط** لجواب يُصفّر عدداً، وصفر فحوص لجواب لا يُصفّر (عبر الفحص الافتراضي المشترك).
- **ملاحظة اختبار (قائمة، ليست من P3.1c):** الـ catch القائم في `_loadSupabaseCounts` يطبع المكدس بـ `debugPrintStack` الذي يُطلق assertion في بيئة الاختبار مع إطارات `stack_trace` («asynchronous gap»)؛ لذلك أكملت الاختبارات أخطاءها بـ `StackTrace.empty`. لا تغيير في الـ catch الإنتاجي.
- **فحص الطفرات — 8/8 التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): عدم فحص الأصفار؛ تجاهل جواب الفحص؛ عدم مقارنة الجلسة؛ إسقاط إعادة الفحص بعد الفحص (**نجت أولاً** — أُضيف اختبار «الفحص المتأخر لا يلغي التحديث الأحدث»)؛ إسقاط حارس الجلسة في الـ debounce (**نجت أولاً** — أُضيف اختبار تغيّر الجلسة أثناء الـ debounce)؛ فحص الأجوبة الكلّها أصفار فقط؛ فحص كل جواب؛ فحص صفر يستبدل صفراً.
- **انحدار (منفرد):** `test/home/` (بما فيه عزل R-02 `home_count_cache_isolation_test`)، `test/lists/`، كل `test/auth/`، `test/favorites/`، `map_sdk_warmup_test`، `delete_account_test`، `r2_home_responsive_test` (Home)، الشاشات الست → **1282 PASS، 8 FAIL = المعروفة فقط بالضبط:** FU-AUTH-BASELINE-7 (السبعة نفسها) + التاريخي (Delete Account migration-file). **FU-OWNERS-R5C الخمسة PASS.**
- **Analyzer** (الملف + الاختبار) → No issues. **Format:** الاختبار 0 تغييرات؛ `home_viewmodel.dart` مطابق للمنسِّق (عدا CRLF). **`git diff --check`** → نظيف.

### المخاطر المتبقية
- الأعداد 7 طلبات متوازية: جلسة تُزاح **بين** طلبات الدفعة الواحدة قد تعطي مزيجاً (بعضه > 0)؛ تُفحص الأصفار التي تستبدل أعداداً فقط، فصفر جديد لجدول كان معروضاً 0 لا يُفحص (لا ضرر: لا يستبدل شيئاً).
- بلا coordinator (وضع غير Supabase) ⇒ لا فحص (لا بوابة).
- PostgREST/staging وSamsung (D-53 أدناه) غير مُتحقَّق منهما؛ تكرار دفعات الأعداد (Q1–Q3) **باقٍ** لتحسين P3 لاحق.

### الحالة و NOW / NEXT / STOP
- **Home False-Zero = CODE_PROVEN** — ليس REAL_DEVICE_VERIFIED ولا STAGING_VERIFIED. **FU-P2.5E-CRUD-STALE: OPEN** (قرار D-3). FU-AUTH-BASELINE-7 وDelete Account التاريخي **OPEN**. تحقق PostgREST على staging لـ P3.1a **PENDING**. Samsung/البناء الأصلي **DEFERRED/UNVERIFIED**.
- **الملفات (غير مدمجة):** `lib/src/viewmodels/home_viewmodel.dart`؛ جديد `test/home/home_false_zero_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك وموافقة على commit. **NEXT:** قرار D-3 لـ FU-P2.5E-CRUD-STALE، أو تحقق staging، أو تحسين استعلامات Home (Q1–Q3) بموافقة منفصلة. **STOP:** لا commit/push؛ لا تحسين استعلامات تلقائياً.
- **أُودع** بموافقة المالك: `f3d8e82` `fix(home): prevent false zero counts from superseded sessions` (3 ملفات)، ودفعه المالك (`origin` = `f3d8e82`، §7AD).

---

## 7AD) P3.1d — الحذف المؤكَّد واتساق الكاش offline — تصميم وتوصية (2026-11-03؛ **لا تنفيذ؛ ينتظر موافقة المالك**)

**Git (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `f3d8e82` = `origin` (0/0)، نظيف، stashes = 2. **لا تغيير كود.**

### الاستنساخ (قائم، مُعاد تشغيله)
`offline_lists_freshness_test.dart` — مجموعة «known limit» **3/3 PASS** (أي أن الخلل قائم): القائمة محفوظة `[a1,a2]`؛ الخادم يقبل حذف `a2` ثم تفشل إعادة القراءة ⇒ النسخة المحفوظة تبقى `[a1,a2]` بوقت ما قبل الحذف، و**شاشة لاحقة offline تعرض `a2`**؛ القراءة الناجحة التالية تزيله. منذ P3.1a صار «نجح الحذف» = **تأكيد خادمي** (id مُرجَع أو صف محذوف مسبقاً مؤكَّد بالقراءة).

### حقائق تحدد التصميم (من المصدر)
- **لا مسار «إلغاء حذف»** في العميل ولا في SQL (لا كتابة تعيد `deleted_at` إلى null لأي من الجداول الست)، والمعرّفات **UUID v4** يولّدها العميل ⇒ **الحذف المؤكَّد نهائي لذلك المعرّف**. قائمة خادم تحوي X **بعد** تأكيد حذفه لا يمكن إلا أن تكون **قديمة** (بدأت قبل الحذف) — مثلاً قراءة `_refreshedStream` كانت جارية أثناء الحذف.
- الحذف المؤكَّد نوعان (P3.1a): **حذف جديد** (id مُرجَع) و**محذوف مسبقاً** (صف هذا الحساب بـ `deleted_at` مؤكَّد بالقراءة) — كلاهما يعني «X محذوف على الخادم لهذا الحساب».

### المقارنة
| المعيار | **A — علامة حذف مُصادَقة (tombstone overlay)** | **B — تعديل v2 مضبوط (استثناء D-3)** |
|---|---|---|
| D-3 | **يبقى كما هو حرفياً**: v2 = قائمة خادم فقط | يحتاج استثناءً صريحاً |
| قائمة قديمة متأخرة تحوي X | **لا تعيده** (العلامة تُخفيه عند العرض؛ v2 يُحفظ كما أرسله الخادم) | **تعيده** (تُكتب v2 بـ X) — إلا بتعديل قوائم الخادم قبل الحفظ = استثناء D-3 أوسع |
| الوقت (P2.5c) | لا يتغيّر (v2 مطابق للخادم)؛ يُضاف علم داخلي «أُخفيت حذوفات مؤكَّدة» | يصير «غير معروف» |
| الانهيار | كتابة واحدة لسجل؛ ممزّقة ⇒ تُرفض ⇒ X يظهر (= اليوم، لا أسوأ) | إعادة ختم v2؛ ممزّقة ⇒ القائمة كلها لا تُقرأ حتى D-2 |
| الإزالة/التقاعد | تتقاعد العلامة حين تُحفظ قائمة خادم **لا تحوي X** | لا شيء |
| الحجم | ~120–160 سطراً في النواة + سطر لكل غلاف وخدمة | ~40 سطراً، لكنه لا يحقق شرط عدم الإحياء |
**التوصية: A.**

### التصميم المقترح (A) — التغييرات الدقيقة
1. **`lib/src/services/encrypted_account_list_cache.dart`:**
   - معامل جديد `idOf` في `EncryptedAccountListCache` (الأغلفة الست تمرّره).
   - مفتاح جديد **`<entity>_deleted_v1`** داخل الصندوق المشفّر نفسه: `{"v":1,"p":"{\"ids\":[...]}","t":HMAC}` تحت `K_mac` نفسه **بتسمية مستقلة** `bw-offline-list-deleted` وإصدار `1`، مربوط بـ `listKey` والحساب (الترميز المسبوق بالطول نفسه) ⇒ لا يُقبل مكان قائمة أو سجل وقت أو لحساب/كيان آخر.
   - `rememberConfirmedDeletion(uid, id)`: تحت طابور الصندوق؛ **فقط لصندوق موجود ومقروء** (لا ينشئ مفتاحاً)؛ يضيف المعرّف، **حدّ أقصى 1000** (يسقط الأقدم ⇒ يعود سلوك اليوم لا أسوأ)، يختم ويتحقق بالقراءة.
   - `readSaved`: يتحقق من العلامات ويُسقط عناصرها من القائمة المُعادة (v2 أو v1 القديم)؛ `SavedListInfo` يكسب علماً داخلياً `hidesConfirmedDeletions`. علامات تالفة/مزوّرة ⇒ تُتجاهل (X يظهر = اليوم).
   - `write` مع `serverReadAt` (قائمة خادم مرجعية فقط): بعد `_store` الناجح، **تقاعد** كل علامة غير موجودة في القائمة المحفوظة (القائمة نفسها تؤكد الحذف)؛ العلامات لعناصر ما زالت فيها تبقى. **v2 يُحفظ كما أرسله الخادم دائماً.**
   - مرآة في الذاكرة لكل صندوق (تُحمَّل في `readSaved`، تُحدَّث في التذكّر/التقاعد، تُمسح في `forgetAccount`) ليُصفّي `localFirstList` قوائم الخادم **عند العرض** بشكل متزامن.
2. **`localFirstList`:** `accept()` يعرض `items` بعد إسقاط المعرّفات المؤكَّد حذفها (والبصمة عليها)، ويحفظ `items` **غير معدّلة**. فحص القائمة الفارغة (P3.1b) يبقى على `items` الخادم الأصلية (صفوف ⇒ البوابة سمحت، حتى لو أُخفيت كلها).
3. **الخدمات الست** (`deleteRequest/Offer/Owner/Office/Broker/Watchman`): تلتقط الحساب والجلسة **قبل** الحذف؛ بعد عودة `_supabase.deleteX` **بنجاح مؤكَّد** فقط ⇒ `rememberConfirmedDeletion` إن كان الحساب والجلسة نفسيهما (P3.1b)؛ أي فشل في التذكّر يُبتلع (الحذف نفسه لا يفشل بسببه). `CoreEntityNotDeleted` أو أي خطأ ⇒ **لا علامة**.
4. **الأغلفة الست:** `idOf: (x) => x.id ?? ''` (سطر لكل غلاف).
5. **اختبار ثابت (invariant) مصدري:** لا كتابة في `lib/` ولا migration تعيد `deleted_at` إلى null للجداول الست (يحمي فرضية «الحذف نهائي»؛ لو أُضيف إلغاء حذف لاحقاً يجب تغيير قاعدة التقاعد).

### اختبارات مركّزة مقترحة
الاستنساخ يصير: حذف مؤكَّد ثم فشل القراءة ⇒ X **لا يظهر** offline (وبعد إعادة التشغيل)؛ «محذوف مسبقاً» ⇒ علامة أيضاً؛ **حذف غير مؤكَّد/خطأ ⇒ لا علامة**؛ قائمة خادم قديمة تحوي X بعد التأكيد ⇒ لا يظهر، وv2 المحفوظ = قائمة الخادم بايت-بايت (وسمها يطابق)، والعلامة باقية؛ قائمة خادم بلا X ⇒ العلامة تتقاعد (السجل يُزال حين يفرغ)؛ الوقت لا يتغيّر بالعلامة؛ تبديل الحساب/الجلسة أثناء الحذف ⇒ لا علامة لأي حساب؛ علامة مزوّرة/لحساب آخر/لكيان آخر/بتسمية القائمة ⇒ تُتجاهل؛ كتابة ممزّقة ⇒ تُتجاهل والقائمة تُقرأ؛ الحدّ 1000؛ v1 القديم + علامة ⇒ يُخفى؛ حذف الحساب ⇒ العلامات تُزال؛ D-2 استرداد ⇒ العلامات تُفقد (موثّق)؛ الكيانات الست عبر خدماتها؛ الاختبار الثابت؛ طفرات لكل حارس.

### مخاطر التوافق والرجوع
- **توافق:** صيغة v2 ومفاتيحها وسجل الوقت بلا تغيير؛ النسخ الأقدم **تتجاهل** `<entity>_deleted_v1`. **الرجوع:** حذف الكود يترك المفتاح يتيماً بلا أثر (يُحذف مع الصندوق عند حذف الحساب)؛ لا ترحيل.
- **حدود:** D-2 (صندوق غير مقروء) يفقد العلامات ⇒ قد يعود X حتى القراءة التالية (= اليوم)؛ تذكّر لا يحدث إن لم يوجد صندوق مقروء بعد؛ أجهزة أخرى لا تعرف علامات هذا الجهاز (تُصحَّح بقراءتها)؛ العلامة **لا تمنح أي صلاحية** ولا تُستعمل في أي قرار وصول — تُخفي فقط سجلاً أكّد الخادم حذفه.
- **قرار المالك المطلوب:** اعتماد A (لا استثناء D-3) أو B (استثناء D-3 مع قبول عودة X من قائمة قديمة).

### تحقق PostgREST على staging (P3.1a — PENDING؛ إجراء المالك)
**تنبيه:** staging والإنتاج **مشروع Supabase واحد** ⇒ **حسابات اختبار مخصّصة فقط**، لا سجلات مستخدمين حقيقيين، **لا service role**. لكل حساب: تسجيل دخول عادي (password grant) ⇒ access token ⇒ **`POST /rest/v1/rpc/claim_current_app_session`** (وإلا تُرشِّح البوابة كل شيء). لا تُلصق الـ tokens في السجلات.
1. الحساب A: إنشاء Request اختبار من التطبيق (ملاحظة `P3.1a-staging-<date>`) ⇒ المعرّف X.
2. `PATCH /rest/v1/requests?id=eq.X&deleted_at=is.null&select=id` مع `Prefer: return=representation` وجسم `{"deleted_at":"<now ISO>"}` ⇒ **متوقع `[{"id":"X"}]`**.
3. الطلب نفسه مرة ثانية ⇒ **`[]`**؛ ثم `GET /rest/v1/requests?id=eq.X&deleted_at=not.is.null&select=id` ⇒ **`[{"id":"X"}]`**، و`deleted_at` لم يتغيّر بين 2 و3 (قراءة A).
4. الحساب B (مُدَّعى): `PATCH` على Request حي Y للحساب A ⇒ **`[]`**؛ `GET` ⇒ **`[]`**؛ ثم A يرى Y حياً.
5. إزاحة: تسجيل دخول A ثانية + claim (جلسة جديدة) ⇒ بالـ token القديم: `PATCH` على Z حي ⇒ **`[]`**، `GET` ⇒ **`[]`**؛ Z حي.
6. التطبيق: حذف من القائمة ⇒ رسالة النجاح؛ حذف بعد الإزاحة ⇒ رسالة الفشل القائمة ثم حوار الإزاحة.
السجلات الاختبارية تبقى محذوفة مرناً لحساب الاختبار.

### الحالة و NOW / NEXT / STOP
- **FU-P2.5E-CRUD-STALE: OPEN** (تصميم A موصى به، غير منفّذ). P3.1a staging **PENDING**. FU-AUTH-BASELINE-7 وDelete Account التاريخي **OPEN**. Samsung/البناء الأصلي **DEFERRED/UNVERIFIED**.
- **NOW:** قرار المالك (A أو B). **NEXT:** التنفيذ بموافقة منفصلة. **STOP:** لا تنفيذ، لا تغيير D-3، لا commit/push، لا تحسين استعلامات Home تلقائياً.
- **قرار المالك (2026-11-03):** اعتماد **A** مع تصحيح حاسم: **لا تقاعد للعلامات** لمجرد غياب المعرّف من قائمة خادم (قد تُقصّ بـ `max_rows`)، ولا إسقاط صامت عند الحد، وفشل آمن للعلامات التالفة/المفقودة. التنفيذ في §7AE.

---

## 7AE) P3.1d — تنفيذ علامات الحذف المُصادَقة (Option A) — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `f3d8e82` = `origin` (0/0)، الشجرة فيها §7AD فقط، stashes = 2.

### الاستنساخ قبل الإصلاح
اختبارات `test/lists/confirmed_deletion_test.dart` كُتبت أولاً؛ مع واجهات فارغة (التذكّر بلا عمل) **فشل 12** منها: الحذف المؤكَّد ثم فشل التحديث ⇒ السجل يظهر offline، بعد إعادة التشغيل، الجواب المتأخر، التزامن، العلامات التالفة، السعة، حذف الحساب، والكيانات الست. (اختبارات «لا علامة بلا تأكيد» نجحت مع الفراغ — صحيح.)

### التنفيذ
- **`lib/src/services/encrypted_account_list_cache.dart` (النواة):**
  - **صيغة التخزين:** مفتاح جديد **`<entity>_deleted_v1`** داخل الصندوق المشفّر نفسه: `{"v":1,"p":"{\"ids\":[...مرتّبة]}","t":"<HMAC-SHA256>"}`. الوسم بمفتاح `K_mac` المشتق نفسه **بتسمية مستقلة** `bw-offline-list-deleted` وإصدار `1`، والأجزاء المسبوقة بطولها: التسمية، الإصدار، `listKey` (الكيان)، **معرّف الحساب القانوني**، الحمولة بايت-بايت. **v2 وسجل الوقت بلا تغيير** (D-3: v2 = قائمة خادم فقط).
  - **الإنشاء:** `rememberConfirmedDeletion(uid, id)` — يُضاف إلى ذاكرة «هذه الجلسة من التشغيل» فوراً، ثم تحت **طابور الصندوق نفسه**: لصندوق موجود ومقروء فقط (لا ينشئ مفتاحاً؛ بلا صندوق تبقى العلامة في الذاكرة لهذا التشغيل — لا يوجد ما يُخفى لاحقاً)؛ قراءة العلامات والتحقق ثم إضافة ثم ختم وقراءة تحقق — **لا ضياع تحديثات** (كل تذكّر وكتابة متسلسلان).
  - **من يستدعيه:** `deleteThenRemember(cache, id, currentUserId, delete, sessionOf)` (جديد): يلتقط الحساب و`session_id` **قبل** الحذف؛ `delete()` يرمي ما لم يؤكّد الخادم (P3.1a) ⇒ لا علامة؛ بعده: **الحساب والجلسة نفسيهما وإلا لا علامة**. فشل التذكّر يُبتلع (الحذف نفسه نجح).
  - **التطبيق:** `readSaved` يُسقط المعرّفات المؤكَّد حذفها من النسخة (v2 أو v1 القديم) ويضع `SavedListInfo.hidesConfirmedDeletions`؛ **`serverReadAt` لا يتغيّر** (لا ادعاء لتحديث خادمي). `localFirstList.accept()` يعرض قائمة الخادم **مُصفّاة**؛ و`write` **يرفض حفظ** قائمة تحوي معرّفاً أُكِّد حذفه **في هذا التشغيل** (فهي قديمة: بدأت قبل الحذف) — يُفحص داخل الطابور فيراه حفظ ينتظر خلف التأكيد. فحص القائمة الفارغة (P3.1b) يبقى على قائمة الخادم الأصلية.
  - **قواعد التقاعد (دقيقة):** **لا تقاعد في هذه النقطة.** غياب المعرّف من قائمة خادم **ليس دليلاً** (القراءات بلا count وقد تُقصّ). الحذف المرن نهائي (اختبار ثابت: لا كتابة في `lib/` ولا migration تعيد `deleted_at` إلى null) ⇒ العلامة لا تكون خاطئة أبداً، فقط باقية. **مؤجَّل إلى P4** (اكتمال مُثبت)، أو بديل يحتاج قرار المالك (أدناه).
  - **سياسة السعة (صريحة، بلا إحياء):** حدّ **1000** علامة لكل قائمة وحساب (`defaultMaxConfirmedDeletions`). **لا تُسقط أي علامة أبداً.** عند الامتلاء وحذف مؤكَّد جديد: يُحفظ في ذاكرة هذا التشغيل؛ إن كانت **النسخة المحفوظة تحويه** (أو لا تُقرأ) ⇒ **تُزال النسخة** (v2/v1/سجل الوقت؛ العلامات باقية) ⇒ لا يُعرض شيء حتى قائمة الخادم التالية، وهذا التشغيل لن يحفظه مجدداً؛ وإلا تبقى النسخة. يُسجَّل بفئة ثابتة.
  - **علامات تالفة/مزوّرة/لحساب آخر/لكيان آخر/في مكان القائمة — سياسة صارمة (قرار المالك، §7AE-1):** القائمة **محجوبة (integrity-blocked)** لذلك الحساب وتلك القائمة؛ **لا تُعامل كمجموعة فارغة، ولا تُستبدل/تُصفَّر/تُحذف تلقائياً أبداً** (لا قائمة خادم دليل كافٍ). ~~الاستبدال بعد أول قائمة خادم~~ و~~إزالة النسخة وبدء سجل جديد عند حذف جديد~~ **أُزيلا**. **غياب** السجل = لا علامات (الحالة الأولى المشروعة).
  - **حذف الحساب:** `forgetAccount` يمسح الذاكرة لذلك الحساب، والسجل يُحذف مع الصندوق. حسابات أخرى بلا مساس.
- **الأغلفة الست:** `idOf: _idOf` (سطر + دالة). **الخدمات الست:** الحذف عبر `deleteThenRemember` (Offer/Owner يحتفظان بتنظيف الوسائط بعده)؛ Request/Office/Broker/Watchmen كسبت معاملاً اختيارياً `coreEntities` (كـ Offer/Owner) للاختبار. **بلا تغيير:** الواجهة، الفرز/الفلاتر، P3.1a/b/c، D-1a/D-2/D-3، R-02، SAD، SQL/RLS/Auth، Toolkit والوسائط.

### الأدلة (شغّلها الوكيل)
- **`test/lists/confirmed_deletion_test.dart` — 21/21 PASS:** (1) حذف مؤكَّد ثم فشل الشبكة ⇒ النسخة والشاشة offline بدونه، v2 وسجل الوقت **بايت-بايت كما هما**، `serverReadAt` = t0، `hidesConfirmedDeletions`؛ (2/5) بعد إعادة تشغيل محاكاة ⇒ العلامة تُخفيه؛ v1 القديم يُصفّى أيضاً؛ (3/4) جواب بدأ قبل الحذف ووصل بعده ⇒ يُعرض بدونه و**لا يُحفظ**؛ (13) قائمة لاحقة بلا المعرّف ⇒ تُحفظ و**العلامة باقية**؛ (8) حذفان متزامنان + تحديث ⇒ العلامتان باقيتان؛ (7) `CoreEntityNotDeleted`/شبكة/`PostgrestException` ⇒ لا علامة؛ (6) تبديل الحساب أو خروج ودخول للحساب نفسه أثناء الحذف ⇒ لا علامة؛ (9/10) وسم معدّل ⇒ النسخة محجوبة ثم قائمة خادم تعيدها؛ ليس JSON/v2 مكان العلامة/حمولة بلا ids ⇒ محجوبة؛ علامة في مكان القائمة ⇒ لا قائمة؛ **علامة حساب آخر بالمفتاح نفسه** ⇒ مرفوضة؛ علامة Bob في صندوق Alice ⇒ مرفوضة؛ علامات تالفة ثم حذف جديد ⇒ النسخة تُزال (لا عودة لـ a2) وسجل جديد بـ a3؛ بلا صندوق ⇒ ذاكرة هذا التشغيل تمنع حفظ القائمة القديمة؛ (14) الحدّ: لا علامة تُسقط، نسخة تحوي المحذوف فوق الحد تُزال ولا تُحفظ مجدداً، ونسخة لا تحويه تبقى؛ الحد الإنتاجي 1000؛ (11) حذف الحساب يزيل علامات ذلك الحساب فقط؛ الاختبار الثابت «لا إلغاء حذف»؛ (12) **الكيانات الست عبر خدماتها الحقيقية**: حذف مؤكَّد يُخفى بعد فشل التحديث، وحذف مرفوض لا يُخفي شيئاً؛ (15) لا تقدّم كاذب للوقت (ضمن 1 و3).
- **فحص الطفرات — 13/13 التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): عرض قائمة الخادم بلا تصفية؛ حفظ القائمة القديمة؛ العلامات التالفة = لا علامات؛ عدم فحص الوسم؛ **الحساب خارج الوسم (نجت أولاً — أُضيف اختبار المفتاح المشترك)**؛ بلا حدّ؛ إزالة النسخة دون أن تحويه؛ عدم ربط الجلسة؛ علامة رغم عدم التأكيد؛ عدم استبدال العلامات التالفة؛ إبقاء النسخة مع علامات تالفة؛ عدم التذكّر في الذاكرة؛ عرض النسخة المحفوظة بلا تصفية.
- **انحدار (منفرد):** `test/lists/`، `test/home/`، `test/favorites/`، `test/offers/`، `test/owners/`، `test/related_items/`، **كل `test/account/`**، `map_sdk_warmup_test`، `r2_home_responsive_test`، الشاشات الست + `r5d_related_cards_test` → **1434 PASS، 3 FAIL**، مصنّفة: (1) التاريخي (Delete Account migration-file)؛ (2) **`list_refresh_test` «each list recovers when the network comes back…» = تذبذب توقيت** — ينجح منفرداً (17/17)، و**`test/lists/` كاملاً 367/367** في إعادة نظيفة؛ (3) **`delete_account_ui_test` «a completed deletion ends on the logged-out entry and never shows Home» — قائم ومستقل:** وُضعت نسخ HEAD (`f3d8e82`) من الملفات الـ 13 المعدّلة مؤقتاً (نسخ يدوي، لا `git restore`/stash) ⇒ **يفشل الاختبار نفسه بالطريقة نفسها**، ثم أُعيدت ملفاتي و`Get-FileHash` مطابق. **مسجّل FU-ACCOUNT-UI-BASELINE-1 (OPEN)** — لم يُرصد سابقاً لأن الانحدارات السابقة شغّلت `delete_account_test` وحده لا كل `test/account/`. **FU-OWNERS-R5C الخمسة PASS.** `test/auth/` لم يُعَد (لا يستورد المسارات المتغيّرة؛ FU-AUTH-BASELINE-7 كما هو).
- **Analyzer** (النواة، الخدمات الست، الأغلفة الست، الاختبار) → No issues. **Format:** الاختبار 0 تغييرات؛ الأغلفة الست وRequest/Office/Broker/Watchmen مطابقة للمنسِّق؛ `encrypted_account_list_cache.dart` **مطابق بعد تصحيح سطرين** — أحدهما جديد هنا، والآخر **من إصلاح P3.1b (`9e45013`) أُودع دون فحص تنسيق نهائي** (`unawaited(cache.write(... mayRecover: stillTheReader ...))`؛ تصحيح تخطيط فقط، صُحّح هنا)؛ `offer_service.dart`/`owner_service.dart` فيهما انحرافات **قائمة في HEAD في أسطر ليست لي** (لم تُنسَّق). بعد التصحيح: الاختبارات المركّزة (`confirmed_deletion` + `list_false_empty` + integrity + storage) **97/97 PASS**. **`git diff --check`** → نظيف.

### حدود معروفة (موثّقة، غير محلولة)
- **rollback/replay للملف المشفّر كاملاً** (استبدال الصندوق بنسخة أقدم صالحة) يعيد علامات وقائمة أقدم — حدّ D-3 نفسه.
- **D-2 (صندوق غير مقروء يُستبدل)** يفقد العلامات المخزّنة؛ آمن لأن البديل قائمة خادم من هذا التشغيل (وذاكرة هذا التشغيل باقية)، لكن الحذوفات القديمة لا تعود ضرورية فقط لأن القائمة جديدة.
- **انهيار بين تأكيد الخادم وكتابة العلامة** (أو فشل I/O عند الكتابة) ⇒ قد يعود السجل offline حتى قراءة الخادم التالية (= السلوك قبل P3.1d؛ يُسجَّل).
- أجهزة أخرى لا ترى علامات هذا الجهاز (تُصحَّح بقراءتها).
- **نموّ العلامات:** بلا تقاعد تبلغ 1000 لكل قائمة بعد 1000 حذف على هذا الجهاز لهذا الحساب؛ بعدها كل حذف لسجل في النسخة يُزيل النسخة حتى القراءة التالية (توفّر offline أقل، بلا إحياء).
- **بديل تقاعد يحتاج قرار المالك (لم يُنفَّذ):** تقاعد علامة **من تشغيل سابق** حين **لا تحويها النسخة المحفوظة** — آمن دون اكتمال لأن قائمة خادم جديدة لا تحوي صفاً محذوفاً مرناً أبداً (`deleted_at is null` + لا إلغاء حذف) والقوائم القديمة لا توجد إلا في التشغيل الذي أكّد الحذف. يختلف عن قاعدة «الإبقاء حتى اكتمال مُثبت» فيتطلب موافقة.

### 7AE-1) المراجعة النهائية المستهدفة (2026-11-03، موافقة المالك) — **توقّف قبل الـ commit**
- **لا طفرة متبقية:** الملف مطابق لنسخة ما قبل الطفرات عدا سطري التنسيق؛ مطابقتا البحث في الـ diff كود حقيقي (تعليق وثيقة و`back ?? <String>{}`).
- **السعة — آمنة:** اختبار جديد (22/22): إزالة نسخة Requests لـ Alice فوق الحد **لا تمسّ** نسخة Offers لها ولا نسخة Bob (بايت-بايت)، وتبقى مُزالة بعد إعادة التشغيل؛ مع الاختبارات السابقة (إزالة ثم جواب قديم لا يُحفظ، ثم قائمة جديدة تُحفظ والعلامات القديمة كلها باقية). **حدّ مُدقَّق:** إن **فشلت إزالة النسخة نفسها** (I/O) فقد يعود السجل بعد إعادة التشغيل — من صنف «انهيار/فشل I/O بين التأكيد والعلامة» الموثّق (يُسجَّل `marking failed`).
- **العلامات التالفة — غير مُثبتة بالمعيار المطلوب ⇒ STOP:** شرط المالك «لا تُعدّ استجابة خادم جديدة دليلاً كافياً لإسقاط حذوفات مؤكَّدة سابقة» **لا يتحقق حرفياً**: `_replaceInvalidMarkers` يستبدل العلامات غير المقروءة بعلامات هذا التشغيل بعد حفظ قائمة خادم من هذا التشغيل، و`rememberConfirmedDeletion` مع علامات تالفة يزيل النسخة ويبدأ سجلاً جديداً. **الأمان يعتمد على:** (1) لا إلغاء حذف (اختبار ثابت ✔)، (2) القراءة تُرشّح `deleted_at is null` (اختبار عقد ✔)، (3) **قراءة-بعد-كتابة متّسقة: لا replica قراءة متأخرة تجيب عن الطلبات — غير مُتحقَّق على المستضاف.** **السيناريو الدقيق:** حذف X مؤكَّد في تشغيل سابق (علامته مخزّنة) → سجل العلامات يتلف (عبث/تلف يمرّ من CRC وAES) → إعادة تشغيل → قراءة خادم تخدمها **replica متأخرة** فتعيد X → تُحفظ (X ليس في ذاكرة هذا التشغيل) → العلامات تُستبدل بلا X → **X يظهر offline**. مع علامات سليمة لا يحدث (العلامة باقية بلا تقاعد).
- **خيارات للمالك:** (A) **صارم:** العلامات غير المقروءة **لا تُستبدل أبداً** بجواب خادم؛ النسخة تبقى محجوبة لتلك القائمة على هذا الجهاز حتى حذف الحساب/إعادة التثبيت (أو آلية P4)، وحذف جديد يبقى في الذاكرة فقط؛ ثمنه: لا offline لتلك القائمة بعد حدث نادر جداً. (B) الإبقاء على القاعدة الحالية **بعد تحقق المالك** أن المشروع المستضاف بلا Read Replicas (Dashboard → Database → Read replicas) ⇒ يصير الشرط (3) مُثبتاً. **التوصية: A** (أصغر تغيير، آمن بلا افتراض مستضاف).
- **بقية التأكيدات — سليمة:** الخدمات الست تضع العلامة فقط بعد `delete()` المؤكَّد (`deleteThenRemember`)؛ Offer/Owner: تنظيف الوسائط يجري **بعد** الحذف المؤكَّد والتذكّر (لا يجري لحذف مرفوض)؛ تبديل الحساب/الجلسة أثناء الحذف ⇒ لا علامة (اختبار + طفرة T8)؛ صيغ v2/HMAC وD-1a/D-2/D-3 وسجل الوقت متوافقة (integrity + storage + freshness PASS، `serverReadAt` لا يتقدّم).
- **لا commit.** الملفات الـ 15 + اختبار السعة الجديد في الشجرة.
- **قرار المالك (2026-11-03): الخيار A الصارم — لا استبدال تلقائي للعلامات التالفة أبداً.**

**تنفيذ السياسة الصارمة (`encrypted_account_list_cache.dart` فقط):**
- علامات غير مقروءة (وسم HMAC خاطئ، تالفة، مشوّهة، لحساب/كيان آخر) ⇒ `_block(uid)`: القائمة **integrity-blocked** لذلك الحساب وتلك القائمة (`isIntegrityBlocked`)، تُكتشف في `readSaved` (حتى بلا نسخة محفوظة)، وفي `write` (بعد فتح الصندوق)، وفي `rememberConfirmedDeletion`. السجل التالف **يبقى في التخزين كما هو** فتُعاد اكتشافه بعد كل إعادة تشغيل.
- **محجوبة ⇒** `readSaved` = null؛ `write` **لا يحفظ شيئاً** (ولا يسترد D-2 خلال التشغيل الذي عُرف فيه الحجب)؛ `rememberConfirmedDeletion` **لا يكتب** (الحذف المؤكَّد يبقى في ذاكرة هذا التشغيل)؛ `localFirstList` بعد قراءة النسخة: **`ListIntegrityBlocked` مرة واحدة ثم توقف — لا قراءة خادم، لا محاولات، لا تحميل لا ينتهي** (حالة خطأ التحميل القائمة في الشاشة؛ لا تغيير واجهة)؛ وقائمة خادم كانت قيد القراءة حين اكتُشف الحجب **لا تُعرض** (الخطأ نفسه ثم توقف).
- **أُزيل:** `_replaceInvalidMarkers` (الاستبدال بعد قائمة خادم) وفرع «إزالة النسخة + سجل جديد» عند حذف مع علامات تالفة.
- **يرفع الحجب فقط:** Delete Account (`forgetAccount` يحذف الصندوق والسجل التالف معه). **أي استرداد آخر للعلامات التالفة يحتاج تصميماً وموافقة منفصلين.**
- **بلا تغيير:** العلامات السليمة باقية بلا تقاعد؛ سياسة السعة؛ تدفق الحذف المؤكَّد وربط الحساب/الجلسة؛ D-1a/D-2/D-3؛ v2/HMAC وسجل الوقت؛ حسابات وقوائم أخرى؛ Toolkit والوسائط.

**الأدلة (شغّلها الوكيل):**
- **قبل الحارس (فشل مقصود):** مع `isIntegrityBlocked` الثابت على false فشلت **4** اختبارات صارمة، منها «قائمة خادم صالحة لا تُحفظ والعلامات والقائمة ووقتها بايت-بايت» (كانت تُستبدل). بعد الحارس: كلها PASS.
- **`confirmed_deletion_test.dart` — 27/27 PASS** (حُذف اختباران كانا يثبّتان الاستبدال، وأُضيفت 7): بعد إعادة التشغيل النسخة محجوبة والشاشة تتلقى `ListIntegrityBlocked` واحداً، بلا قائمة وبلا قراءة خادم رغم إعداد محاولات؛ قائمة خادم صالحة **وقائمة قديمة تحوي المحذوف** ⇒ لا تُحفظ، والقائمة وسجل الوقت والعلامات **بايت-بايت** (لا تقدّم للوقت)؛ قائمة كانت قيد القراءة حين اكتُشف الحجب لا تُعرض؛ حجب ثم فقد مفتاح الصندوق في التشغيل نفسه ⇒ **لا استرداد D-2** (الملف بايت-بايت، لا مفتاح جديد)؛ حذف مؤكَّد جديد لا يمسّ السجل التالف ولا القائمة، ويبقى محجوباً بعد إعادة التشغيل؛ حسابات أخرى وقوائم Alice الأخرى صالحة وغير محجوبة (لا تداخل حساب/جلسة)؛ Delete Account يرفع الحجب. **اختبارات الحذف العادي والسعة والتزييف والكيانات الست كما هي PASS.**
- **فحص الطفرات للحراس الصارمة — 7/7 التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): القراءة لا تحجب؛ الكتابة تتجاهل حجباً معروفاً (**نجت أولاً** — أُضيف اختبار «فقد المفتاح بعد الحجب لا يسترد»)؛ الكتابة لا تفحص العلامات؛ التذكّر يستبدل العلامات التالفة؛ الشاشة المحجوبة تقرأ الخادم؛ عرض قائمة الخادم رغم الحجب؛ Delete Account لا يرفع الحجب.
- **انحدار مركّز:** `test/lists/` كاملاً + الشاشات الست ⇒ **627/627 PASS**. لم يُعَد الانحدار الواسع (1434) — لا تغيير خارج النواة.
- **Analyzer** (النواة + الاختبار) → No issues. **Format:** الملفان مطابقان للمنسِّق (صُحّح سطر فارغ مزدوج خلّفه حذف الدالة). **`git diff --check`** → نظيف.

**حدود متبقية (غير محلولة بهذا التغيير):**
- **نافذة I/O عند السعة:** فشل إزالة النسخة نفسها (أو فشل/انهيار بين تأكيد الخادم وكتابة العلامة) ⇒ قد يعود السجل offline بعد إعادة التشغيل.
- **D-2:** صندوق غير قابل للفك (مفتاح مفقود/تالف) في تشغيل **لم يُعرف فيه الحجب** يُستبدل بقائمة خادم ⇒ تُفقد العلامات المخزّنة معه (لا يمكن قراءتها أصلاً).
- **rollback/replay للملف كاملاً** بنسخة أقدم صالحة ⇒ علامات وقائمة أقدم (حدّ D-3).
- **ثمن الحجب:** قائمة محجوبة لا تُعرض online ولا offline على هذا الجهاز لذلك الحساب حتى Delete Account أو استرداد معتمد لاحقاً (حدث نادر: عبث أو تلف يمرّ من CRC وAES).
- staging (P3.1a) **PENDING**؛ Samsung (D-54، ويُضاف: قائمة محجوبة تُظهر خطأ التحميل لا تحميلاً لا ينتهي) والبناء الأصلي **DEFERRED/UNVERIFIED**.
- **الحالة:** P3.1d بالسياسة الصارمة = **CODE_PROVEN — جاهز لموافقة الـ commit النهائية**. **STOP:** لا commit/push؛ لا P3.2.
- **أُودع** بموافقة المالك: `552bf5b` `fix(offline): prevent deleted records resurfacing with authenticated tombstones` (15 ملفاً)، ودفعه المالك (`origin` = `552bf5b`، §7AF).

### الحالة و NOW / NEXT / STOP
- **FU-P2.5E-CRUD-STALE = CODE_PROVEN (P3.1d)، مع سياسة العلامات التالفة الصارمة المعتمدة (§7AE-1)** — ليس REAL_DEVICE_VERIFIED ولا STAGING_VERIFIED؛ **التقاعد مؤجَّل (P4 أو قرار البديل)**. P3.1a staging **PENDING**. FU-AUTH-BASELINE-7 وDelete Account التاريخي و**FU-ACCOUNT-UI-BASELINE-1** **OPEN**. Samsung (D-54 أدناه) والبناء الأصلي **DEFERRED/UNVERIFIED**.
- **الملفات (غير مدمجة):** `lib/src/services/encrypted_account_list_cache.dart`؛ الأغلفة الست `lib/src/services/{requests,offers,owners,offices,brokers,watchmen}_local_cache.dart`؛ الخدمات الست `lib/src/services/ScreenServices/{request,offer,owner,office,broker,watchmen}_service.dart`؛ جديد `test/lists/confirmed_deletion_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك وموافقة على commit. **NEXT:** قرار بديل التقاعد، أو تحقق staging، أو P3.2 بموافقة منفصلة. **STOP:** لا commit/push؛ لا P3.2 تلقائياً.

---

## 7AF) P3.2 — إزالة تكرار استعلامات أعداد Home — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `552bf5b` = `origin` (0/0)، نظيف، stashes = 2.

### القياس (MEASURED في الاختبار — ليس حركة شبكة على جهاز)
**الأداة:** `test/home/home_count_requests_test.dart` — `HomeViewModel` و`CountCacheService` و`SupabaseHomeCountsService` الحقيقية، و**عميل Supabase حقيقي** بتدفق المصادقة الحقيقي (`onAuthStateChange` = `ReplaySubject` في gotrue 2.27.2 يعيد للمستمع الجديد الأحداث السابقة)، وأحداث حقيقية (`setInitialSession` ⇒ initialSession؛ `refreshSession()` على `/auth/v1/token` مُحاكى ⇒ tokenRefreshed بالجلسة نفسها)، وبديل HTTP **يعدّ كل طلب عدّ** (7 طلبات = قراءة أعداد واحدة). الجلسات `session_id` بصيغة UUID كالحقيقية. **خط الأساس قيس على مصدر HEAD `552bf5b`** (نسخ مؤقت لملف واحد ثم إعادته، `Get-FileHash` مطابق).

| السيناريو | قبل (HEAD) | بعد | |
|---|---|---|---|
| بدء بارد بجلسة مستعادة (حدث مُعاد واحد) | **14** طلباً (قراءتان) | **7** (قراءة) | −50% |
| بدء بارد بعد 3 أحداث سابقة (تُعاد للمستمع) | **14** | **7** | −50% |
| فتح Home ثانية (ViewModel جديد، كل الأحداث تُعاد) | **14** | **7** | −50% |
| 3 تعديلات + سحبان **أثناء** قراءة واحدة | **35** (5 قراءات متوازية) | **14** (الجارية + واحدة بعدها) | −60% |
| قراءة معلّقة ثم إغلاق Home | +7 بعد الإغلاق | **0** | |
| token refresh لاحق / سحب واحد / تعديل واحد / جلسة جديدة للحساب نفسه / حساب آخر / فشل ثم إعادة | 7 لكلٍّ | **7 لكلٍّ (محفوظ)** | |
**تصحيح استنتاج P3.0 (Q1):** «1 + R دفعات» كان استنتاجاً من المصدر؛ **المقاس: قراءتان عند البدء أياً كان عدد الأحداث المُعادة** (1 أو 3).

### التحسين (`lib/src/viewmodels/home_viewmodel.dart` فقط)
- **قراءة واحدة في كل مرة لكل حساب وجلسة وepoch** (`_CountsLoad`، مفتاح `account|session_id|_countsEpoch`): طلب أثناء قراءة جارية للمفتاح نفسه **لا يبدأ قراءة موازية**؛ إن كان **قد يغيّر البيانات** (تعديل/سحب/عودة لتبويب Home) ⇒ **قراءة واحدة تتبعها** (تغيير أثناء القراءة لا يُفقد — مُثبت)؛ إن كان **حدث مصادقة** (لا يغيّر سجلاً) ⇒ تغطيه القراءة الجارية (`_loadCounts(dataMayHaveChanged: false)` من مستمع المصادقة).
- **حساب أو جلسة أخرى، أو epoch جديد** (خروج/تبديل حساب — حتى للحساب نفسه بلا `session_id` معروف) ⇒ قراءة مستقلة دائماً؛ الجواب القديم يُسقط بحراس P3.1c القائمة (`stillTheReader`).
- لا قراءة لاحقة بعد إغلاق Home؛ الفشل يبقى كما كان (الجداول الفاشلة تُبقي المعروض، والمُطلِق التالي يقرأ — **لا تخطٍّ بعد اكتمال قراءة**، فالمحاولات الضمنية محفوظة).
- `_loadSupabaseCounts()` باقٍ بالتوقيع نفسه للمُطلِقات الحاملة للبيانات (يحافظ على اختبار الربط النصي `home_filter_wiring_test`). **بلا تغيير:** `SupabaseHomeCountsService`، `CountCacheService` (R-02)، P3.1c (الأصفار/الجلسة)، الواجهة، الخادم، الطلبات نفسها (لا HEAD ولا حمولة — P3.3).

### الأدلة (شغّلها الوكيل)
- **`home_count_requests_test.dart` — 12/12 PASS** بعد التغيير؛ **على HEAD: 5 تفشل** (البدء البارد ×2، ViewModel ثانٍ، المُطلِقات المتزامنة، الإغلاق) و**7 تنجح** (السلوك المحفوظ).
- **خلل وجده انحدار R-02 أثناء التنفيذ وأُصلح:** نسخة أولى بمفتاح `account|session` فقط ⇒ عند غياب `session_id` (null) خروج ودخول للحساب نفسه ينضم للقراءة القديمة التي تُسقط ⇒ لا قراءة جديدة؛ فشل `home_count_cache_isolation_test` «a read from before a sign-out is dropped even for the same account» ⇒ أُضيف `_countsEpoch` للمفتاح ⇒ PASS.
- **فحص الطفرات — 7/7 التُقطت** (على اختبارات P3.2 وP3.1c وR-02؛ الملف أُعيد، `Get-FileHash` مطابق): أحداث المصادقة تطلب قراءة لاحقة؛ بلا single-flight؛ بلا قراءة لاحقة بعد تغيير؛ المفتاح بلا الجلسة؛ **المفتاح بلا epoch**؛ قراءة لاحقة بعد الإغلاق؛ عدم مسح القراءة المنتهية.
- **انحدار:** `test/home/` كاملاً (R-02، P3.1c، الفلاتر) + `r2_home_responsive_test` ⇒ **301/301 PASS**؛ `test/auth/` + `map_sdk_warmup_test` ⇒ **282 PASS، 7 FAIL = FU-AUTH-BASELINE-7 بالضبط**.
- **Analyzer** (الملف + الاختبار) → No issues (أُزيل استعمال `notifyAllSubscribers` الداخلي لصالح `refreshSession()` الحقيقي). **Format:** الملفان مطابقان. **`git diff --check`** → نظيف.

### كفاءات متبقية (غير منفّذة)
- **P3.3 (التالي):** كل قراءة أعداد = 7 طلبات `GET select=id` تُرجع صفوف المعرّفات ⇒ HEAD count (حمولة).
- token refresh كل ساعة ما زال يقرأ الأعداد (محفوظ عمداً كمحاولة ضمنية بعد الفشل).
- عودة تبويب Home = قراءة (Q3)؛ انتشار `CoreEntityMutationNotifier` لكل القوائم (Q4)؛ N+1 المفضلات (Q5)؛ `getRelatedItemsCount` متسلسل (Q6)؛ Search ست قراءات كاملة (Q7)؛ الترقيم/الاكتمال (P4).
- Samsung والبناء الأصلي **DEFERRED/UNVERIFIED**؛ القياس هنا اختباري لا حركة جهاز.

### الحالة و NOW / NEXT / STOP
- **P3.2 = CODE_PROVEN** — ليس REAL_DEVICE_VERIFIED. FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ P3.1a staging **PENDING**.
- **الملفات (غير مدمجة):** `lib/src/viewmodels/home_viewmodel.dart`؛ جديد `test/home/home_count_requests_test.dart`؛ وهذا الملف.
- **NOW:** موافقة المالك على commit. **NEXT:** **P3.3 — Count Payload Optimization** (بموافقة منفصلة). **STOP:** لا P3.3 تلقائياً؛ لا commit/push.
- **أُودع** بموافقة المالك: `b288bf4` `perf(home): deduplicate concurrent count requests` (3 ملفات)، ودفعه المالك (`origin` = `b288bf4`، §7AG).

---

## 7AG) P3.3 — تحسين حمولة طلبات أعداد Home — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `b288bf4` = `origin` (0/0)، نظيف، stashes = 2.

### شكل الاستعلام قبل/بعد (`SupabaseHomeCountsService._countActiveRows`، الجداول السبعة)
- **قبل:** `from(t).select('id').isFilter('deleted_at', null).count(CountOption.exact)` ⇒ **GET** `?select=id&deleted_at=is.null` + `Prefer: count=exact` ⇒ الخادم يرسل **صفوف المعرّفات كلها** (حتى `max_rows`) والعدد في `Content-Range`.
- **بعد:** `from(t).count(CountOption.exact).isFilter('deleted_at', null)` ⇒ **HEAD** `?deleted_at=is.null` + `Prefer: count=exact` ⇒ **لا جسم**؛ العدد من `Content-Range`. **الفلتر نفسه** (`deleted_at is null`؛ لا فلتر مالك صريح قبل ولا بعد — RLS + بوابة الجلسة كما هما)، **`CountOption.exact` نفسه**.
- **API مُتحقَّق من المصدر المثبّت (`postgrest 2.9.1`):** `PostgrestQueryBuilder.count([CountOption])` ⇒ `HttpMethod.head` ⇒ `PostgrestFilterBuilder<int>`. التحليل: `Content-Range` مفقود أو `*/*` ⇒ العدد null ⇒ **cast إلى int يرمي**؛ مشوّه ⇒ `FormatException`؛ حالة ≠ 2xx ⇒ `PostgrestException` — **لا يصير أيٌّ منها صفراً**؛ كلها تصل إلى `catch` القائم في `getCounts` ⇒ **القيمة المعروضة تبقى** (السلوك القديم نفسه). فرع `count: 0` في المكتبة خاص بـ `maybeSingle` فقط.

### القياس (MEASURED في اختبار حتمي — بديل PostgREST؛ أعداد الصفوف محاكاة لا بيانات مستضافة)
| صفوف لكل جدول | جسم الاستجابة لكل قراءة أعداد (7 طلبات) — قبل | بعد |
|---|---|---|
| 0 | 14 بايت (`[]`×7) | **0** |
| 3 | 973 بايت | **0** |
| 250 | 80,507 بايت | **0** |
| 1000 (= `max_rows` المحلي) | 322,007 بايت | **0** |
**عدد الطلبات بلا تغيير:** 7 لكل قراءة؛ قياسات P3.2 كلها كما هي (بدء بارد 7، مُطلِقات متزامنة 14، 0 بعد الإغلاق…). الحمولة لكل معرّف ≈ 46 بايت (`{"id":"<uuid>"}`). خط الأساس قيس على كود HEAD (`b288bf4`) قبل التغيير بالاختبار نفسه.

### الأدلة (شغّلها الوكيل)
- **جديد `test/home/home_count_payload_test.dart` — 12/12 PASS** (على الكود القديم: الشكل والحمولة وتكامل Home فشلت، والدقة/الفشل الآمن نجحت — أي أن السلوك محفوظ): 7 طلبات HEAD بجدول لكلٍّ ومعاملات الاستعلام **بالضبط** `{deleted_at: is.null}` و`count=exact`؛ **0 بايت** لـ 3/250/1000 صف؛ الأعداد السبعة دقيقة (1..7 لكل مفتاح بما فيه `requested`/`quotation`)؛ صفر شرعي = 0؛ `Content-Range` مفقود/`*/*`/مشوّه ⇒ **المعروض يبقى، لا صفر**؛ 401/403/500 ⇒ المعروض يبقى؛ **تكامل Home:** جلسة مُزاحة (البوابة ترشّح كل صف ⇒ أصفار) لا تستبدل الأعداد المعروضة ولا كاش R-02.
- **حُدِّث عمداً:** `core_entity_query_contract_test` (P3.0) كان يثبّت «7 GET بـ `select=id`» ⇒ يثبّت الآن «7 HEAD بالفلتر نفسه»؛ بديل `home_count_requests_test` (P3.2) يعدّ GET **و**HEAD (أداة قياس، بلا تغيير توقعات) ⇒ قياساته كما هي.
- **فحص الطفرات — 4/4 التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): إسقاط فلتر «غير محذوف»؛ `estimated` بدل `exact`؛ عدد غير صالح يُقرأ صفراً؛ العودة إلى GET `select=id`.
- **انحدار:** `test/home/` كاملاً (R-02، P3.1c، P3.2، P3.3، الفلاتر) + `r2_home_responsive_test` + `core_entity_query_contract_test` + `core_entity_refresh_stream_test` ⇒ **318/318 PASS**. `test/auth/` لم يُعَد (لا يستورد الخدمة؛ FU-AUTH-BASELINE-7 كما هو).
- **Analyzer** → No issues. **Format:** الملفات الأربعة مطابقة للمنسِّق (صُحّح تخطيط سطر واحد في الخدمة ثم أُعيدت الاختبارات المركّزة 26/26). **`git diff --check`** → نظيف.
- **ملاحظة تشغيل:** أول تشغيل بدا معلّقاً لأن تشغيلاً سابقاً نُقل إلى الخلفية وبقي يعمل؛ بعد إيقافه نجحت الاختبارات في ثوانٍ — لا تعليق في الاختبارات.

### الحدود المتبقية
- **عدّ `exact` على الخادم** ما زال يكلّف مسحاً للصفوف المطابقة (لا يُقاس هنا؛ `planned`/`estimated` غير دقيقة فلم تُعتمد).
- 7 طلبات لكل قراءة (لا RPC مجمّع — يحتاج تغيير خادم وموافقة)؛ token refresh كل ساعة يقرأ الأعداد؛ عودة تبويب Home (Q3)؛ انتشار إشعار التعديل (Q4)؛ `getRelatedItemsCount` متسلسل بـ `select=id` (Q6)؛ Search (Q7)؛ الترقيم/الاكتمال (P4).
- القياس اختباري؛ **staging/PostgREST المستضاف وSamsung والبناء الأصلي DEFERRED/UNVERIFIED** (HEAD عبر الشبكة الحقيقية/البروكسي غير مُتحقَّق منه).

### الحالة و NOW / NEXT / STOP
- **P3.3 = CODE_PROVEN** — ليس REAL_DEVICE_VERIFIED ولا STAGING_VERIFIED. FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ P3.1a staging **PENDING**.
- **الملفات (غير مدمجة):** `lib/src/services/supabase_home_counts_service.dart`؛ جديد `test/home/home_count_payload_test.dart`؛ `test/home/home_count_requests_test.dart` (أداة العدّ)؛ `test/lists/core_entity_query_contract_test.dart` (العقد الجديد)؛ وهذا الملف.
- **NOW:** موافقة المالك على commit. **NEXT:** **P3.4 — Favorites N+1** (بموافقة منفصلة). **STOP:** لا P3.4 تلقائياً؛ لا commit/push.
- **أُودع** بموافقة المالك: `9d43a7c` `perf(home): eliminate row payload from count queries` (5 ملفات)، ودفعه المالك (`origin` = `9d43a7c`، §7AH).

---

## 7AH) P3.4 — إزالة N+1 في المفضلات (Favorites) — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `9d43a7c` = `origin` (0/0)، نظيف، stashes = 2.

### النمط قبل التغيير (مُثبت من المصدر ومقيس)
- **المرحلة 1 — أي العناصر مفضّلة:** `FavoriteService._getServerFavoritesWithMetadata` = 6 طلبات (`favorite_<type>`: `select=target_id,added_at` + `owner_id` + `order=added_at.desc`) **واحداً بعد الآخر** (`for … await`).
- **المرحلة 2 — بطاقة لكل مفضل:** `FavoritesViewModel._load<Type>WithMetadata` = **طلب لكل مفضل** (`getX(id)` بـ `id=eq.` + `owner_id` + `deleted_at is null` + `limit=1`)، **متسلسلة داخل النوع** (الأنواع الستة بالتوازي). Offer: لكل عنصر قراءة الصف ثم **استدعاء Worker للوسائط** (`resolveOfferMediaFor`) قبل العنصر التالي. Owner: قراءات متسلسلة ثم وسائط **كلها دفعة واحدة بلا حد**.

### التصميم بعد التغيير
- **`SupabaseCoreEntitiesService._rowsByIds`:** لكل نوع `select(<أعمدة القراءة المفردة نفسها>)` + `eq('owner_id', الحساب)` + `inFilter('id', …)` + `isFilter('deleted_at', null)` — **الفلاتر نفسها** (RLS + البوابة كما هما). **100 معرّف لكل طلب** (المعرّف مفتاح أساسي ⇒ الصفوف ≤ المعرّفات، أقل بكثير من حد الصفوف؛ سطر الطلب بضعة KB)؛ القطع متسلسلة. بعد كل قراءة: إن تغيّر الحساب المسجَّل ⇒ `StateError` (كما `getOfferMetadata`). دوال جديدة: `get{Requests,Offers,Owners,Offices,Brokers,Watchmen}ByIds` (+ مغلّفات في الخدمات الست).
- **Offers:** دفعة الصفوف ثم الوسائط **كما في `getOffer` تماماً** (`_withDisplayMedia` المستخرجة منها: best effort؛ فشل الوسائط ⇒ العرض دون وسائط؛ تغيّر الحساب ⇒ يُسقَط) — **استدعاء Worker لكل Offer باقٍ** (لا endpoint مجمّع؛ إضافته تغيير خادم)، لكن **4 في آن** (`mediaReadsAtOnce`) بدل واحد. Owners: الوسائط **4 في آن** بدل بلا حد. **الحد لكل نوع:** عند تحميل Offers وOwners معاً يصل المجموع إلى **8** استدعاءات Worker في آن (مقيس 5–8؛ لا حد مشترك). `stop` ⇒ بعد إغلاق الشاشة لا تبدأ قراءة وسائط جديدة (الجارية تكتمل وتُهمل نتيجتها).
- **`FavoritesViewModel`:** البطاقات تُبنى **بترتيب المفضلات** (لا ترتيب رد الخادم) بتاريخ الإضافة نفسه؛ المفقود/المحذوف/لحساب آخر ⇒ بلا بطاقة. **فشل قراءة نوع ⇒ تبقى البطاقات المعروضة له التي ما زالت مفضّلة** (فشل ≠ فراغ؛ كانت كل بطاقة تفشل قراءتها تُسقط ثم يُكتب الكاش ناقصاً)؛ الأنواع الأخرى لا تتأثر. حراس الحساب (`_isCurrentForAccount`/الجيل) والتخلّص والمطابقة مع الإضافات/الإزالات المتفائلة **بلا تغيير**. حقن اختياري للخدمات الأربع الأخرى (الافتراضي كما هو).
- **`FavoriteService`:** الطلبات الستة **معاً** (`Future.wait`)، الفلتر والترتيب نفسهما، أي فشل ⇒ `{}` كما كان؛ مدخل اختبار (`client`, `currentUserId`) — الإنتاج بلا تغيير.
- لا SQL/RLS/Auth، لا تغيير في الواجهة أو الكاش/التشفير/العلامات، لا حزم جديدة. ملف جديد صغير: `lib/src/services/bounded_tasks.dart` (`mapWithLimit`).

### القياس (MEASURED — اختبار حتمي: الخدمات الحقيقية + خدمة الوسائط على بديل HTTP مسجِّل؛ لا شبكة مستضافة)
| الحالة | طلبات قاعدة البيانات قبل → بعد | أقصى توازٍ | Worker قبل → بعد (أقصى توازٍ) |
|---|---|---|---|
| لا مفضلات | 0 → 0 | — | 0 → 0 |
| Offer واحد | 1 → 1 | 1 → 1 | 1 → 1 |
| 10 Requests | **10 → 1** | 1 → 1 | 0 |
| 10 Offers بوسائط | **10 → 1** | 1 → 1 | 10 → 10 (**1 → 4**) |
| 10 Owners بوسائط | **10 → 1** | 1 → 1 | 10 → 10 (**10 → 4**) |
| 2 من كل نوع (12) | **12 → 6** | 6 → 6 | 4 → 4 |
| 5 Offers: 2 حيّان + محذوف + لحساب آخر + مفقود | **5 → 1** | 1 → 1 | 2 → 2 |
| 250 Broker | (250) → **3** (100/100/50) | — | 0 |
| قائمة المفضلات (المرحلة 1) | 6 → 6 | **1 → 6** | — |
- خط الأساس قيس على كود HEAD (`9d43a7c`) بالأداة نفسها قبل أي تغيير؛ المرحلة 1 قيست بطفرة تعيد الحلقة المتسلسلة (P10 أدناه). **زمن الشبكة الفعلي غير مقيس**: المتوقع أن سلسلة N رحلة تصبح رحلة واحدة لكل نوع، لكنه استنتاج لا قياس.

### الأدلة (شغّلها الوكيل)
- **جديد `test/favorites/favorites_request_count_test.dart` — 14/14** (12 + 2 من المراجعة النهائية: Offers وOwners معاً ≤ 4 لكل نوع/8 إجمالاً؛ إغلاق الشاشة أثناء قراءة الوسائط لا يبدأ قراءة أخرى لـ Offers ولا لـ Owners): شكل الطلب (طلب لكل نوع، `owner_id`/`deleted_at`/`id=in.(…)` بالضبط، **الأعمدة مطابقة للقراءة المفردة**، لا limit/order)؛ الأعداد أعلاه؛ الوسائط لكل بطاقة Offer/Owner وحد 4؛ فشل الوسائط ⇒ البطاقة بلا وسائط؛ **الترتيب** (بما فيه التعادل، والخادم يرد بترتيب معكوس)؛ المفقود/المحذوف/حساب آخر؛ 250 بلا نقص؛ فشل نوع عند التحديث يُبقي بطاقاته ويحدّث الأخرى؛ فشل نوع في التحميل الأول يتركه وحده؛ **تغيّر الحساب أثناء القراءة ⇒ لا نشر ولا إشعار**؛ رد بعد تغيّر الحساب المسجَّل ⇒ مرفوض؛ إغلاق الشاشة أثناء القراءة ⇒ لا قراءة وسائط.
- **جديد `test/favorites/favorites_metadata_requests_test.dart` — 2/2:** الطلبات الستة معاً بالفلتر والترتيب نفسهما والتعيين؛ فشل قائمة واحدة ⇒ `{}` كما كان.
- **المراجعة النهائية — استبدال الجلسة للحساب نفسه:** الحماية القائمة (بلا تغيير) = كل نهاية جلسة تصل `AuthViewModel._handleSessionIdentity` كهوية null ⇒ `FavoriteService.invalidateForAccountChange()` ⇒ كل شاشة مفضلات أقدم تصبح قديمة (لا نشر، لا كاش) حتى لو عاد **الحساب نفسه**؛ وفحص الحساب داخل `_rowsByIds` بالـ uid فقط (لا يميّز جلستين لحساب واحد — الحماية من الجيل). **جديد `test/favorites/favorites_same_account_session_test.dart` — 1/1** بـ `AuthViewModel` الحقيقي: قراءة معلّقة ← خروج ← دخول الحساب نفسه ← الرد ⇒ لا بطاقات ولا كتابة كاش ولا إشعار؛ شاشة جديدة تحمّل طبيعياً. طفرة حذف الزيادة عند الخروج ⇒ **التُقطت**. **فخ:** يجب استيراد Favorites بـ `src/Views/…` كالتطبيق؛ تهجئة `views` تنشئ نسخة ثانية من المكتبة بعدّاد جيل مستقل (في الإنتاج المسار واحد: `app.dart` ← `Views`).
- **طفرات المراجعة:** تجاهل `stop` لوسائط Owners ⇒ **التُقطت**؛ لوسائط Offers ⇒ **التُقطت**. بعد المراجعة `test/favorites` ⇒ **95/95**.
- **حُدِّث عمداً:** بدائل `getOffer`/`getOwner` في `favorites_viewmodel_initial_load_test` و`favorites_list_reconciliation_test` و`r2_search_favorites_responsive_test` تجيب الآن أيضاً عن `getOffersByIds`/`getOwnersByIds` من بياناتها نفسها (بلا تغيير توقعات).
- **فحص الطفرات — 10/10 التُقطت** (الملفات أُعيدت، `Get-FileHash` مطابق): إسقاط فلتر المالك؛ إسقاط فلتر الحذف؛ بلا تقطيع؛ إزالة فحص تغيّر الحساب؛ تجاهل `stop`؛ وسائط بلا حد (نجت أول مرة لأن الاختبار قارن بالثابت نفسه ⇒ ثُبّت الحد 4 حرفياً ثم التُقطت)؛ وسائط واحدة واحدة؛ ترتيب الخادم بدل المفضلات؛ فشل يُسقط البطاقات المعروضة؛ قائمة المفضلات متسلسلة (شكل HEAD).
- **انحدار:** `test/favorites` + `test/lists` + `test/offers` + `test/owners` + `r2_search_favorites_responsive_test` ⇒ **839/839**؛ map/plan_attachment/related_items/r5a–r5d responsive/email_change_callback ⇒ **320/320**؛ بعد تصحيح التنسيق `test/favorites` ⇒ **92/92**.
- **Analyzer** → No issues. **Format (language 3.5):** الملفات الجديدة مطابقة؛ في المعدّلة لا انحراف جديد (انحرافات `offer_service`/`owner_service`/`favorites_viewmodel`/`favorites_list_reconciliation_test` موجودة في HEAD بالعدد نفسه، لم تُلمس). **`git diff --check`** → نظيف.

### الحدود المتبقية
- **Worker لكل Offer/Owner ذي وسائط** (N استدعاء، 4 في آن لكل نوع، حتى 8 إجمالاً) — دفعة حقيقية تحتاج endpoint مجمّع في الـ Worker (تغيير خادم + موافقة).
- **جلسة مُزاحة (Single Active Device) قبل اكتشافها:** قراءات Favorites (القائمة والسجلات) تعود فارغة بصمت من بوابة الجلسة كما في F-SAD-EMPTY ⇒ قد تُعرض/تُكتب بطاقات ناقصة حتى تصل هوية null — **قائم قبل P3.4 بالدرجة نفسها** (قراءة لكل عنصر كانت تعود null أيضاً)؛ غير محلول هنا.
- **فشل قراءة قائمة المفضلات (المرحلة 1) ما زال يُرجع `{}` ⇒ تُعرض «لا مفضلات»** (قائم منذ قبل؛ لا يُكتب الكاش في ذلك الفرع) — **FU-FAV-META-EMPTY، OPEN**، يحتاج قراراً منفصلاً.
- قوائم المفضلات بلا ترقيم: حد `max_rows` المستضاف قد يقطع أكثر من 1000 مفضل لنوع واحد بصمت (P4)؛ حد `max_rows` المستضاف وطول سطر الطلب عبر البروكسي **غير مُتحقَّق منهما** (100 معرّف ≈ 4 KB).
- فشل نوع في **التحميل الأول** (لا بطاقات سابقة) ما زال يُترك فارغاً ويُكتب الكاش بدونه (كما كان لكل عنصر يفشل).
- التحديث الدوري/المتفائل يعيد القراءة كاملة (6 + ≤6 + الوسائط) — لا تغيير هنا.
- **staging/PostgREST المستضاف وSamsung والبناء الأصلي DEFERRED/UNVERIFIED.**

### الحالة و NOW / NEXT / STOP
- **P3.4 = CODE_PROVEN** — ليس REAL_DEVICE_VERIFIED ولا STAGING_VERIFIED. FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ P3.1a staging **PENDING**؛ FU-FAV-META-EMPTY **OPEN**.
- **الملفات (غير مدمجة):** `lib/src/services/supabase_core_entities_service.dart`؛ الخدمات الست `lib/src/services/ScreenServices/{request,offer,owner,office,broker,watchmen}_service.dart`؛ جديد `lib/src/services/bounded_tasks.dart`؛ `lib/src/views/Screens/home/favorites/{favorites_viewmodel,favorites_service}.dart`؛ جديدة `test/favorites/favorites_request_count_test.dart` و`test/favorites/favorites_metadata_requests_test.dart` و`test/favorites/favorites_same_account_session_test.dart` (من المراجعة النهائية)؛ البدائل في `test/favorites/favorites_viewmodel_initial_load_test.dart` و`test/favorites/favorites_list_reconciliation_test.dart` و`test/responsive/r2_search_favorites_responsive_test.dart`؛ وهذا الملف.
- **NOW:** موافقة المالك على commit. **NEXT:** **P4 — Pagination & Complete Lists** (الترقيم، `max_rows`، الاكتمال الحقيقي، مفتاح ترتيب ثانٍ) بموافقة منفصلة؛ وبقية P3 (Q3/Q4/Q6/Q7) حسب قرار المالك. **STOP:** لا P4 تلقائياً؛ لا commit/push.
- **أُودع** بموافقة المالك: `268c9c1` `perf(favorites): batch entity reads and bound media concurrency` (17 ملفاً)، ودفعه المالك (`origin` = `268c9c1`، §7AI).

---

## 7AI) P4.0 — تدقيق معمارية الترقيم والقوائم الكاملة — 2026-11-03 (AUDIT؛ لا تغيير كود إنتاجي)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `268c9c1` = `origin` (0/0)، نظيف، stashes = 2.

### 1) الاستعلامات الحالية (مُتحقَّق من المصدر)
- القوائم الست `SupabaseCoreEntitiesService._fetch{Requests,Offers,Owners,Offices,Brokers,Watchmen}` عبر `_refreshedStream`: `select(<أعمدة>)` + `eq('owner_id', الحساب)` + `isFilter('deleted_at', null)` + `order('created_at', desc)` ⇒ `order=created_at.desc.nullslast` — **مفتاح ترتيب واحد، بلا limit/offset/Range/count**. ترجع قائمة كاملة كـ `Stream<List<T>>` (قراءة واحدة في آن، تعديل أثناء القراءة ⇒ قراءة أخرى بعدها، الإلغاء يُهمل الجارية لكنه لا يوقفها).
- المخطط: `created_at timestamptz NOT NULL DEFAULT now()` في الجداول الست؛ `id` uuid مفتاح أساسي؛ فهرس `(owner_id, created_at desc)` لكل جدول. التطبيق **لا يرسل `created_at` أبداً** (لا في الإدراج ولا التحديث، `CoreEntityPayloadBuilder`)، لكن لا trigger يمنع تعديله (عدا Toolkit) ⇒ ثابت عملياً لا مضمون.
- الحماية: الحساب (`stillTheAccount`) + الجلسة (`stillTheReader`، P3.1b — خروج ودخول للحساب نفسه = جلسة جديدة) + تأكيد القائمة الفارغة (`confirmEmptyList`) + بوابة الجلسة في قاعدة البيانات (جلسة مُزاحة ⇒ صفر صفوف بلا خطأ).
- **مثبت باختبار جديد** `test/lists/list_row_cap_characterization_test.dart` (1/1): خادم بحد 1000 صف و1200 Request ⇒ القائمة 1000 **بلا خطأ ولا أي إشارة**؛ الطلب بلا limit/offset/count وبمفتاح ترتيب واحد. (PostgREST يرد على القراءة المقطوعة بـ 200 و`Content-Range: 0-999/*`.) **تناقض ظاهر اليوم:** أعداد Home `exact` (P3.3) قد تقول 1200 بينما القائمة 1000.

### 2) `max_rows`
- المحلي: `supabase/config.toml` → `[api] max_rows = 1000`.
- **المستضاف: UNKNOWN.** فحص قراءة فقط (CLI 2.109.1 مربوط من مجلد scratch معزول، SELECT واحد على `pg_db_role_setting`؛ الأثر الوحيد: login role المؤقت المعتاد «Initialising login role…»): لا إعداد `pgrst.*` في قاعدة البيانات لـ `authenticator`/`anon`/`authenticated` ⇒ القيمة في إعدادات المنصة (env) خارج متناول SQL للقراءة. لا أمر CLI للقراءة (`config` = push كتابة، لم يُستخدم). **لا يُفترض أن 1000 هو المستضاف**؛ التصميم أدناه صحيح أياً كانت القيمة.

### 3) واجهات الترقيم في `postgrest 2.9.1` المثبّت (من المصدر)
- `order()` متسلسل يُلحق مفاتيح (`order=created_at.desc.nullslast,id.desc.nullslast`)؛ `limit(n)`؛ `range(from,to)` = `offset` + `limit`؛ `or('…')` لشرط keyset مركّب؛ `lt/lte/gt/gte`؛ `.count(CountOption.exact)` بعد `select` يعطي البيانات والعدد معاً (`PostgrestResponse`). لا حاجة لحزمة جديدة.

### 4) البدائل
| | offset/range | keyset (cursor) — **الموصى به** |
|---|---|---|
| ترتيب ثابت | يحتاج `id` كمفتاح ثانٍ أيضاً | `(created_at desc, id desc)` ترتيب كلي |
| إدراج أثناء الترقيم | السجلات الجديدة (الأحدث، في الأعلى) تزيح الإزاحات ⇒ **تكرار** عند حد الصفحة | الجديد أحدث من المؤشر ⇒ خارج هذه اللقطة؛ لا تكرار |
| حذف أثناء الترقيم | السجلات تنزاح للخلف ⇒ **تخطّي سجلات حيّة بصمت** (إزالة التكرار لا تصلحه) | لا إزاحة ⇒ لا تخطّي للباقين |
| تعديل | `created_at` لا يتغير ⇒ لا أثر | كذلك |
| كلفة الخادم | `OFFSET` يمسح كل ما قبله (خطّي متزايد) | يبدأ من الفهرس عند المؤشر |
- **حدود keyset الموثّقة:** صف من معاملة بدأت قبل المؤشر وأُكملت بعده قد يحمل `created_at` أقدم ⇒ يغيب عن هذه اللقطة فقط ويظهر في التحديث التالي؛ تعديل `created_at` يدوياً (التطبيق لا يفعله) يكسر الافتراض.
- **UI pagination (تمرير لا نهائي) مقابل لقطة كاملة مُرقّمة:** الأول يغيّر عقد الواجهة، ويجعل الكاش المشفّر نوافذ جزئية (الاكتمال unknown للأبد)، ويُربك البحث وطبقة العلامات والأعداد ⇒ إعادة تصميم كبيرة. الثاني **لا يغيّر الواجهة ولا عقد الكاش** (قائمة كاملة تستبدل المحفوظة كلها كما الآن) ويمكّن لاحقاً من «مكتمل حتى وقت القراءة». **التوصية: لقطة كاملة مُرقّمة أولاً**؛ UI pagination قرار منفصل لاحق إن ظهرت حاجة أداء مقيسة.

### 5) التصميم الموصى به (P4.1)
- **مكان التغيير:** داخل `_fetchX` فقط (دالة مشتركة `_pagedRows`)، بنفس `select`/`owner_id`/`deleted_at`؛ يبقى `Stream<List<T>>` و`localFirstList` والكاش كما هي.
- **الترتيب:** `order('created_at', desc)` ثم `order('id', desc)` — يغيّر ترتيب السجلات المتعادلة تماماً فقط (كان غير محدد) ⇒ **قرار مالك (ترتيب العرض)**.
- **الصفحة:** `limit(P)`؛ التالية `or('created_at.lt.<c>,and(created_at.eq.<c>,id.lt.<i>)')` حيث `<c>` **النص الخام** لـ `created_at` من الصف (لا إعادة تنسيق — دقة الميكروثانية و`+00:00`)، و`<i>` معرّفه. **P المقترح 500** (≤ القيمة الافتراضية المعتادة، ~0.5 MB لكل صفحة) — قرار مالك.
- **الاكتمال (لا يعتمد على `max_rows`):** الصفحة الأولى بـ `count(CountOption.exact)` ⇒ T. توقّف عند: صفحة فارغة، أو المجمَّع ≥ T. صفحة قصيرة والمجمَّع < T ⇒ تابع (الحد المستضاف أصغر من P، أو حذف حدث). ⇒ قائمة صغيرة = **طلب واحد** كاليوم (+ عدّ الخادم)؛ N كبيرة ≈ ⌈N/P⌉.
- **حد أعلى للصفحات** (مثلاً 40×500 = 20,000) ⇒ تجاوزه = **خطأ «غير مكتمل»** لا قطع؛ يبقى المحفوظ — قرار مالك للرقم.
- **الذرّية:** الصفحات تُجمع في الذاكرة؛ تحقق: لا معرّف مكرر (تكرار ⇒ عدم اتساق ⇒ خطأ)، ثم **تُسلَّم القائمة كاملة مرة واحدة** ⇒ `localFirstList.accept` ⇒ `cache.write` يستبدل v2/HMAC كاملاً كما الآن. **أي فشل صفحة ⇒ القراءة كلها ترمي** ⇒ `fail` القائم ⇒ لا عرض جديد ولا كتابة، المحفوظ ووقته كما هما، والإعادات P2.5b كما هي. لا تُحفظ صفحة جزئية أبداً.
- **الجلسة:** `readSession` القائم يُلتقط قبل `server()` ⇒ `stillTheReader` عند التسليم (يرفض خروجاً ودخولاً للحساب نفسه). إضافة: بعد كل صفحة، إن تغيّر الحساب أو `ListSessionCheck.currentSession()` عن بدايته ⇒ خطأ (لا قائمة). **خطر خاص بالترقيم:** جلسة تُزاح بعد الصفحة 1 تُرجع صفحات تالية فارغة ⇒ تبدو «نهاية القائمة» ⇒ قطع صامت. القاعدة: إن انتهت القراءة والمجمَّع < T ⇒ `ListSessionCheck.confirmFor(session)` قبل القبول؛ مؤكدة ⇒ حذف شرعي (تُقبل)؛ غير مؤكدة ⇒ `ListSessionNotCurrent` (لا عرض ولا حفظ، تسجيل الخروج المعتاد). الصفحة الأولى الفارغة تبقى على مسار `confirmEmptyList` القائم.
- **الفراغ/النقص/الشبكة:** فارغ مؤكد الجلسة = فراغ شرعي (يُحفظ)؛ غير مكتمل (حد الصفحات، تكرار، نقص غير مؤكد) = خطأ غير شبكي (يوقف الإعادات كأي خطأ غير شبكي — أو يُعامل كشبكي: **قرار في P4.1**)؛ فشل شبكة في أي صفحة = خطأ شبكي (إعادات P2.5b).
- **العلامات (P3.1d):** بلا تغيير — تُطبَّق على القائمة الكاملة عند العرض؛ **لا تقاعد أبداً من الصفحات** (ولا من القائمة الكاملة، بانتظار قرار P4/المالك)؛ السعة 1000 والحجب الصارم كما هما.
- **D-2:** `mayRecover` يبقى لقراءة خادم ناجحة كاملة فقط — والترقيم لا يسلّم غيرها.
- **الإلغاء:** `_refreshedStream` اليوم يُهمل القراءة الجارية فقط ⇒ P4.1 يمرّر «ما زال مطلوباً؟» إلى `_pagedRows` فلا تُطلب صفحة بعد إغلاق الشاشة.

### 6) الأداء والذاكرة
- الصفحات متسلسلة بالضرورة (المؤشر)؛ القوائم الست مستقلة (كل شاشة قائمتها) ⇒ لا توازٍ جديد.
- الكلفة على الحساب الصغير (الأغلب): كاليوم + `count=exact` (مسح مفهرس لصفوف الحساب). الحساب الكبير: ⌈N/P⌉ رحلة بدل رحلة واحدة مقطوعة.
- الذاكرة: القائمة كاملة في الذاكرة (كاليوم) + JSON في قيمة Hive واحدة مشفرة بـ HMAC على الحمولة كلها ⇒ لـ 10k سجل عدة MB تُشفَّر على الخيط الرئيسي — **يُقاس في P4.1** قبل اعتماد الحد الأعلى.
- Search (Q7) يقرأ القوائم الست نفسها ⇒ يصبح كاملاً وأثقل؛ Favorites: قوائم `favorite_<type>` بلا ترقيم (حد `max_rows` نفسه)، ودفعات 100 معرّف (P3.4) لا تتأثر — **خارج P4.1**.

### 7) خطة مرحلية وحدود القرار
- **P4.1 (أصغر نقطة آمنة):** `_pagedRows` + تطبيقه على **Requests فقط** + الاختبارات أدناه؛ الخمس الأخرى بلا تغيير. **قرارات مطلوبة قبل التنفيذ:** (أ) ترتيب `id desc` للمتعادلات؛ (ب) P = 500؛ (ج) الحد الأعلى للصفحات؛ (د) «غير مكتمل» خطأ شبكي أم لا.
- **P4.2:** الخمس الأخرى بالدالة نفسها والاختبارات نفسها (مُعاملة بالنوع).
- **P4.3:** تحقق staging (PostgREST المستضاف: ترميز المؤشر عبر البروكسي، `max_rows` الفعلي، العدّ) بحساب الاختبار المعيّن — **owner-run** (الإنتاج والـ staging مشروع واحد).
- **P4.4 (اختياري):** `ListCompleteness.complete` حتى وقت القراءة في سجل المزامنة (تغيير صيغة سجل P2.5c ⇒ موافقة).
- لاحقاً بقرارات منفصلة: قوائم المفضلات، Search، UI pagination.
- **اختبارات P4.1 المطلوبة:** صفحة واحدة = طلب واحد (`order`, `limit`, `count=exact`)؛ 2P بالضبط؛ حد خادم أصغر من P (مثلاً 300 مع P=500 و1200 سجل ⇒ الكل)؛ تعادلات كثيرة عبر حد الصفحة بلا تكرار/تخطٍّ؛ إدراج وحذف أثناء الترقيم (لا تخطّي للباقين، مع مقارنة offset)؛ فشل صفحة وسطى ⇒ لا تسليم والمحفوظ كما هو؛ إزاحة الجلسة بعد الصفحة 1 ⇒ `ListSessionNotCurrent` بلا حفظ؛ خروج ودخول للحساب نفسه أثناء الترقيم ⇒ يُهمل؛ إلغاء ⇒ لا صفحة أخرى؛ تجاوز الحد ⇒ خطأ لا قطع؛ ترميز `created_at` (ميكروثانية، `+00:00`) ذهاباً وإياباً؛ العلامات على قائمة متعددة الصفحات + الحجب؛ القائمة الفارغة على المسار القائم؛ قياس حجم/زمن حفظ 5k سجل؛ طفرات لكل قاعدة.

### الحالة و NOW / NEXT / STOP
- **P4.0 = AUDIT** — لا تغيير كود إنتاجي ولا SQL/RLS/Auth/إعدادات ولا حزم؛ اختبار توصيف واحد.
- **مفتوح:** FU-FAV-META-EMPTY؛ `max_rows` المستضاف **UNKNOWN**؛ P3.1a staging **PENDING**؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ تقاعد العلامات مؤجَّل؛ Worker لكل وسائط (P3.4)؛ Q3/Q4/Q6/Q7. **Samsung والبناء الأصلي وstaging DEFERRED.**
- **الملفات (غير مدمجة):** جديد `test/lists/list_row_cap_characterization_test.dart`؛ وهذا الملف.
- **NOW:** قرار المالك في (أ)–(د) والموافقة على P4.1. **STOP:** لا P4.1 تلقائياً؛ لا commit/push.
- **قرار المالك (2026-11-03):** (أ) `created_at DESC, id DESC` ✔؛ (ب) 500 ✔؛ (ج) 40 صفحة / 20,000 سجل ✔؛ (د) **خطأ اكتمال مخصّص غير شبكي** — النقص والتوقف المبكر وغياب العدّ وتجاوز الحد ليست أعطال اتصال، بلا إعادات غير محدودة؛ عطل الشبكة الحقيقي أثناء صفحة يبقى على الإعادات المحدودة القائمة. ⇒ P4.1 (§7AJ).

---

## 7AJ) P4.1 — ترقيم keyset لقائمة Requests — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `268c9c1` = `origin` (0/0)؛ غير مدمج من P4.0: هذا الملف + `test/lists/list_row_cap_characterization_test.dart`؛ stashes = 2.

### التنفيذ (Requests فقط؛ `lib/src/services/supabase_core_entities_service.dart`)
- **`_pagedRows`** (مشتركة، تُستخدم لـ Requests وحدها الآن): الفلاتر نفسها (`select` + `eq('owner_id')` + `isFilter('deleted_at', null)` — RLS وبوابة الجلسة كما هما)، `order(created_at desc).order(id desc).limit(500)`. الصفحة التالية: `or('created_at.lt.<c>,and(created_at.eq.<c>,id.lt.<i>)')` حيث `<c>` **نص `created_at` الخام** من الصف (ميكروثانية و`+00:00` محفوظان؛ مُثبت أن `+` يُرسل `%2B`) و`<i>` معرّفه.
- **العدّ:** الصفحة الأولى بـ `count(CountOption.exact)` (طلب واحد: صفوف + `Content-Range: 0-499/T`). عدّ مفقود أو `*` (cast المكتبة يفشل) أو مشوّه ⇒ `CoreEntityListIncomplete(missingCount)`.
- **الاكتمال (لا يعتمد على `max_rows`):** القراءة تستمر ما دام المجمَّع < T وآخر صفحة غير فارغة؛ **الصفحة القصيرة ليست نهاية** (حد خادم أصغر). كل صف يجب أن يأتي **بعد** سابقه بدقة (وقت أقدم، أو الوقت نفسه ومعرّف أصغر) ولمرة واحدة ⇒ صفحة تكرّر أو تعيد الترتيب أو لا تتقدم ⇒ `badPage`؛ صفوف الصفحة الأولى > T أو > 500 ⇒ `badPage`.
- **الحدود:** T > 20,000 ⇒ `tooLarge` **بعد الطلب الأول** (لا تُقرأ أول 20,000)؛ 40 صفحة دون اكتمال (حد خادم صغير) ⇒ `tooLarge`.
- **عدم التطابق:** إن انتهت الصفحات والمجمَّع ≠ T ⇒ `ListSessionCheck.confirmFor(جلسة القراءة)`: غير مؤكدة ⇒ `ListSessionNotCurrent` (جلسة مُزاحة تُرجع صفحات فارغة — لا تُقبل قائمة قصيرة)؛ مؤكدة ⇒ عدّ HEAD دقيق جديد: يساوي المجمَّع ⇒ قبول (حذف/إضافة شرعيان)؛ وإلا `changedDuringRead` ⇒ **إعادة نظيفة واحدة** من البداية (`_wholeList`)، وفشلها ⇒ الخطأ نفسه نهائياً.
- **الجلسة والإلغاء:** الحساب و`session_id` (من جلسة العميل نفسه) يُلتقطان عند البدء ويُفحصان **قبل كل طلب وبعده** ⇒ خروج، أو خروج ودخول **للحساب نفسه** ⇒ `ListSessionNotCurrent` بلا صفحة أخرى (تحديث التوكن يُبقي الجلسة). `_refreshedStream` يمرّر «ما زال مطلوباً؟» ⇒ بعد إلغاء الاستماع لا تُطلب صفحة أخرى (`_ListReadNotWanted` لا يراه أحد). الأنواع الخمسة الأخرى: تغيير توقيع ميكانيكي فقط (`(_) => _fetchX()`)، بلا تغيير سلوك.
- **الخطأ الجديد:** `CoreEntityListIncomplete(CoreEntityListProblem.{missingCount, tooLarge, badPage, changedDuringRead})` — **غير شبكي** (`isRetryableListError` = false ⇒ لا إعادات تلقائية)؛ عطل الشبكة في أي صفحة يمرّ كما هو (إعادات P2.5b المحدودة)، وخطأ الخادم كذلك. الواجهة بلا تغيير: `EntityListState` يُبقي القائمة المعروضة أو يُظهر حالة خطأ التحميل القائمة (لا نص تقني).
- **الذرّية والكاش:** القائمة تُسلَّم مرة واحدة كاملة إلى `localFirstList` ⇒ `cache.write` القائم يستبدل v2/HMAC كاملاً؛ أي فشل/نقص ⇒ لا تسليم ⇒ المحفوظ ووقت المزامنة كما هما. العلامات (P3.1d) والحجب الصارم وD-1a/D-2/D-3 **بلا تغيير**؛ لا تقاعد للعلامات.

### الاكتمال المُتحقَّق مقابل لقطة لحظية
الطلبات المنفصلة **ليست** معاملة PostgreSQL واحدة. المضمون: كل صف حيّ كان موجوداً عند الصفحة الأولى وبقي حتى نهاية القراءة يظهر **مرة واحدة بالضبط**، والمجموع يطابق عدّاً دقيقاً. غير المضمون: سجل أُضيف في الأعلى أثناء القراءة لا يظهر (القراءة التالية تُظهره)؛ سجل حُذف بعد وصول صفحته يبقى حتى القراءة التالية (والعلامات تخفيه إن حُذف من هذا الجهاز)؛ إضافة وحذف متعادلان بعد الصفحة الأولى لا يُكشفان؛ صف من معاملة بدأت قبل المؤشر وأُكملت بعده قد يغيب حتى القراءة التالية.

### القياس (MEASURED — اختبار حتمي، محاكاة PostgREST على MockClient؛ ليس شبكة مستضافة ولا Samsung)
| السجلات | قبل (HEAD) | بعد: الطلبات | جسم الاستجابة | المُجمَّع |
|---|---|---|---|---|
| 0 | 1 | 1 | 2 B | 0 |
| 500 | 1 | 1 | 290,230 B | 500 |
| 1,200 | 1 (ومع `max_rows`=1000 ⇒ **1000 فقط بصمت**) | 3 | 697,256 B | 1,200 |
| 10,000 | 1 (ومع 1000 ⇒ **1000 فقط**) | 20 | 5,829,700 B | 10,000 |
- الحمولة لكل سجل ≈ 580 B (أعمدة القائمة كاملة). القائمة الصغيرة (الأغلب) = **طلب واحد كما كانت** + عدّ دقيق في الطلب نفسه. الشاشة وعقد `Stream<List<RequestModel>>` بلا تغيير. زمن الشبكة والتشفير الفعلي لـ 10k سجل **غير مقيس**.

### الأدلة (شغّلها الوكيل)
- **جديد `test/lists/requests_keyset_pagination_test.dart` — كُتب أولاً: 27 فشلاً على القراءة القديمة**، ثم **37/37** (تصحيح في P4.2، §7AK: كُتب سابقاً «38/38» خطأً؛ الـ 42 = 37 + 4 العقد + 1 التوصيف): شكل الصفحة الأولى؛ 0/1/499/500/501/1000/1200 (عدد الطلبات، كل صف مرة، الترتيب)؛ مؤشر الصفحة التالية بالنص الخام و`%2B`؛ 1200 بحد خادم 1000؛ حد خادم 300 < 500؛ تعادلات `created_at` (3 أوقات لـ 1200 سجل)؛ حساب آخر/محذوف مستبعد؛ 20,001 ⇒ `tooLarge` بعد طلب واحد؛ 20,000 ⇒ 40 صفحة كاملة؛ حد 100 و4,500 ⇒ `tooLarge` بعد 40؛ خطأ 500 في الصفحة 2؛ عطل شبكة في الصفحة 3 (بعد إعادات المكتبة) ⇒ خطأ شبكي قابل للإعادة؛ عدّ مفقود/`*`/مشوّه ⇒ `missingCount` غير شبكي؛ عدّ أصغر من الصفوف؛ صف مكرر؛ خادم لا يتقدم؛ جلسة مُزاحة بعد الصفحة 1 ⇒ `ListSessionNotCurrent` (سُئل عن جلسة القراءة، بلا عدّ)؛ خروج ودخول للحساب نفسه ⇒ لا صفحة ثالثة؛ خروج ⇒ لا صفحة ثانية؛ إغلاق الشاشة ⇒ لا صفحة أخرى؛ إضافة في الأعلى (لا تظهر، بلا عدّ إضافي)؛ حذف لم يُقرأ بعد (عدّ ثانٍ ⇒ قبول 1199)؛ إضافة+حذف (إعادة واحدة ⇒ 1200: 7 طلبات + عدّ)؛ تغيّر في كل صفحة ⇒ `changedDuringRead` بعد إعادة واحدة؛ **كاش مشفّر حقيقي:** فشل الصفحة 2 لاحقاً ⇒ المحفوظ 1200 ووقته كما هما؛ عدّ مفقود ⇒ لا استبدال؛ سجل محذوف على الخادم ومتذكَّر ⇒ 1199 معروضة ومحفوظة، بلا حجب؛ صفحة متأخرة لا تزال تُدرج سجلاً محذوفاً مؤكداً ⇒ لا يظهر في أي قائمة و**لا يُحفظ** (قاعدة P3.1d) والوقت كما هو؛ القياسات.
- **حُدِّث عمداً:** `core_entity_query_contract_test` — Requests بالعقد الجديد، والخمسة الأخرى بالعقد القديم؛ `list_row_cap_characterization_test` (P4.0) يوصّف الآن **Offers** (ما زالت طلباً واحداً)، إذ لم تعد Requests تُقطع.
- **الطفرات — 13/13 التُقطت** (الملف أُعيد، `Get-FileHash` مطابق): بلا مفتاح `id`؛ الصفحة القصيرة نهاية؛ قبول بلا مطابقة؛ بلا فحص الحساب/الجلسة بين الصفحات؛ تجاهل الإلغاء؛ بلا حد 20,000؛ بلا حد 40 صفحة؛ بلا فحص التكرار/الترتيب؛ بلا الإعادة النظيفة؛ مؤشر من وقت مُعاد تنسيقه؛ عدّ مفقود غير مُعيَّن؛ قبول عدم التطابق بعد تأكيد الجلسة؛ عدم سؤال الجلسة. (أول تشغيل للأداة تخطّى كل الطفرات بخطأ في السكربت — PowerShell يسطّح مصفوفة زوج واحد — فلم يُحتسب؛ أُعيد بعد الإصلاح.)
- **انحدار:** `test/lists` كاملاً + `test/home` + `test/related_items` + `r5a_requests_responsive_test` ⇒ **754/754**؛ بعد آخر تعديل تنسيق: ملفات الترقيم والعقد والتوصيف ⇒ **42/42**.
- **Analyzer** → No issues. **Format (3.5):** الملفان الجديدان مطابقان؛ الملفان المتتبَّعان بلا انحراف جديد. **`git diff --check`** → نظيف.
- **ملاحظة بيئة:** أول تشغيل «أحمر» توقف لأن قرص C امتلأ مؤقتاً أثناء التجميع («not enough space»)؛ بعد عودة 15.7 GB أُعيد بنجاح — ليس من الاختبارات.

### الحدود المتبقية
- **`max_rows` المستضاف UNKNOWN**؛ التصميم صحيح أياً كانت القيمة، لكن إن كانت < 500 فحسابات > 40×القيمة تفشل بـ `tooLarge` (لا قطع). ترميز المؤشر عبر البروكسي المستضاف و`count=exact` مع `limit` على PostgREST الحقيقي **غير مُتحقَّق منهما** (P4.3).
- **الحساب > 20,000 Request** يرى خطأ تحميل (ويُبقي المحفوظ) بدل قائمة — قرار المالك.
- كلفة `count=exact` على الخادم لكل قراءة؛ عدّ HEAD إضافي فقط عند عدم التطابق.
- القائمة كاملة في الذاكرة وفي قيمة Hive واحدة مشفرة (10k ≈ 5.8 MB JSON) — زمن الحفظ على الجهاز **غير مقيس**.
- `getRelatedRequests` (حتى 10) وقراءات Search/Home filters عبر `getRequests` تستفيد تلقائياً؛ **الخمسة الأخرى ما زالت بلا ترقيم** (P4.2)؛ قوائم المفضلات بلا ترقيم.
- **staging وSamsung والبناء الأصلي DEFERRED.** FU-FAV-META-EMPTY وFU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ P3.1a staging **PENDING**.

### الحالة و NOW / NEXT / STOP
- **P4.1 = CODE_PROVEN** — ليس STAGING_VERIFIED ولا REAL_DEVICE_VERIFIED.
- **الملفات (غير مدمجة):** `lib/src/services/supabase_core_entities_service.dart`؛ جديد `test/lists/requests_keyset_pagination_test.dart`؛ `test/lists/core_entity_query_contract_test.dart`؛ `test/lists/list_row_cap_characterization_test.dart` (من P4.0، معدّل)؛ وهذا الملف (§7AI + §7AJ).
- **NOW:** موافقة المالك على commit. **NEXT:** **P4.2 — الترقيم للقوائم الخمس الأخرى** بالدالة نفسها والاختبارات نفسها؛ ثم P4.3 تحقق staging (owner-run). **STOP:** لا P4.2 تلقائياً؛ لا commit/push.
- **أُودع** بموافقة المالك: `4aefdc9` `feat(pagination): add complete keyset retrieval for Requests` (5 ملفات، P4.0 + P4.1)، ودفعه المالك (`origin` = `4aefdc9`، §7AK).

---

## 7AK) P4.2 — ترقيم keyset للقوائم الخمس الأخرى — 2026-11-03 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء (بعد `git fetch`):** `perf/phase-1-startup-baseline` @ `4aefdc9` = `origin` (0/0)، نظيف، stashes = 2.

### التنفيذ (`lib/src/services/supabase_core_entities_service.dart` فقط)
- `_fetchOffers` / `_fetchOwners` / `_fetchOffices` / `_fetchBrokers` / `_fetchWatchmen` تقرأ الآن عبر **`_wholeList` نفسها** من P4.1 (لا تنفيذ مستقل): الأعمدة نفسها (`_offerColumns` لـ Offers — الثابت المشترك مع `getOfferMetadata` منذ P3.4؛ `*` للأربعة كما كان `select()`)، والمحوّلات نفسها (`_xFromRow`)، والفلاتر نفسها؛ كل قواعد P4.1 كما هي (500، `created_at desc, id desc`، العدّ الدقيق، المؤشر المركّب، 40 صفحة/20,000، أخطاء الاكتمال، إعادة نظيفة واحدة، فحص الحساب/الجلسة قبل كل طلب وبعده، الإلغاء). `getX()` تمرّر `_fetchX` مباشرة إلى `_refreshedStream`.
- **الوسائط:** قراءة قائمة Offers/Owners **لا تطلب أي وسائط** (مثبت: 0 استدعاء Worker لقراءة 1200)، كما كانت؛ الوسائط تبقى لكل سجل حيث يُعرض.
- لا تغيير في الواجهة/الـViewModels/`localFirstList`/الكاش v2/HMAC/العلامات/D-1a/D-2/D-3. `getRelatedOffers`/`getRelatedRequests` (حتى 10) بلا تغيير. **لا كيان احتاج تنفيذاً مختلفاً** (لكل جدول `created_at NOT NULL` و`id` uuid مفتاح أساسي وفهرس `(owner_id, created_at desc)`).

### القياس (MEASURED — محاكاة PostgREST حتمية؛ ليس شبكة مستضافة ولا Samsung)
قبل: **طلب واحد** لكل قائمة أياً كان الحجم، وبحد خادم 1000 ⇒ **1000 فقط بصمت**. بعد: 0/500 ⇒ 1 طلب، 1,200 ⇒ 3، 10,000 ⇒ 20 — لكل قائمة.
| القائمة | 500 (B) | 1,200 (B) | 10,000 (B) |
|---|---|---|---|
| Offers | 327,730 | 787,256 | 6,579,700 |
| Owners | 203,730 | 489,656 | 4,096,698 |
| Offices | 207,122 | 498,149 | 4,175,592 |
| Brokers | 149,730 | 360,056 | 3,016,698 |
| Watchmen | 202,122 | 486,149 | 4,075,592 |
| (Requests، P4.1) | 290,230 | 697,256 | 5,829,700 |
(أحجام الصفوف من بيانات اختبار ممثلة؛ الأعمدة الحقيقية قد تختلف.)

### الأدلة (شغّلها الوكيل)
- **جديد `test/lists/entity_keyset_pagination_test.dart`** — مجموعة واحدة مُعاملة تُشغَّل لكل قائمة (21 لكل منها) + قياس = **106**. **كُتب أولاً: 70 فشلاً (14 لكل قائمة) على القراءة القديمة**، ثم **106/106**. لكل قائمة: شكل الصفحة (الفلاتر، الترتيب بمفتاحين، 500، العدّ الدقيق، **الأعمدة نفسها كقراءة السجل المفرد**)؛ 0/499/500/501/1200؛ حد 1000 و300؛ تعادلات `created_at`؛ حساب آخر/محذوف مستبعد؛ لا وسائط أثناء قراءة القائمة؛ عدّ مفقود/`*`/مشوّه ⇒ `missingCount` غير شبكي؛ عطل شبكة في الصفحة 2 ⇒ خطأ شبكي قابل للإعادة؛ صف مكرر وخادم لا يتقدم ⇒ `badPage`؛ جلسة مُزاحة ⇒ `ListSessionNotCurrent`؛ دخول الحساب نفسه مجدداً **وحساب آخر** أثناء الترقيم ⇒ لا صفحة أخرى؛ إغلاق الشاشة؛ > 20,000 ⇒ `tooLarge` بعد طلب واحد؛ **كاش مشفّر حقيقي:** قراءة لاحقة بصفحة معيبة أو بلا عدّ ⇒ المحفوظ ووقته كما هما؛ علامة حذف مؤكدة ⇒ مخفية في كل صفحة، والصفحة المتأخرة التي تُدرجها لا تُحفظ، بلا حجب.
- **P4.1 سليم:** `requests_keyset_pagination_test` **37/37** (تصحيح: في §7AJ كُتب 38/38 خطأً — الملف فيه 37 اختباراً).
- **حُدِّث عمداً:** `core_entity_query_contract_test` — اختبار واحد يثبّت الآن عقد الترقيم للست (بدل «Requests مُرقّمة والخمسة بلا ترقيم»)؛ `list_row_cap_characterization_test` (P4.0) — لم تبقَ قائمة كيان بلا ترقيم، فصار يوصّف **قوائم المفضلات** (`favorite_<type>` بلا limit): 1,200 مفضّل بحد 1000 ⇒ 1000 بصمت (خطر قائم).
- **الطفرات — 6/6 التُقطت** (الملف أُعيد، hash مطابق): إعادة كل قائمة من الخمس إلى طلبها الواحد القديم ⇒ 14 فشلاً لكلٍّ؛ Offers بأعمدة أخرى (`*`) ⇒ اختبار الأعمدة. قواعد الدالة المشتركة نفسها مغطاة بطفرات P4.1 الـ 13. (أول تشغيل للأداة أبلغ «1 failing» لكلٍّ بسبب خطأ في تحليل الأسماء — كل الأسماء صارت فارغة فاختُزلت إلى واحد؛ أُعيد بعد الإصلاح: 14.)
- **الملفات الأربعة (ترقيم + عقد + توصيف):** **147/147**.
- **انحدار:** `test/lists` كاملاً + `test/home` + `test/favorites` + `test/related_items` + `test/offers` + `test/owners` + responsive للقوائم الست (r5a–r5d) ⇒ **1,533/1,536**؛ الإخفاقات الثلاثة كلها في `core_entity_refresh_stream_test`: **بديل HTTP في الاختبار** لقراءة `owners` كان (1) بلا `Content-Range` أصلاً (PostgREST الحقيقي يرسله دائماً مع `count=exact`) ⇒ `missingCount` كما صُمّم، و(2) يُرجع صفين بالوقت نفسه بترتيب الإدراج (`o1, o2`) بينما الخادم الحقيقي يرتّب `id desc` ⇒ `badPage` كما صُمّم. **حُدِّث البديل عمداً** (عدّ دقيق كما يرسله PostgREST، وأوقات مختلفة تجعل `o1, o2` ترتيب «الأحدث أولاً» الحقيقي) — بلا تغيير في توقعات دورة حياة التحديث ⇒ **3/3**. لا تغيير مصدري بعد التشغيل الكامل.
- **Analyzer** → No issues. **Format (3.5):** الجديد مطابق؛ المتتبَّعان بلا انحراف جديد. **`git diff --check`** → نظيف.

### الحدود المتبقية
- **`max_rows` المستضاف UNKNOWN**؛ إن كان < 500 فالقوائم > 40×القيمة تفشل بـ `tooLarge` (لا قطع). سلوك المؤشر و`count=exact` مع `limit` على PostgREST المستضاف **UNVERIFIED** ⇒ **P4.3**.
- **الذاكرة/الأداء:** كل قائمة كاملة في الذاكرة وفي قيمة Hive واحدة مشفرة (10k Offers ≈ 6.6 MB JSON)؛ زمن التحليل والتشفير على الجهاز **غير مقيس**؛ `count=exact` لكل قراءة على الخادم. الشاشات الست قد تُقرأ عند إشعار تعديل واحد (Q4، قائم).
- الحساب > 20,000 لقائمة ⇒ خطأ تحميل لتلك القائمة (المحفوظ يبقى).
- الاكتمال المُتحقَّق ليس لقطة لحظية (كما في §7AJ).
- **قوائم المفضلات بلا ترقيم** (مثبت بالتوصيف) — FU-FAV-META-EMPTY وFU-FAV-PAGING خارج P4؛ Search يقرأ القوائم الست (أصبح كاملاً وأثقل).
- **staging وSamsung والبناء الأصلي DEFERRED.** FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 **OPEN**؛ P3.1a staging **PENDING**.

### الحالة و NOW / NEXT / STOP
- **P4.2 = CODE_PROVEN** — ليس STAGING_VERIFIED ولا REAL_DEVICE_VERIFIED.
- **الملفات (غير مدمجة):** `lib/src/services/supabase_core_entities_service.dart`؛ جديد `test/lists/entity_keyset_pagination_test.dart`؛ `test/lists/core_entity_query_contract_test.dart`؛ `test/lists/list_row_cap_characterization_test.dart`؛ `test/lists/core_entity_refresh_stream_test.dart` (بديل HTTP)؛ وهذا الملف (§7AK + تصحيح عدد §7AJ).
- **NOW:** موافقة المالك على commit. **NEXT:** **P4.3 — تحقق staging** (PostgREST المستضاف: المؤشر والعدّ و`max_rows` الفعلي) بحساب الاختبار المعيّن، **owner-run** (الإنتاج والـ staging مشروع واحد). **STOP:** لا P4.3 تلقائياً؛ لا commit/push.
- **أُودع ودُفع** (تقرير المالك، مُتحقَّق في §7AL): `585c4dd` `feat(pagination): extend complete keyset retrieval to all entity lists`.

---

## 7AL) P4.3 — تحقق PostgREST المستضاف من الترقيم (قراءة فقط) — 2026-11-04 (PARTIAL: قبول شكل الاستعلام VERIFIED_HOSTED؛ الباقي BLOCKED)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `585c4dd` = `origin` (`git ls-remote` يطابق، 0/0)؛ المعدّل فقط ملفات plugin المولّدة الثلاثة (لم تُلمس)؛ stashes = 2 (محفوظة). قرص C: 28 GB متاحة.

**البيئة = الإنتاج** (`rbvcnvqpdqrhywcgxkne` — الإنتاج والـ staging مشروع واحد). لا كتابة، لا seeding، لا service_role، لا تسجيل دخول لأي حساب، لا تغيير إعدادات/SQL، لا تصدير بيانات.

### الوصول المستخدم وغير المستخدم
- **مستخدم:** 18 طلب `GET` بالمفتاح العام `sb_publishable_…` (موجود أصلاً في `SupabaseConfig`، لم يُطبع) **بلا جلسة** (الدور `anon`)، و`owner_id=eq.<uuid صفري>`. المطبوع: الحالة و`Content-Range` ورمز الخطأ فقط. السكربت في scratch خارج المستودع.
- **Dashboard** (المتصفح المدمج، عرض فقط): صفحة تسجيل الدخول ⇒ **توقّف** (لا إدخال بيانات اعتماد).
- **غير مستخدم عمداً:** `supabase db query --linked` (دور CLI مميّز يتجاوز RLS — ممنوع في P4.3)؛ service_role؛ تسجيل دخول حساب اختبار (كلمة مرور + كتابة جلسة + claim يزيح جلسة الهاتف إن كان الحساب A).

### لماذا يُثبت `anon` شيئاً
الأساس يسحب كل صلاحيات الجداول من `anon` (`revoke all on all tables in schema public from anon, authenticated` ثم المنح لـ `authenticated` فقط). PostgreSQL يرفض الصلاحية **بعد** تحليل الاستعلام: حلّ الأعمدة والعلاقات المضمّنة وتحويل قيم `timestamptz`/`uuid`. ⇒ رد `401 / 42501` = الاستعلام مقبول بنيوياً ونوعياً ولم يُرفض إلا للصلاحية. الضوابط السلبية أدناه تثبت هذا الترتيب **على الخادم المستضاف نفسه**.

### النتائج (OBSERVED، 2026-11-04)
| الطلب | الجداول | الرد |
|---|---|---|
| الصفحة الأولى بشكل العميل حرفياً: `select` (أعمدة `_requestColumns` مع `request_areas(area,ordinal)`، `_offerColumns` مع `offer_areas(…)`، `*` للأربعة) + `owner_id=eq.` + `deleted_at=is.null` + `order=created_at.desc.nullslast,id.desc.nullslast` + `limit=500` + `Prefer: count=exact` | الست | **401 `42501` permission denied** لكلٍّ (بلا `Content-Range`) |
| صفحة المؤشر: نفسه + `or=(created_at.lt.2026-11-03T12:34:56.123456+00:00,and(created_at.eq.…,id.lt.<uuid>))` (`+` مُرمَّز `%2B`) | الست | **401 `42501`** لكلٍّ |
| ضابط: وقت غير صالح في المؤشر | requests | 400 `22007` |
| ضابط: uuid غير صالح في المؤشر | requests | 400 `22P02` |
| ضابط: عمود غير موجود | requests | 400 `42703` |
| ضابط: علاقة مضمّنة غير موجودة | requests | 400 `PGRST200` |
| ضابط: شجرة `or` مشوّهة | requests | 400 `PGRST100` |
| ضابط: المؤشر نفسه بـ `+` **غير مُرمَّز** | requests | 400 `22007` (`+` صار مسافة: `…123456 00:00`) |

### ما صار VERIFIED_HOSTED (بهذا القدر فقط)
- للجداول الست: البوابة المستضافة وPostgREST وPostgreSQL **تقبل شكل استعلام الترقيم الحرفي** — كل أعمدة القائمة والعلاقتان المضمّنتان موجودة، الترتيب بمفتاحين مع `nullslast`، `limit=500`، `count=exact`، وشجرة `or` المركّبة بوقت ميكروثانية و`+00:00` وuuid تُحلَّل وتُحوَّل أنواعها.
- ترميز `%2B` **ضروري وصحيح** عبر البروكسي: `+` الخام يُفسَّر مسافة ⇒ **خطأ 400 صريح لا نتائج خاطئة صامتة**.
- الوصول غير الموثَّق للجداول الست = **401 رفض** (لا صفوف ولا قائمة فارغة).

### غير مُتحقَّق (لا دليل — لا يُدّعى)
| # | السيناريو | الحالة |
|---|---|---|
| 1 | `max_rows` المستضاف | ~~UNKNOWN~~ ⇒ **VERIFIED_HOSTED = 1000** (Dashboard، 2026-11-04 — §7AM «قراءة Dashboard») |
| 2 | `Content-Range`/العدّ الدقيق بصفوف حقيقية | UNVERIFIED (401 بلا `Content-Range`) |
| 3 | صفحة 500 بصفوف فعلية | UNVERIFIED |
| 4 | دلالة المؤشر (الصفوف بعده فقط) | UNVERIFIED (القبول النحوي/النوعي فقط VERIFIED) |
| 5 | ثبات الترتيب عند حد الصفحة | UNVERIFIED |
| 6 | الملكية/RLS لجلسة `authenticated` | ⇒ **PARTIAL** (B لا يرى صفوف الآخرين، §7AN)؛ عزل RLS الكامل على مستوى الصفوف **NOT VERIFIED** (B بلا صفوف) |
| 7 | بوابة Single Active Device (جلسة غير مُطالَب بها ⇒ صفر صفوف) | ⇒ مستوى الجلسة **VERIFIED** (§7AN)؛ إخفاء صفوف موجودة **NOT VERIFIED** (0 صف) |
| 8 | رد القائمة الفارغة (`*/0` المتوقع) | ⇒ **VERIFIED** (§7AN) |
| 9 | لا تكرار/لا تخطٍّ | UNVERIFIED (CODE_PROVEN فقط) |
| 10 | الكيانات الست | قبول الاستعلام فقط |
- **أحجام بيانات حسابات الاختبار:** غير مقيسة (تحتاج جلسة موثّقة أو SQL مميّز). لا دليل على حساب بـ > 500 سجل ⇒ **التحقق متعدد الصفحات بحجم 500 غير ممكن دون seeding** (ممنوع؛ والـ seeding هنا = صفوف إنتاج).

### الحدود والمخاطر القائمة (بلا تغيير)
`max_rows` UNKNOWN؛ قوائم المفضلات بلا ترقيم؛ FU-FAV-META-EMPTY OPEN؛ اكتمال Search وذاكرة القوائم الكبيرة غير مقيسة؛ P3.1a staging PENDING؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 OPEN؛ حدود استرداد العلامات وتراجع الملفات موثّقة كما هي؛ Samsung والبناء الأصلي DEFERRED.

### خطوات ينفّذها المالك (قراءة فقط)
- **(أ) `max_rows` — دقيقة واحدة:** Supabase Dashboard ← المشروع ← Integrations ← Data API ← Settings (أو Project Settings ← Data API) ← قيمة **Max rows**. اقرأها فقط، **لا Save**، وأبلغ بالرقم.
- **(ب) تحقق موثّق (قرار مالك):** سكربت قراءة فقط يكتبه الوكيل ويشغّله المالك في طرفيته، يدخل فيه كلمة المرور بنفسه (لا تُطبع)، على حساب اختبار **ليس حساب الهاتف** (A هو حساب الهاتف ⇒ claim يزيحه). الأثر الكتابي الذي يحتاج موافقة: تسجيل الدخول ينشئ جلسة Auth، وclaim يكتب `user_active_sessions`/`app_session_claims`، ثم release وsign-out في النهاية. ما يثبته: قبل claim ⇒ القوائم الست `200` و`Content-Range: */0` (بوابة SAD + رد الفارغ)؛ بعد claim ⇒ عدّ دقيق و`Content-Range` حقيقي، الملكية، و**ترقيم بحجم صفحة صغير** (مثلاً `limit=2` داخل السكربت فقط، بلا تغيير كود التطبيق) يختبر المؤشر والترتيب وعدم التكرار/التخطي على بيانات الحساب الموجودة **دون seeding**. يُطبع: أعداد وحالات ونتيجة مقارنة، لا معرّفات ولا محتوى.

### الحالة و NOW / NEXT / STOP
- **P4.3 = PARTIAL** — قبول شكل الاستعلام للست VERIFIED_HOSTED؛ القيمة والسلوك مع الصفوف **BLOCKED** (صلاحيات). P4.1/P4.2 تبقى CODE_PROVEN للسلوك.
- **الملفات (غير مدمجة):** هذا الملف فقط (§7AL + سطر الإيداع في §7AK). لا تغيير كود.
- **NOW:** المالك يقرأ `max_rows` (أ) ويقرّر (ب). **NEXT:** P4.3b — السكربت الموثّق بعد الموافقة. **STOP:** لا كتابة مستضافة، لا seeding، لا P4.4/المفضلات/الكتابة دون اتصال تلقائياً؛ لا commit/push.

---

## 7AM) P4.3b — أداة تحقق موثّق يشغّلها المالك — 2026-11-04 (PREPARED + LOCALLY VERIFIED؛ لم يُشغَّل شيء مستضاف)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `585c4dd`؛ غير مدمج: هذا الملف (§7AL)؛ ملفات plugin المولّدة الثلاثة كما هي (لم تُلمس)؛ stashes = 2 (محفوظة). **لا تسجيل دخول ولا claim ولا أي طلب مستضاف في هذه النقطة.**

### الملفات (جديدة، غير متتبَّعة؛ لا تغيير في `lib/` ولا SQL/RLS/إعدادات)
المجلد القائم للمشغّلات `cloudflare/workers/r2-profile-upload/staging-acceptance/` (Node built-ins فقط، بلا `npm install`؛ التقارير في `reports/` المستثنى من git):
- `p43_pagination_readonly_checks.mjs` — **فحوص GET فقط**. كل طلب يمر عبر `getOnly` (يرفض غير GET وغير الجداول الست، بلا إعادة). يقرأ عقد الترقيم **من مصدر التطبيق نفسه** (`_pageSize`/`_maxPages`/`_maxListRows`، `_requestColumns`/`_offerColumns`، ربط `_wholeList` للست، شكل `order`/`or`/الفلاتر) ويرفض العمل إن تغيّر؛ وURL والمفتاح العام من `supabase_config.dart`.
- `p43_pagination_hosted_check.mjs` — المنسِّق: **خطوات الجلسة (كتابة) منفصلة** عن الفحوص، كلٌّ بموافقة مكتوبة على لوحة المفاتيح؛ يعيد استخدام `app_session_claim.mjs` القائم (claim + `is_current_app_session`). أمر `plan` بلا شبكة؛ `run` **يرفض بلا طرفية تفاعلية** (لا يُشغَّل آلياً).
- `run_p43_pagination_check.ps1` — المشغّل: يسأل محلياً عن بريد حساب الاختبار ومعرّفه وكلمة مروره (مخفية، `SecureString`)؛ **لا يقرأ `BW_TEST_*`** (بيانات الحساب A) ويرفض بريد A إن طابق `BW_TEST_EMAIL`؛ القيم في بيئة العملية لتشغيل واحد ثم تُحذف؛ لا وسيطات سطر أوامر ولا كتابة على القرص.
- `p43_pagination_offline_selftest.mjs` — اختبار ذاتي بلا شبكة (fetch العام يرمي)، بخادم Auth + PostgREST وهمي يتبع SQL الـ Single Active Device (claim/is_current/release، سجل claims دائم، بوابة restrictive).

### ما تفعله الأداة عند تشغيل المالك (لم يحدث بعد)
| الخطوة | الموافقة | الأثر |
|---|---|---|
| تسجيل دخول واحد S1 | `SIGN IN` | جلسة Auth جديدة (+ تحديث وقت آخر دخول). **بلا إعادة** عند الفشل. يُرفض الاستمرار إن لم يطابق المعرّف المُدخل أو كان A ⇒ خروج `scope=local` فوراً |
| قراءة قبل claim | — | `is_current_app_session` = false، والقوائم الست `200` + `[]` + `*/0` (بوابة SAD) |
| claim لـ S1 | `CLAIM` | upsert `user_active_sessions` + صف **دائم** في `app_session_claims`؛ **يُنهي جلسات الحساب الأخرى** |
| فحوص GET (الست) | — | قراءة فقط |
| (اختياري) S2 + claim | `DISPLACE` | جلسة ثانية + صف claim دائم ثانٍ؛ S1 تُزاح |
| تنظيف (دائماً بعد أي دخول) | ضمن الموافقات | `release_current_app_session` (يحذف صف النشاط لهذه الجلسة فقط) + `logout?scope=local` لكل جلسة (لا يمسّ جلسات أخرى) |
**لا إنشاء/تعديل/حذف لبيانات التطبيق.** المطبوع والتقرير: PASS/FAIL، حالات HTTP، **أعداد**، أشكال `Content-Range` (`a-b/T`، `*/0`) فقط — لا كلمة مرور ولا توكن ولا بريد ولا معرّف حساب/سجل ولا وقت ولا محتوى (ذيل 6 أحرف لمعرّف الحساب في الخطة فقط).

### الفحوص المُعدّة (لكل قائمة من الست، بالجلسة النشطة)
الصفحة الأولى بعقد الإنتاج حرفياً (`limit=500` + `count=exact`): الحالة 200/206 (تُسجَّل أيهما)، العدّ الدقيق، تطابق `Content-Range` مع الصفوف، ≤ 500 و≤ العدّ ⇒ **`max_rows` يُرى فعلاً** إن كانت قائمة أكبر منه (صفحة أقصر من min(العدّ، 500))؛ ترتيب صارم `created_at DESC, id DESC` (الوقت بالميكروثانية لا كنص)؛ كل صف للحساب؛ لا صف محذوف (`*`)؛ **RLS:** بلا فلتر المالك العدّ نفسه، ومالك آخر عشوائي ⇒ `*/0`؛ **فارغ شرعي:** مؤشر أقدم من كل الصفوف ⇒ `[]`؛ **مشي keyset بـ `limit=2`** (افتراضي 5 صفحات، حتى 10×20 بإعداد) يطابق صفوف صفحة الإنتاج وترتيبها، بلا تكرار/تخطٍّ؛ **ترقيم إنتاجي متعدد الصفحات بـ 500 فقط إن كان العدّ > الصفحة الأولى** — وإلا «not exercised» (لا ادعاء).

### التحقق المحلي (شغّله الوكيل؛ بلا أي طلب مستضاف)
- `node --check` للملفات الثلاثة ✔؛ محلّل PowerShell للمشغّل: 0 أخطاء (لم يُشغَّل).
- **الاختبار الذاتي 32/32:** العقد الحقيقي يُقرأ من المصدر (500/40/20,000، الأعمدة بلا مسافات كما يرسلها postgrest-dart)؛ عقد مُعدَّل (بلا `id desc`، قائمة غير مربوطة، بلا `_pageSize`، مؤشر مختلف) ومفتاح `sb_secret_` ⇒ رفض؛ تحليل الوقت (0–6 كسور، `.09 < .1`، الإزاحة)؛ `Content-Range`؛ فحص الترتيب؛ نص المؤشر = نص العميل و`%2B`؛ `getOnly` GET واحد بلا إعادة ويرفض جدولاً آخر قبل الإرسال؛ الإعدادات (ناقصة، A، معرّف بأحرف كبيرة، حدود المشي)؛ **تشغيل كامل على الخادم الوهمي** بأحجام 7/0/1/3/1,201/12 مع الإزاحة ⇒ كل الفحوص PASS، دخولان وخروجان `scope=local`، الـ claim محرَّر وسجل claims = 2، كل طلبات الجداول GET، و**لا قيمة سرية/معرّفة واحدة في المخرجات أو التقرير** (كلمة المرور، البريد، المعرّفات، refresh token، `eyJ`، المفتاح، كل id وكل `created_at`)؛ رفض `SIGN IN` ⇒ **صفر طلبات**؛ رفض `CLAIM` ⇒ لا claim/release، بوابة مغلقة، خروج محلي؛ دخول مرفوض ⇒ **طلب واحد بلا إعادة**؛ حساب مختلف ⇒ لا claim ولا قراءة؛ claim فاشل ⇒ لا إعادة وخروج؛ حد خادم 300 ⇒ «observed 300» والترقيم يكتمل 1,201؛ 11 عطلاً مُحقناً كلٌّ يُكتشف (ترتيب، تجاهل المؤشر، تكرار عبر الصفحات، تخطٍّ صامت بترتيب سليم، تسرّب RLS، بلا `Content-Range`، صف لمالك آخر، فلتر مالك مُتجاهَل، بوابة مطفأة، صفوف مرئية لجلسة غير نشطة، إعادة claim لجلسة مُزاحة)؛ `run` بلا طرفية ⇒ exit 2 قبل قراءة أي اعتماد؛ `plan` بلا طلبات.
- **طفرات على الأداة نفسها — 18/19 التُقطت** (الملفان أُعيدا، SHA-256 مطابق). غير الملتقطة **مكافئة**: إزالة فحص التكرار — الترتيب الصارم يرفض أي تكرار أصلاً. (أول جولة كشفت 3 ثغرات في الاختبار الذاتي لا في الأداة ⇒ أُضيفت الأعطال الثلاثة الأخيرة؛ وطفرة بوابة ضعيفة استُبدلت بإزالة الفحص.)

### خطوات المالك (يدوية)
- **(أ) `max_rows` — قراءة فقط:** Supabase Dashboard ← المشروع `broker-wallet` ← Integrations ← Data API ← Settings (أو Project Settings ← Data API) ← **Max rows**. لا تغيّر القيمة ولا تضغط Save. أبلغ بالرقم فقط.
- **(ب) قبل التشغيل:** اختر حساب الاختبار المخصّص (مثلاً الحساب B «القابل للاستغناء» في مشغّلات staging) وتأكد أنه **غير مسجّل على أي جهاز/محاكي تريد بقاءه** (الـ claim يُخرجه). اعرف معرّفه (uuid).
- **(ج) تجربة بلا شبكة:** `node .\p43_pagination_hosted_check.mjs plan` و`node .\p43_pagination_offline_selftest.mjs` من المجلد.
- **(د) التشغيل المستضاف — فقط بعد موافقة منفصلة:** `.\run_p43_pagination_check.ps1` في طرفيتك، واكتب `SIGN IN` ثم `CLAIM` (و`DISPLACE` إن اخترت الإزاحة). ثم أرسل ملخص الأعداد/PASS-FAIL أو ملف `reports\p43_pagination_<time>.json` (لا يحوي معرّفات).

### الموافقة المطلوبة (منفصلة، بالحرف)
1. تسجيل دخول واحد (أو اثنين مع الإزاحة) بكلمة مرور حساب الاختبار المخصّص — **ليس A** — على مشروع الإنتاج.
2. claim لجلسة Single Active Device لذلك الحساب (يُنهي جلساته الأخرى؛ يترك صفاً دائماً في `app_session_claims` لكل جلسة).
3. (اختياري) الإزاحة: جلسة ثانية + claim.
4. التنظيف: release + خروج `scope=local`.

### حدود الأداة (صريحة)
- **حساب معزول يمرّن SAD بأمان** (جلستان للحساب نفسه داخل السكربت) — لكنه **لا يتحقق من سلوك الهاتف** عند الإزاحة (تسجيل الخروج في التطبيق) — ذلك فحص Samsung المؤجَّل.
- صفوف `app_session_claims` **دائمة** بالتصميم (لا حذف من العميل).
- الترقيم الإنتاجي متعدد الصفحات بـ 500 **يُثبت فقط إن كان لدى الحساب > صفحة**؛ لا seeding. مشي `limit=2` يغطي أول ≤ 10 صفوف افتراضياً (≤ 200 بالإعداد).
- `max_rows` يُرى من الأداة فقط إن كانت قائمة أكبر منه؛ وإلا يبقى من الـ Dashboard.
- مساواة العدّ بلا فلتر المالك تثبت عدم التسرّب **بقدر وجود صفوف لحسابات أخرى** (مُتوقَّع في الإنتاج، غير مُثبت دون صلاحية مميّزة).

### غير مُتحقَّق (بلا تغيير عن §7AL)
كل سيناريوهات §7AL 1–9 مستضافاً — الأداة جاهزة لها، **لم تُشغَّل**.

### المخاطر القائمة
`max_rows` = 1000 مستضافاً (أُغلق، انظر «قراءة Dashboard»)؛ قوائم المفضلات بلا ترقيم ⇒ تُقص بصمت عند 1000، وFU-FAV-META-EMPTY OPEN؛ FU-DATA-API-AUTO-EXPOSE جديد؛ اكتمال Search وذاكرة القوائم الكبيرة غير مقيسة؛ P3.1a staging PENDING؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 OPEN؛ حدود استرداد العلامات وتراجع الملفات كما هي؛ Samsung والبناء الأصلي DEFERRED.

### الحالة و NOW / NEXT / STOP
- **P4.3b = PREPARED + LOCALLY VERIFIED** — ليس HOSTED_VERIFIED.
- **الملفات (غير مدمجة):** الأربعة أعلاه + هذا الملف (§7AL + §7AM).
- **NOW:** المالك يقرأ `max_rows` ويقرّر الموافقة (1–4). **NEXT:** P4.3c — تشغيل المالك للأداة ثم تسجيل النتائج هنا. **STOP:** لا تسجيل دخول/claim من الوكيل؛ لا A؛ لا seeding؛ لا P4.4/المفضلات/Search؛ لا commit/push.

### قراءة Dashboard (قراءة فقط) — 2026-11-04
**الوصول:** جلسة Dashboard التي سجّلها المالك في المتصفح المدمج. **لا Save/Apply، لا تعديل حقل، لا SQL، لا دخول لحساب تطبيق، لا claim.** قراءة نص الصفحة وقيم حقول النموذج فقط.
**هوية المشروع:** عنوان الصفحة `broker-wallet` (المنظمة كما في Dashboard)، والمرجع في الرابط `rbvcnvqpdqrhywcgxkne` = نطاق `SUPABASE_URL` الافتراضي في `supabase_config.dart`.

| الإعداد | القيمة | الحالة |
|---|---|---|
| Data API | **INSTALLED** | VERIFIED_HOSTED |
| **Max rows** (Integrations ← Data API ← Settings، حقل `maxRows`) | **1000** | **VERIFIED_HOSTED** |
| Pool size (`dbPool`) | فارغ — «Configured automatically» | VERIFIED_HOSTED (القيمة الفعلية تتبع حجم الحوسبة؛ UNKNOWN رقماً) |
| Exposed schemas | «2 of 2 schemas exposed» (القائمة لم تُقرأ بدقة) | VERIFIED_HOSTED كعدد فقط |
| Extra search path | `public`، `extensions` (كما تظهر في الصفحة) | VERIFIED_HOSTED (عرض) |
| «Automatically expose new tables» | **ON** | VERIFIED_HOSTED — انظر الخطر أدناه |
| «0 of 40 tables exposed» / «2 of 50 functions exposed» | عرض Dashboard | معناه **غير مُتحقَّق**؛ لا يغيّر النتيجة: §7AL أثبت أن PostgREST يحلّ الجداول الست (رد `42501` لا «جدول غير موجود»)، والمنح لـ `authenticated` من الهجرات |
| Read replicas | **لا يوجد** — «All reads and writes currently go to the primary» | VERIFIED_HOSTED ⇒ لا تأخّر نسخ بين الصفحات |
| الحوسبة | Primary، ap-south-1، **Nano** (مشتركة، حتى 0.5 GB)؛ الخطة لا تسمح بتغيير الحوسبة (Pro فما فوق) | VERIFIED_HOSTED |
| حجم قاعدة البيانات | 31.3 MB (WAL 112 MB)؛ لحظة القراءة 12/60 اتصالاً، RAM 61% | VERIFIED_HOSTED (لقطة) |
| `statement_timeout` لدوري `authenticated`/`anon` | — | **UNKNOWN** (لا يظهر في Dashboard؛ قراءته تحتاج SQL — غير مسموح هنا). القيمة الافتراضية المعروفة في Supabase مستنتجة من التوثيق لا مُتحقَّقة |

**المستنتج من المصدر (ليس قيمة مستضافة):** `supabase/config.toml` المحلي `max_rows = 1000` — يطابق المستضاف الآن، لكن المستضاف أُثبت مستقلاً.

**الأثر على P4:**
- `1000 ≥ 500` ⇒ صفحة الإنتاج (500) **لا يقصّها الحد المستضاف**؛ سيناريو «حد < 500 ⇒ `tooLarge` بعد 40 صفحة» **لا ينطبق** على الإعداد الحالي؛ الحد 40×500 = 20,000 كما هو. التصميم يبقى صحيحاً إن تغيّر الإعداد لاحقاً (لا يعتمد على `max_rows`).
- الخطر الذي أثبته توصيف P4.0 صار **بقيمة مستضافة مُتحقَّقة:** أي قراءة بلا ترقيم تُقص بصمت عند **1000** — ينطبق اليوم على **قوائم المفضلات** (`favorite_<type>`) ⇒ FU-FAV-PAGING حقيقي عند > 1000 مفضّل لنوع. وأي build قديم قبل `4aefdc9` يقصّ القوائم الست عند 1000.
- في P4.3c ستُظهر الأداة `server cap ≥ 500` (لا «observed») ما لم تكن قائمة > 500 وأُرجعت أقل — وذلك سيكون تناقضاً يُحقَّق فيه.
- لا نسخ قراءة ⇒ الصفحات المتتالية تُقرأ من primary واحد.

**خطر أمني جديد للمتابعة (ليس من P4؛ لم يُغيَّر شيء):** «Automatically expose new tables» = ON ⇒ الجداول الجديدة تُمنح افتراضياً لأدوار Data API. المشروع يعتمد على `revoke` صريح + RLS في الهجرات؛ جدول جديد يُنشأ خارج هجرة تُلغي المنح قد يُكشف لـ `anon`. ⇒ **FU-DATA-API-AUTO-EXPOSE** — قرار المالك (المراجعة/التعطيل تغيير إعداد إنتاج يحتاج موافقة منفصلة وفحصاً أن الهجرات لا تعتمد عليه).

**ما زال غير مُتحقَّق:** كل سيناريوهات §7AL 2–9 (تحتاج P4.3c)؛ `statement_timeout`؛ قيمة pool الفعلية.
**NEXT (أصغر خطوة):** P4.3c — المالك يختار حساب الاختبار المخصّص (ليس A، غير مسجّل على جهاز مطلوب)، ويعطي الموافقة على الخطوات 1–4 أعلاه، ويشغّل `run_p43_pagination_check.ps1` بنفسه ويرسل الملخص.

---

## 7AN) P4.3c — نتيجة التحقق الموثّق المستضاف (شغّله المالك) — 2026-11-04 (PASSED ضمن النطاق المختبَر)

**Git عند المراجعة:** `perf/phase-1-startup-baseline` @ `585c4dd` = `origin` (`git ls-remote`)؛ غير مدمج: هذا الملف + الأدوات الأربع (§7AM)؛ ملفات plugin الثلاثة لم تُلمس؛ stashes = 2. الأدوات الأربع **مطابقة بالـ SHA-256** للحالة المُتحقَّقة بعد الطفرات (لا تعديل مؤقت).

**التشغيل:** المالك، في طرفيته، بالحساب المخصّص **B** (ليس A)، مع خطوة الإزاحة. الوكيل لم يرسل أي طلب مستضاف ولم يسجّل دخولاً. **التقرير:** `cloudflare/workers/r2-profile-upload/staging-acceptance/reports/p43_pagination_20261104T070348Z.json` (مستثنى من git؛ قرأه الوكيل محلياً فقط). **فحص التقرير:** لا uuid ولا JWT ولا بريد ولا مفتاح ولا URL ولا وقت.

### النتيجة: **92/92 PASS، 0 FAIL**
| القسم | PASS |
|---|---|
| setup (الحساب = المعرّف المُدخل، ليس A) | 1 |
| gate-unclaimed (`is_current` = false + الست `200`/`[]`/`*/0`) | 7 |
| claim (S1 + تأكيد `is_current`) | 1 |
| lists (11 نوع فحص؛ «لا صف محذوف» لجداول `*` الأربعة فقط) | 64 |
| displace (S2 الحساب نفسه، claim، S1 لم تعد current، الست مغلقة لـ S1، إعادة claim لـ S1 ⇒ `session_superseded`، أعداد S2 = S1 للست) | 16 |
| cleanup | 3 |
**أحجام بيانات B:** العدّ الدقيق **0** في القوائم الست (لا صفوف). أول صفحة لكلٍّ: HTTP **200** (لا 206)، 0 صف.
**التنظيف (مُثبت في التقرير):** release بـ S2 ⇒ HTTP 200، `released: true`؛ خروج `scope=local` لـ S2 ثم S1 ⇒ HTTP 204 لكلٍّ. ⇒ لا claim نشط متروك من التشغيل؛ يبقى صفّا `app_session_claims` الدائمان (بالتصميم).

### المُتحقَّق مستضافاً (VERIFIED_HOSTED) — بحدوده
| البند | الحالة | الدليل |
|---|---|---|
| قبول شكل استعلام الترقيم الحرفي للست (الأعمدة، العلاقتان المضمّنتان، ترتيب بمفتاحين، `limit=500`، `count=exact`، المؤشر المركّب و`%2B`) | **VERIFIED** | §7AL (anon) + طلبات موثّقة `200` هنا |
| `max_rows` = **1000**؛ لا read replicas (كل القراءات من primary) | **VERIFIED** | §7AM «قراءة Dashboard» |
| رد القائمة الفارغة الموثّقة: `200` + `[]` + `Content-Range: */0` للست | **VERIFIED** | lists |
| العدّ الدقيق لقائمة فارغة = 0 (`count=exact` يُرسَل ويُقرأ) | **VERIFIED** | lists |
| مؤشر keyset بجلسة موثّقة يُقبل ويُرجع `200 []` (مؤشر أقدم من كل الصفوف) | **VERIFIED** (فراغ فقط) | lists |
| RLS: بلا فلتر المالك يعدّ B **0** صفوف بينما جداول الإنتاج فيها صفوف لحسابات أخرى (ملاحظة مستضافة سابقة: سجلات Owner للحساب A في 2026-10-07 — لا من هذا التشغيل)؛ مالك آخر عشوائي ⇒ `*/0` | **PARTIAL** — مُثبت فقط أن B لا يرى صفوف الآخرين؛ **عزل RLS على مستوى الصفوف كاملاً NOT VERIFIED** (B بلا صفوف: لا اختبار لرؤية صفوفه هو ولا لصفوف حسابين معاً) | lists |
| Single Active Device على مستوى الجلسة: جلسة غير مُطالَب بها ليست current؛ claim يجعلها current؛ claim جلسة ثانية يُزيح الأولى؛ المُزاحة **لا تستطيع** إعادة claim (`session_superseded`)؛ release يعمل | **VERIFIED** | gate-unclaimed، claim، displace، cleanup |
| خروج `scope=local` لكل جلسة | **VERIFIED** (204) | cleanup |

### غير مُتحقَّق (لا يُدّعى)
- **الترقيم الفعلي متعدد الصفحات** وحد الصفحة 500 — **NOT VERIFIED** (العدّ 0 في الست؛ «production multi-page: not exercised»).
- **الترتيب `created_at DESC, id DESC`** على صفوف حقيقية، **دلالة المؤشر** (الصفوف بعده فقط)، **لا تكرار/لا تخطٍّ** — NOT VERIFIED (فحوص الترتيب والملكية والمشي مرّت **على 0 صف**؛ فحص المشي سجّل «not applicable»).
- **بوابة SAD على البيانات:** أن الجلسة غير المُطالَب بها/المُزاحة **تُخفي صفوفاً موجودة** — NOT VERIFIED: مع 0 صف لا يُميَّز «البوابة أخفت» من «القائمة فارغة». (مستوى الجلسة مُثبت أعلاه؛ و«أعداد S2 = S1» = 0 = 0 لا يثبت شيئاً إضافياً.)
- `Content-Range` بصيغة `a-b/T` وحالة 200/206 لصفحة قصيرة — لم تُرَ (لا صفوف).
- `statement_timeout`؛ قيمة pool الفعلية؛ سلوك الهاتف عند الإزاحة (Samsung مؤجَّل).

### الحالة
- **P4.3a** (قبول الاستعلام) VERIFIED_HOSTED؛ **P4.3b** (الأداة) PREPARED + LOCALLY VERIFIED؛ **P4.3c = PASSED ضمن النطاق المختبَر** (حساب فارغ + SAD على مستوى الجلسة).
- **P4.1 / P4.2 تبقى CODE_PROVEN** لسلوك الترقيم؛ القبول المستضاف متعدد الصفحات **PENDING**.
- **بند قبول مفتوح جديد: P4.3-ACCEPT-NONEMPTY** — تشغيل فحوص القوائم (قراءة فقط) على حساب **ببيانات حقيقية غير فارغة** (ويفضَّل > 500 في قائمة واحدة) لإثبات الترتيب والمؤشر وعدم التكرار/التخطي وبوابة SAD على صفوف موجودة، وعزل RLS على مستوى الصفوف (الحساب يرى صفوفه كلها ولا يرى صفوف غيره). **الحالة: OPEN.**

### أصغر متابعة آمنة (دون تعديل بيانات الإنتاج)
1. **(الموصى به) P4.3d — مشي keyset بصفحة صغيرة على بيانات موجودة:** الأداة نفسها بـ `BW_P43_WALK_LIMIT=2` و`BW_P43_WALK_PAGES=20` (≤ 40 صفاً لكل قائمة) على حساب **يملك صفوفاً بالفعل**. الحساب الوحيد المعروف ببيانات هو **A** (حساب الهاتف) والأداة **ترفضه عمداً** ⇒ يحتاج قراراً صريحاً من المالك: إما حساب اختبار آخر يملك بيانات حقيقية، أو السماح بـ A بعلم صريح (تعديل الأداة + claim يُخرج الهاتف ثم إعادة دخول الهاتف) — ويُفضَّل ضمن جلسة Samsung المجمّعة المؤجَّلة. المؤشر في keyset لا يتعلق بحجم الصفحة على الخادم، فمشي `limit=2` على صفوف حقيقية يثبت الترتيب والمؤشر والبوابة دون seeding.
2. **حد الـ 500 تحديداً** يحتاج قائمة > 500 صف: بلا seeding في الإنتاج لا يمكن؛ المكان الآمن الوحيد مشروع Supabase **منفصل غير إنتاجي** — قرار بنية أكبر، خارج P4.3.
3. لا شيء من ذلك يبدأ تلقائياً؛ ولا ترقيم المفضلات (FU-FAV-PAGING).

### المخاطر القائمة
قوائم المفضلات بلا ترقيم ⇒ تُقص بصمت عند 1000 (`max_rows` مُتحقَّق)؛ FU-FAV-META-EMPTY OPEN؛ **FU-DATA-API-AUTO-EXPOSE** OPEN؛ اكتمال Search وذاكرة القوائم الكبيرة غير مقيسة؛ P3.1a staging PENDING؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 OPEN؛ حدود استرداد العلامات وتراجع الملفات كما هي؛ Samsung والبناء الأصلي DEFERRED.

- **الملفات الجاهزة للمراجعة (غير مدمجة):** هذا الملف (§7AL + §7AM + §7AN + سطر §7AK)، والأدوات الأربع في `staging-acceptance/`. **ليست للإيداع:** `reports/` (مستثنى)، ملفات plugin الثلاثة.
- **NOW:** موافقة المالك على commit. **NEXT:** قرار المالك بشأن P4.3d (الحساب ذو البيانات). **STOP:** لا تسجيل دخول/claim من الوكيل؛ لا seeding؛ لا ترقيم المفضلات تلقائياً؛ لا commit/push.

---

## 7AO) P4.4 — اكتمال بيانات المفضلات والحماية من الفراغ الكاذب — 2026-11-04 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `e9aa961` = `origin` (`git ls-remote`)؛ المعدّل فقط ملفات plugin الثلاثة (لم تُلمس)؛ stashes = 2.

### المخطط (مُتحقَّق من الهجرة الأساسية)
`favorite_<type>` الست: `owner_id uuid`، `target_id uuid`، `added_at timestamptz NOT NULL DEFAULT now()`، **`PRIMARY KEY (owner_id, target_id)`** — بلا `id` وبلا `deleted_at` (الإزالة حذف فعلي). سياسة SELECT: `owner_id = auth.uid() and owns_<x>(target_id)`، وبوابة `app_session_gate` الـ restrictive نفسها (جلسة مُزاحة ⇒ `[]` صامت). فهارس: المفتاح الأساسي + `target_id`. ⇒ **مفتاح keyset: `added_at DESC, target_id DESC`** (`target_id` فريد لكل مالك ⇒ ترتيب كلي). لا تغيير مخطط.

### السبب الجذري لـ FU-FAV-META-EMPTY (مُثبت من المصدر وباختبارات حمراء)
`FavoriteService._getServerFavoritesWithMetadata` كان: (1) `catch (e) { return {}; }` ⇒ أي فشل (شبكة، خادم، نوع واحد من الست) = **«لا مفضلات»**؛ (2) لا مستخدم بعد مهلة `waitForAuthReady` ⇒ `{}`؛ (3) طلب واحد بلا `limit`/`count` لكل نوع ⇒ **قص صامت عند 1000** (`max_rows` المستضاف المُتحقَّق)؛ (4) فراغ بوابة الجلسة (جلسة مُزاحة) يُقبل كفراغ حقيقي. وFavoritesViewModel يعامل `{}` كقائمة فارغة موثوقة ⇒ يعرض «لا مفضلات» **ويستبدل الكاش بقائمة فارغة** (`cacheFavorites([])` يمسح الصندوق).

### الإصلاح (`favorites_service.dart` + 11 سطراً في `favorites_viewmodel.dart`)
- **العقد الجديد لـ `getAllFavoritesWithMetadata`:** إما خريطة **كاملة للأنواع الست** (كل قائمة كاملة وموثوقة) وإما **استثناء** — لا خريطة فارغة أو جزئية بدل فشل أبداً. الاكتمال ⇒ `CoreEntityListIncomplete` (`missingCount`/`tooLarge`/`badPage`/`changedDuringRead` — النوع نفسه من P4.1)؛ الجلسة/لا حساب ⇒ `ListSessionNotCurrent`؛ أعطال الطلب تمرّ كما هي. توقيع الدالة **لم يتغير** (بدائل الاختبارات القائمة تعمل كما هي).
- **الترقيم:** قارئ مركّز داخل `FavoriteService` (`_pagedFavorites` + `_wholeFavoriteList` + `_FavoriteCursor`) بعقد P4 نفسه حرفياً: 500 لكل صفحة؛ `order(added_at desc).order(target_id desc).limit(500)`؛ الصفحة الأولى `count(exact)`؛ المؤشر `or(added_at.lt.<نص خام>,and(added_at.eq.<نص خام>,target_id.lt.<id>))`؛ الصفحة القصيرة ليست نهاية؛ كل صف بعد سابقه بدقة ولمرة واحدة (`badPage`)؛ 40 صفحة / 20,000 ⇒ `tooLarge`؛ عدم تطابق ⇒ تأكيد الجلسة ثم عدّ HEAD (بفلتر المالك) ⇒ قبول أو **إعادة نظيفة واحدة** ثم `changedDuringRead`. الأنواع الست ما زالت **متوازية** (P3.4)، وصفحات كل نوع متتالية.
- **لماذا لم يُعَد استخدام `_pagedRows` نفسه:** خاص بـ `SupabaseCoreEntitiesService`، ومثبّت على `created_at`/`id`/`deleted_at` ومصدر الجلسة الخاص به؛ تعميمه يعني تعديل قارئ P4.1/P4.2 المُثبت بالطفرات. ⇒ أصغر تكيّف: قارئ بالعقد نفسه وأنواع الأخطاء نفسها و`ListSessionCheck` نفسه. **ازدواج منطق موثَّق (~120 سطراً) ⇒ FU-PAGING-UNIFY (اختياري، بقرار).**
- **الحساب/الجلسة:** الحساب و`session_id` (من جلسة العميل نفسه؛ hook اختبار `currentSessionId`) يُلتقطان عند البدء ويُفحصان **قبل كل طلب وبعده** ⇒ خروج، حساب آخر، أو **دخول جديد للحساب نفسه** ⇒ `ListSessionNotCurrent` بلا صفحة أخرى.
- **الفراغ الموثوق:** إن كانت أي قائمة فارغة ⇒ **تأكيد واحد** لهذه الجلسة عبر `ListSessionCheck.confirmFor` القائم (`AppSessionCoordinator.validateNow` ⇒ `is_current_app_session`) قبل قبول الخريطة؛ غير مؤكد ⇒ `ListSessionNotCurrent`؛ تعذّر التأكيد ⇒ خطأ؛ لا جلسة تطبيق ⇒ يُقبل كما هو (كقوائم P3.1b). قائمة بصفوف تثبت مرور البوابة فلا تأكيد.
- **ViewModel:** مسارات التحميل الثلاثة (`_loadFreshFavoritesImmediately`، `_loadFreshFavorites`/`refresh`، `_refreshImmediately`) كانت تلتقط الأخطاء أصلاً ⇒ **الفشل الآن يُبقي المعروض كما هو ولا يكتب الكاش**؛ الحالة الوحيدة المضافة: `_error = null` عند تطبيق جواب **كامل** (5 مواضع) كي يحل جواب مؤكد لاحق محل حالة خطأ سابقة. **الواجهة بلا تغيير:** `FavoritesView` تعرض حالة الخطأ القائمة (بلا نص تقني) فقط إن `error != null && cachedFavorites.isEmpty`، وإلا البطاقات.
- **حدّ الواجهة (مُبلَّغ، غير مُنفَّذ):** فشل نوع واحد يمنع **تحديث** الأنواع الأخرى في تلك القراءة (كل-أو-لا شيء). عرض قائمة محدَّثة جزئياً كأنها كاملة كان سيحتاج مؤشراً «غير مكتمل» جديداً في الواجهة ⇒ خارج النطاق؛ الاختيار الآمن: لا يتغير المعروض حتى قراءة كاملة.
- **بلا تغيير:** P3.4 (قراءات السجلات بدفعات 100 معرّف، وسائط Offer/Owner بحد 4 لكل نوع)، المطابقة مع التعديلات المتفائلة، الترتيب حسب `addedAt`، إزالة التكرار، تجاهل السجل المفقود/المحذوف، البطاقات، مولّد الحساب، صناديق Hive لكل حساب، التشفير/HMAC/العلامات/SAD، الواجهة.

### القياس (MEASURED — محاكاة PostgREST حتمية بحد `max_rows`=1000؛ ليس شبكة مستضافة ولا Samsung)
| المفضلات لكل نوع | قبل (HEAD `e9aa961`) | بعد |
|---|---|---|
| 0 / 10 / 500 | 1 طلب، كاملة | 1 طلب (+ `count=exact`)، كاملة |
| 501 | 1، كاملة | 2، كاملة |
| 1,200 | 1، **1000 فقط بصمت** | 3، كاملة 1,200 |
| 10,000 | 1، **1000 فقط بصمت** | 20، كاملة |
- قراءة نموذجية (الست ≤ 500): **6 طلبات كما كانت** + **طلب تأكيد جلسة واحد** (`is_current_app_session`) في الإنتاج إن كانت أي قائمة فارغة — كلفة الحماية من الفراغ الكاذب. سجلات الكيانات: بلا تغيير (P3.4؛ لا N+1 — `favorites_request_count_test` يمر).
- زمن الشبكة والذاكرة على الجهاز **غير مقيسين**.

### الأدلة (شغّلها الوكيل)
- **كُتبت أولاً (أحمر):** نسخ مؤقتة من الاختبارين الجديدين بلا hook `currentSessionId` على كود HEAD دون تغيير ⇒ **30 فشلاً في اختبار الخدمة + 6 من 7 في اختبار ViewModel** (السابع — الإغلاق أثناء القراءة — محمي أصلاً)؛ حُذفت النسخ المؤقتة.
- **جديد `test/favorites/favorites_metadata_pagination_test.dart` — 41/41:** شكل الصفحة (الفلتر، المفتاحان، 500، العدّ)؛ الست معاً (6 متوازية)؛ المؤشر بالنص الخام و`%2B`؛ 0/1/499/500/501/1000/1200 (1/1/1/1/2/2/3 طلبات، كل مفضّل مرة وبالترتيب)؛ 1,200 بحد 1000؛ حد 300 < الصفحة؛ تعادلات `added_at` عبر حدود الصفحات؛ الأنواع الست بأحجام مختلفة + صفوف حساب آخر مستبعدة وفلتر المالك في كل طلب؛ الوقت بالميكروثانية؛ القياس؛ نوع واحد فاشل ⇒ القراءة كلها تفشل؛ خطأ خادم/شبكة في الصفحة 2؛ `Content-Range` مفقود/`*`/مشوّه ⇒ `missingCount`؛ لا مستخدم ⇒ فشل بلا طلبات؛ فراغ تحت جلسة غير مؤكدة ⇒ `ListSessionNotCurrent` (سؤال واحد)؛ فراغ مؤكد ⇒ قبول؛ لا جلسة تطبيق ⇒ قبول؛ تعذّر التأكيد ⇒ فشل؛ لا فراغ ⇒ لا تأكيد؛ جلسة مُزاحة بعد الصفحة 1 ⇒ `ListSessionNotCurrent` **فوراً بلا عدّ ولا إعادة**؛ خروج / حساب آخر / دخول جديد للحساب نفسه بعد الصفحة 1 ⇒ لا صفحة 2؛ جلسة جديدة مع قوائم فارغة ⇒ رفض؛ > 20,000 ⇒ `tooLarge` بعد طلب واحد؛ 20,000 ⇒ 40 صفحة؛ حد 100 و4,500 ⇒ `tooLarge` بعد 40؛ تكرار/تجاهل المؤشر ⇒ `badPage`؛ حذف لم يُقرأ بعد ⇒ عدّ HEAD (بفلتر المالك) ⇒ 1,199؛ إضافة+حذف ⇒ إعادة نظيفة ⇒ 1,200؛ تغيّر دائم ⇒ `changedDuringRead`.
- **جديد `test/favorites/favorites_false_empty_test.dart` — 7/7** (قراءة البيانات الحقيقية لـ `FavoriteService`، الكاش وحده بديل): أول زيارة ونوع فاشل ⇒ **حالة الخطأ لا «لا مفضلات»، ولا حفظ** (كان: `error` = null وكتابة `[]`)؛ بطاقات معروضة + تحديث فاشل ⇒ البطاقات باقية والكاش لم يُستبدل (كان: `[[]]`)؛ فراغ تحت جلسة غير مؤكدة ⇒ البطاقات باقية؛ فشل الصفحة 2 ⇒ البطاقات باقية؛ فشل ثم تحديث مؤكد فارغ ⇒ `error` يُمسح و«لا مفضلات» ويُحفظ؛ 600 مفضّل ⇒ كل البطاقات بالترتيب وصفحتان؛ إغلاق أثناء القراءة ⇒ لا عرض ولا حفظ.
- **حُدِّث عمداً:** `favorites_metadata_requests_test` (P3.4) — بديله أصبح وفياً لـ PostgREST (`Content-Range` بالعدّ)، والعقد الجديد للاستعلام، و«نوع فاشل ⇒ القراءة تفشل» صار **خطأً لا `{}`**؛ `list_row_cap_characterization_test` (P4.0) — لم تبقَ قراءة قائمة بلا ترقيم: 1,200 مفضّل بحد 1000 ⇒ **كلها، 3 طلبات** (كان: 1000 بصمت).
- **الطفرات على الكود الإنتاجي — 15/15 التُقطت** (الملفان أُعيدا، SHA-256 مطابق): بلا `target_id`؛ الصفحة القصيرة نهاية؛ قبول بلا مطابقة؛ بلا فحص الحساب؛ بلا فحص الجلسة؛ بلا 20,000؛ بلا 40 صفحة؛ بلا فحص الترتيب/التكرار؛ بلا الإعادة النظيفة؛ مؤشر بوقت مُعاد تنسيقه؛ عدّ مفقود غير مُصنَّف؛ فراغ بلا تأكيد؛ عدم تطابق بلا تأكيد الجلسة؛ **إعادة الخطأ القديم (`{}` عند الفشل)**؛ ViewModel لا يمسح الخطأ. (الجولة الأولى 14/15: «عدم تطابق بلا تأكيد» نجا لأن فحص الفراغ النهائي يلتقطه لاحقاً — دفاع بعمق — فأُضيف تأكيد صريح «فوراً بلا عدّ ولا إعادة» وجُعل عدّ البديل يحترم البوابة كالخادم ⇒ التُقطت.)
- **انحدار:** `test/favorites` كاملاً (يشمل P3.4: دفعات السجلات وحد الوسائط، عزل الحسابات، جلسة الحساب نفسه، الواجهة، المطابقة المتفائلة) + `test/lists` كاملاً + `r2_search_favorites_responsive_test` + `auth/single_active_session_source_test` ⇒ **675/675**؛ بعد التنسيق وإصلاح تحذير lint: الملفات الأربعة المعنية ⇒ 51/51 ثم 41/41.
- **Analyzer** (الملفات الستة) → No issues. **Format (3.5):** الاختباران الجديدان واختبار التوصيف (مُعاد كتابته) نُسّقت؛ `favorites_service.dart` و`favorites_metadata_requests_test.dart` مطابقان؛ `favorites_viewmodel.dart` فيه انحرافات **سابقة** (30 سطراً في HEAD = 30 الآن) ⇒ لم يُنسَّق. **`git diff --check`** → نظيف.

### الحدود المتبقية
- **غير مُتحقَّق مستضافاً:** ترقيم المفضلات على PostgREST الحقيقي — يُضاف إلى **P4.3-ACCEPT-NONEMPTY (OPEN)** (الحساب B بلا مفضلات؛ الأداة لم تُوسَّع للمفضلات).
- كل-أو-لا شيء: نوع فاشل يؤخر تحديث الأنواع الأخرى حتى قراءة كاملة (حدّ الواجهة أعلاه).
- طلب تأكيد جلسة إضافي لكل قراءة فيها قائمة فارغة (كلفة مقصودة).
- ~~بعد إغلاق الشاشة تُكمل القراءة الجارية صفحاتها (≤ 40) وتُهمل نتيجتها~~ ⇒ **أُصلح في المراجعة المركّزة أدناه** (الطلب الجاري وحده يكتمل).
- `getAllFavorites()`/`favoritesStream` (غير مستخدمتين في `lib/`) تمرّران الخطأ الآن بدل `{}`.
- قوائم المفضلات كاملة في الذاكرة؛ أداء 20,000 على الجهاز غير مقيس. ازدواج منطق الترقيم ⇒ FU-PAGING-UNIFY.
- **مفتوح بلا تغيير:** اكتمال Search وذاكرة القوائم الكبيرة PENDING؛ FU-DATA-API-AUTO-EXPOSE؛ P3.1a staging PENDING؛ FU-AUTH-BASELINE-7 وDelete Account التاريخي وFU-ACCOUNT-UI-BASELINE-1 OPEN؛ حدود استرداد العلامات وتراجع الملفات كما هي؛ **Samsung والبناء الأصلي DEFERRED**.

### الحالة و NOW / NEXT / STOP
- **P4.4 = CODE_PROVEN** — ليس HOSTED_VERIFIED ولا REAL_DEVICE_VERIFIED. **FU-FAV-META-EMPTY: مُصلَح (CODE_PROVEN)**؛ **FU-FAV-PAGING: مُنفَّذ (CODE_PROVEN)**.
- **الملفات (غير مدمجة):** `lib/src/views/Screens/home/favorites/favorites_service.dart`؛ `lib/src/views/Screens/home/favorites/favorites_viewmodel.dart`؛ جديد `test/favorites/favorites_metadata_pagination_test.dart`؛ جديد `test/favorites/favorites_false_empty_test.dart`؛ `test/favorites/favorites_metadata_requests_test.dart`؛ `test/lists/list_row_cap_characterization_test.dart`؛ وهذا الملف.
- **NOW:** موافقة المالك على commit. **NEXT (اقتراح):** توسيع P4.3-ACCEPT-NONEMPTY ليشمل المفضلات عند توفر حساب ببيانات؛ أو Search بقرار منفصل. **STOP:** لا Search تلقائياً؛ لا commit/push.

### مراجعة مركّزة قبل الإيداع: طلبات صفحات بعد الإغلاق/الخروج — 2026-11-04
**HEAD:** `e9aa961` (بلا تغيير)؛ stashes = 2؛ ملفات plugin الثلاثة لم تُلمس.
- **ما فُحص:** حلقة `_pagedFavorites` (`stillOurs()` قبل كل طلب وبعده) ودورة حياة `FavoritesViewModel`. في الإنتاج تنشئ كل شاشة Favorites **`FavoriteService()` خاصة بها** (`favorites_view.dart` ← `FavoritesViewModel()` بلا حقن) ⇒ إشارة إيقاف على النسخة لا تمسّ قارئاً آخر.
- **الخروج / حساب آخر / دخول جديد للحساب نفسه:** **لا طلبات زائدة** — `stillOurs()` يوقف القراءة قبل الصفحة التالية (مثبت سابقاً: «لا صفحة 2»). **إزاحة الجلسة من جهاز آخر:** الجلسة المحلية لا تتغير، والبوابة تُرجع الصفحة التالية فارغة ⇒ تنتهي الحلقة بعد طلب واحد على الأكثر ثم الرفض الفوري (مثبت: «بلا عدّ ولا إعادة»).
- **إغلاق الشاشة: المشكلة مؤكدة.** الخدمة لم تكن تعلم بالإغلاق ⇒ قراءة 1,200 مفضّل استمرت **3 صفحات** بعد إغلاق الشاشة أثناء الصفحة 1 (10,000 ⇒ حتى 20)، **وطلب تأكيد الجلسة أيضاً**؛ النتيجة تُهمل (مولّد الحساب/`_disposed`). **مُثبت باختبار أحمر:** المتوقع 1، الفعلي **3**.
- **الإصلاح (أصغر تغيير، بلا تغيير توقيع ولا API عامة للاختبارات):** `FavoriteService.cancelMetadataReads()` يرفع عدّاد epoch؛ كل قراءة تلتقط epoch عند البدء و`stillOurs()` يفحصه **أولاً** ⇒ بعد الإلغاء لا صفحة ولا عدّ HEAD ولا تأكيد جلسة (أُضيف `stillOurs()` قبل `ListSessionCheck.confirmFor` في الموضعين)؛ الطلب المُرسَل يكتمل وجوابه لا يُستخدم، والقراءة تفشل بخطأ خاص (`_MetadataReadNotWanted`) لا يراه أحد. القراءات اللاحقة على النسخة نفسها **غير متأثرة**. `FavoritesViewModel.dispose()` يستدعيه (سطر واحد). لا إعادات ولا polling ولا حزم.
- **محفوظ:** كل حراس الحساب/الجلسة، كل-أو-لا شيء، تمرير الأخطاء، الحماية من الفراغ الكاذب، دفعات P3.4 وحد الوسائط، الكاش (لا كتابة من قراءة فاشلة — مثبت: `cacheWrites` فارغ في اختبارات الفشل الأربعة وفي اختبار الإغلاق).
- **الأدلة (شغّلها الوكيل):** جديد في `favorites_false_empty_test` — «أُغلقت أثناء الصفحة 1 ⇒ لا صفحة أخرى ولا تأكيد جلسة ولا حفظ، والقراءة اللاحقة كاملة» (أحمر قبل الإصلاح: 3 صفحات)؛ جديد في `favorites_metadata_pagination_test` — «إلغاء أثناء الصفحة 1 ⇒ الطلب يكتمل، لا صفحة 2، لا تأكيد، فشل؛ قراءة لاحقة كاملة». **الاختبارات المتأثرة فقط:** ملفا P4.4 + `favorites_metadata_requests` + `favorites_viewmodel_initial_load` + `favorites_list_reconciliation` + `favorites_same_account_session` + `favorites_request_count` (P3.4) + `favorites_screen_ui` + `r2_search_favorites_responsive` + `list_row_cap_characterization` ⇒ **122/122**. **طفرتان مستهدفتان 2/2 التُقطتا** (إزالة فحص epoch؛ إزالة الاستدعاء من `dispose`)، الملفان أُعيدا بـ SHA-256 مطابق. لم يُكرَّر انحدار الـ 675 (التغيير محصور في مسار الإلغاء). **Analyzer** (4 ملفات) → No issues. **Format:** الملفات الجديدة/الخدمة مطابقة؛ `favorites_viewmodel.dart` بلا انحراف جديد (30 = 30). **`git diff --check`** → نظيف.
- **P4.3-ACCEPT-NONEMPTY:** OPEN (بلا تغيير).

---

## 7AP) تدقيق تغطية Offline-First والوسائط وأداء الشاشات السبع — 2026-11-04 (AUDIT؛ لا تغيير كود)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `21c43a9` (= P4.4، `feat(favorites): paginate metadata…`) = `origin` (لا شيء جديد عند `fetch --dry-run`)؛ المعدّل فقط ملفات plugin الثلاثة (لم تُلمس)؛ stashes = 2 (لم تُلمس). ⇒ **P4.4 مدمج ومدفوع** (كان §7AO يقول «غير مدمج» وقت كتابته).

**طبيعة الدليل:** قراءة المصدر الحي فقط (`SOURCE-READ`) — لم يُشغَّل اختبار ولا Flutter ولا جهاز ولا طلب مستضاف. لا شيء هنا `CODE_PROVEN` جديد؛ كل زمن = **NOT MEASURED**.

### 1) الحالات الخمس للوسائط كما في الكود
| الحالة | أين | النطاق/الحدود |
|---|---|---|
| بيانات السجل | الست: `offline_lists` المشفّرة (P2/D-3). المفضلات: صندوق Hive `cached_favorites_<uid>` **غير مشفّر**. Quotations/Map/Search: **لا نسخة محلية** | — |
| صورة (Offer/Owner/Profile) | `DefaultCacheManager` (`flutter_cache_manager`) بمفتاح ثابت `offer-media:<owner>:<mediaId>` (Profile: `mediaId` وحده) + ربط المفتاح بالملف في صندوق `url_mapping` | الإعداد الافتراضي: **30 يوماً / 200 ملف** لكل التطبيق، في مجلد cache (يمسحه النظام، خارج النسخ الاحتياطي). لا مصغّرات منفصلة: «الصورة المصغّرة» = الصورة الكاملة نفسها |
| أصل رفعه هذا الجهاز | `app_flutter/offer_media` | مستثنى من النسخ (D-1a)؛ يُكنس عند حذف الحساب |
| ملصق الفيديو | `offerMediaPosterKey` = `<cacheKey>:poster`؛ يُولَّد عند الطلب من الرابط الموقّع (`OfferVideoPosterService`، يقرأ نطاقات بايت فقط) ويُحفظ تحت المفتاح نفسه | تحت مجلد temp؛ إعادة المحاولة بعد دقيقتين |
| الفيديو الكامل | `VideoPlayerController.networkUrl` برابط موقّع؛ `getVideoFile` يعيد ملفاً محلياً **فقط** لأصل رفعه هذا الجهاز | **لا تنزيل للفيديو، لا تشغيل offline** لفيديو لم يرفعه هذا الجهاز (مطابق للسياسة: لا تنزيل تلقائي) |
| ملف Plan | `getTemporaryDirectory()/plan_attachments/<parent>_<id>_<mediaId>.<ext>` بعد فحص النوع | يُفتح offline إن نُزِّل سابقاً؛ **لا يكنسه حذف الحساب** (مجلد temp) |
| PDF عرض السعر | `app_flutter/quotation_<id>_<mediaId>.pdf` | يُحذف مع حذف العرض؛ **غير مستثنى من النسخ ولا يكنسه حذف الحساب** |

### 2) مصفوفة الحالة
| الشاشة | المُنفَّذ (SOURCE-READ) | يعمل offline الآن | يحتاج شبكة | كلفة/خطر | اختبار ناقص | أصغر تحسين آمن |
|---|---|---|---|---|---|---|
| **Requests/Offers/Owners/Offices/Brokers/Watchmen (قائمة)** | `EntityListState` + `watchUser*LocalFirst()`؛ الكاش أولاً ثم ترقيم P4؛ مؤقت debug `[EntityList] first list after N ms` | نعم، بالكاش المشفّر داخل جلسة معتمدة | التحديث | **البطاقات بلا وسائط بعيدة** (Offers/Owners: أيقونات فقط) ⇒ لا كلفة صور. كل `notifyListeners` يعيد فلترة + فرز + تجميع أسبوعي للقائمة كلها داخل `build` (O(n log n))؛ القوائم lazy لكل مجموعة أسبوع. ثمن فك التشفير/HMAC لـ 20,000 غير مقيس | زمن الفتح بالكاش، 5k/20k صف | قياس (NOT MEASURED) أولاً؛ ثم memoize الفرز/التجميع عند تغيّر القائمة فقط |
| **Quotations (قائمة)** | `watchQuotations()` قراءة خادم واحدة لكل فتح وبعد **أي** تعديل كيان | **لا** — خطأ/فراغ | كل شيء | **طلب واحد بلا ترقيم ⇒ قص صامت عند 1000** (`max_rows` مُتحقَّق)؛ `StreamBuilder` يفحص `hasError` قبل البيانات ⇒ **فشل تحديث لاحق يستبدل القائمة المعروضة بشاشة خطأ**؛ البطاقات تُبنى كلها دفعة (`Column` داخل `SliverToBoxAdapter`) | 1001+ صف؛ فشل بعد بيانات | ترقيم keyset بعقد P4؛ إبقاء القائمة عند فشل لاحق |
| **Home** | أعداد معزولة لكل حساب (R-02/P3.1c–P3.3) | الأعداد المحفوظة | التحديث | — | — | بلا تغيير |
| **Profile avatar** | `CurrentUserAvatar`: ملف محلي ⇒ `Image.file`؛ وإلا `buildOfflineAwareImage(cacheKey: mediaId)`؛ اللقطة `cached_profile_snapshot_v1` تحفظ `profileMediaId` **دون** الرابط الموقّع | نعم إن بقي الملف/الكاش؛ انتهاء الرابط لا يهم | أول تنزيل | الملف في cache (قد يُمسح ⇒ placeholder)؛ مفتاح Profile غير مقرون بالحساب (معرّف UUID فريد — خطر منخفض) | إعادة تشغيل offline، تبديل حساب | جهاز فقط (P5) |
| **Offer Details** | `OfferDetailsLoadCoordinator`: وسائط محلية متزامنة من الكتالوج (`offerMediaCatalog::<owner>::<offer>`) ثم صف موثوق + روابط موقّعة **بالتوازي**؛ جيل يرفض النتائج المتأخرة | النص من نموذج القائمة + الصور المحفوظة | صف موثوق، وسائط جديدة، الفيديو الكامل، ملصق لم يُولَّد | `getSingleFile` بمهلة 5 ث (قد لا تُحفظ صورة كبيرة على شبكة بطيئة) | offline بلا كتالوج | — |
| **Owner Details** | `PrivateMediaStore` نفسه (`OwnerService`)؛ المسار `/owners-details` يتطلب `extra` | كالعرض | كالعرض | `state.extra as OwnerModel` بلا بديل by-id | — | — |
| **Plan files** | `PlanAttachmentFiles.ensureLocal` (فحص نوع، حد حجم) | إن نُزِّل سابقاً | أول فتح | انظر §1 (حذف الحساب) | حذف الحساب يكنسها | إضافة الكنس (قرار) |
| **Favorites** | P3.4 + P4.4؛ البطاقة ترسم وسائط بالهوية فقط (`toStored` = مفتاح + isVideo، بلا رابط) | البطاقات من الصندوق | التحديث، الصور غير المحفوظة | **(أ)** الصندوق **غير مشفّر وغير مستثنى من النسخ** (عنوان/وصف الكيان) — يخالف معيار القوائم الست. **(ب)** بطاقة من الكاش لها `originalData: null`؛ النقر يدفع `/owners-details` (وRequests/Offices/Brokers/Watchmen) بـ `extra: null` ⇒ `state.extra as OwnerModel` **يرمي** — **أُعيد إنتاجه ثم أُصلح (CODE_PROVEN، انظر «متابعة FU-FAV-OFFLINE-NAV» أدناه)** (Offers آمن: by-id) | النقر على بطاقة من الكاش offline | (ب) أولاً: ربط البطاقة بالسجل من الكاش المشفّر أو تعطيل/رسالة؛ (أ) قرار أمني منفصل |
| **Search** | محرّك محلي في الذاكرة؛ أول بحث = **6 قراءات خادم كاملة** (ترقيم P4) ثم فهرسة؛ صالح 5 د أو حتى تعديل؛ وسائط البطاقات: المحفوظ أولاً ثم حلّ بحد 3 متوازية | **لا** للبحث الأول بعد الفتح؛ يستمر بالذاكرة إن حُمّل | كل أول تحميل | حتى 6 × 20,000 صف في الذاكرة + نسخة القوائم نفسها مرة ثانية؛ لا يستخدم الكاش المشفّر | offline، أحجام كبيرة | **P4.5a** (أدناه) |
| **Smart Map** | `MapPlacesLoader`: كاش **ذاكرة** 5 د لكل مستخدم، وإلا 4 قراءات كاملة (Offers/Owners/Offices/Watchmen) | فقط ضمن 5 د في العملية نفسها | بعد إعادة التشغيل/انتهاء المدة؛ **بلاطات Google دائماً** (لا offline مضمون) | قراءات مكررة لما في الكاش المشفّر | offline بعد إعادة تشغيل | لاحقاً: العلامات من الكاش المشفّر |
| **Toolkit** (Scanner/Combine/Images-to-PDF/Signature) | مكتبات محلية لكل حساب في `app_flutter/<tool>` (مستثناة من النسخ)؛ مكتبة سحابية metadata-first (`ToolkitRemoteCache`: بيانات فقط، لا ملف ولا رابط)؛ تنزيل عند الفتح | الملفات المحلية تُفتح وتُعدّل؛ بطاقات السحابة تظهر من البيانات | فتح مستند سحابي غير منزّل | — | قبول offline لكل أداة على الجهاز | قبول جهاز فقط (P5) |
| **UAE Links** | كتالوج ثابت؛ الروابط خارجية | الكتالوج | فتح الروابط | — | — | — |

### 3) فجوات أمن/خصوصية (للقرار، لا تنفيذ)
- **FU-FAV-CACHE-PLAIN:** `cached_favorites_<uid>` غير مشفّر وغير مستثنى من النسخ.
- **FU-MEDIA-MAP-BACKUP:** `url_mapping`/`local_media` (Hive، غير مشفّر) تُنسخ احتياطياً: معرّفات حسابات + معرّفات وسائط + مسارات (لا روابط ولا بايتات).
- **FU-PLAN-QUOTE-CLEANUP:** نسخ Plan (temp) وPDF العروض (`app_flutter` الجذر) لا يكنسها حذف الحساب؛ PDF العروض غير مستثنى من النسخ.
- **FU-IMAGE-CACHE-POLICY:** الإعداد الافتراضي 200 ملف/30 يوماً مشترك بين Profile وOffer وOwner وFavorites وSearch وMap — لا حصة لكل حساب ولا LRU مقصود.

### 4) خارطة الطريق (مرحلة واحدة في كل مرة؛ موافقة المالك بين المراحل)
1. **P4.5a — Search من الكاش المشفّر أولاً:** فهرسة القوائم الست من `*LocalCache` للحساب الحالي فوراً (بحث offline لما هو محفوظ)، ثم استبدالها بالقراءة الكاملة عند الاتصال؛ نفس `SearchEngine` وواجهة بلا تغيير؛ لا تبعيات. يُتحقق أولاً أن الكاش يحمل كل حقول البحث.
2. **FU-FAV-OFFLINE-NAV** (صغير، تعطل محتمل): اختبار أحمر للنقر على بطاقة من الكاش ثم إصلاح أدنى. *قد يتقدّم على 1 بقرار المالك.*
3. **P4.6 — Quotations:** ترقيم keyset (يغلق القص عند 1000) + إبقاء القائمة عند فشل لاحق؛ لا تغيير حسابات.
4. **P4.7 — فتح القوائم السبع:** قياس جهاز (المؤقت موجود في debug؛ Profile build لاحقاً) ثم memoize الفرز/التجميع.
5. **M1 — سياسة كاش الصور** (حصة/LRU/نطاق الحساب) قبل أي تخزين مسبق؛ **M2** Offers/Owners details offline؛ **M3** اتساق وسائط Favorites/Search؛ **M4** الفيديو الكامل offline بسياسة تنزيل صريحة فقط.
6. **Map offline** من الكاش المشفّر (البلاطات خارج الضمان) — **Toolkit** قبول جهاز لكل أداة — **P4.3-ACCEPT-NONEMPTY** — **P5** جهاز مجمّع — **O0–O7** كتابة offline.

### الحالة و NOW / NEXT / STOP
- **AUDIT مكتمل** (SOURCE-READ). P4.4 مدمج @ `21c43a9`. **P4.3-ACCEPT-NONEMPTY: OPEN.** لا شيء أعلاه REAL_DEVICE_VERIFIED.
- **NOW:** قرار المالك: P4.5a أولاً أم FU-FAV-OFFLINE-NAV. **NEXT:** المرحلة المختارة وحدها. **STOP:** لا تنفيذ تلقائي؛ لا تغيير تشفير/تنسيق كاش/HMAC/علامات؛ لا تنزيل وسائط تلقائي؛ لا قرارات FU الأمنية دون المالك؛ لا commit/push؛ Samsung والبناء الأصلي DEFERRED.
- **(قرار المالك لاحقاً: FU-FAV-OFFLINE-NAV أولاً — نُفِّذ أدناه.)**

### متابعة FU-FAV-OFFLINE-NAV — النقر على مفضّل من النسخة المحفوظة — 2026-11-04 (CODE_PROVEN؛ غير مدمج)
**Git عند البدء:** `21c43a9` = `origin`؛ §7AP غير مدمج؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس.

**أُعيد إنتاجه (لم يعد استنتاجاً):** اختبار مؤقت على الكود دون تغيير — بطاقة من `CachedFavoriteItem.toFavoriteItem()` ومسارات تحاكي `app.dart` حرفياً ⇒ النقر **رمى في الأنواع الخمسة كلها**: `type 'Null' is not a subtype of type 'RequestModel' / 'OwnerModel' / 'OfficeModel' / 'BrokerModel' / 'WatchmenModel' in type cast`. حُذف الاختبار المؤقت بعد التشغيل الأحمر.

**السبب الجذري:** `CachedFavoriteItem.toFavoriteItem()` يضع `originalData: null` دائماً (الصندوق لا يحفظ السجل)، ويبقى كذلك offline أو قبل اكتمال القراءة الطازجة؛ `_navigateToDetails` كان يدفع `/requested-details` و`/owners-details` و`/offices-details` و`/brokers-details` و`/watchmen-details` بـ `extra: widget.favorite.originalData`، وهذه المسارات في `app.dart` تفعل `state.extra as XModel` بلا بديل by-id.

**الإصلاح (أصغر تغيير؛ لا تغيير في `app.dart` ولا الكاش ولا الخادم):**
- جديد `lib/src/services/favorite_saved_records.dart` — `FavoriteSavedRecords.find(type, id)`: يقرأ القائمة المشفّرة **للحساب الحالي فقط** عبر `*LocalCache.read(uid)` القائم (يتحقق من HMAC، يُبقي سجلات الحساب وحده، يُخفي علامات الحذف المؤكد، ويرفض الصندوق المحجوب) ويعيد السجل ذا المعرّف نفسه؛ حساب أو جلسة مختلفة عند انتهاء القراءة ⇒ لا شيء؛ لا مستخدم/معرّف فارغ/نوع آخر/Offers ⇒ لا شيء؛ لا يرمي أبداً. هو **السجل نفسه الذي تفتح به شاشة القائمة التفاصيل offline** — لا سجل مُختلَق.
- `favorites_card.dart`: Offers **بلا تغيير** (by-id بما لدى البطاقة)؛ للأنواع الخمسة: سجل مرفق من النوع الصحيح ⇒ الدفع نفسه كما كان (online بلا تغيير)؛ وإلا ⇒ بحث في النسخة المحفوظة (طلب واحد في كل مرة؛ لا شيء إن أُغلقت البطاقة) ⇒ فتح التفاصيل بالسجل المحفوظ، وإلا **لا تنقّل** وSnackBar بالنص القائم `errorLoadingData` («Error loading data» / «خطأ في تحميل البيانات») — لا نص جديد. لم يعد أي دفع لهذه المسارات بسجل مفقود أو من نوع آخر.
- **بلا تغيير:** P3.4 (الدفعات وحد الوسائط)، P4.4 (الترقيم، الحماية من الفراغ الكاذب، الإلغاء عند الإغلاق)، ترتيب `addedAt`، صناديق Hive وصيغتها، التشفير/HMAC/العلامات/SAD، الوسائط والروابط الموقّعة والفيديو.

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- جديد `test/favorites/favorites_offline_navigation_test.dart` — **38/38**: لكل نوع من الخمسة: من الكاش + سجل محفوظ ⇒ التفاصيل بالسجل نفسه (`same`)؛ من الكاش بلا سجل محفوظ ⇒ لا استثناء، لا تنقّل، الرسالة؛ online بسجله ⇒ الدفع نفسه بلا بحث. البحث الحقيقي بلا مستخدم ⇒ يفشل مغلقاً؛ نقرتان أثناء البحث ⇒ بحث واحد؛ بطاقة أُزيلت أثناء البحث ⇒ لا شيء؛ Offers ⇒ `/offers-details-by-id/<id>` بـ `extra` كما كان وبلا بحث. **مع الكاش المشفّر الحقيقي (Hive مؤقت):** لكل نوع: السجل المحفوظ بحقوله، غير الموجود ⇒ null؛ الحساب B لا يرى سجلات A والعكس؛ خروج (null/فارغ) ⇒ لا شيء؛ تغيّر الحساب أثناء القراءة ⇒ لا شيء؛ **جلسة جديدة للحساب نفسه** أثناء القراءة ⇒ لا شيء؛ سجل بعلامة حذف مؤكد ⇒ لا شيء؛ **بعد «إعادة تشغيل»** (إغلاق الصناديق + `debugForgetProcessState`) ⇒ ما زال يُوجد؛ لا قائمة/Offers/نوع مجهول/معرّف فارغ ⇒ لا شيء؛ هوية ترمي ⇒ لا شيء. فحصا مصدر: `app.dart` ما زال يفرض السجل في المسارات الخمسة (المحاكاة مطابقة)، والبطاقة لا تدفعها بـ `originalData` خام.
- **الطفرات 3/3 التُقطت** (الملفان أُعيدا، SHA-256 مطابق): بلا إعادة فحص الحساب/الجلسة بعد القراءة؛ بلا حارس البحث الجاري؛ بلا فحص `mounted`.
- **انحدار مركّز:** `test/favorites` كاملاً + `r2_search_favorites_responsive_test` ⇒ **194/194**.
- **Analyzer** (الملفات الثلاثة) ⇒ No issues. **Format (3.5):** الملفان الجديدان نُسّقا ومطابقان؛ `favorites_card.dart` بلا انحراف جديد (6 سابقة = 6). **`git diff --check`** ⇒ نظيف. CRLF في الملفات الثلاثة.

**حدود باقية (offline-detail):**
- السجل المحفوظ = حقول القائمة فقط (لا وسائط)؛ شاشات التفاصيل تجلب الوسائط بنفسها كما من شاشة القائمة.
- مفضّل لم يُحفظ سجله (لم تُفتح شاشة قائمته لهذا الحساب، أو حُذف، أو قائمة محجوبة) ⇒ رسالة ولا تفاصيل offline. **Online قبل اكتمال القراءة الطازجة** ⇒ قد تظهر الرسالة لحظياً لو كان السجل غير محفوظ؛ النقر بعد التحديث يعمل. لا جلب by-id جديد (خارج النطاق).
- المسارات الخمسة في `app.dart` ما زالت تفرض `state.extra` لكل المستدعين الآخرين (25 موضع دفع؛ لم يُراجع كلها) ⇒ **FU-DETAILS-ROUTE-EXTRA** (اختياري).
- غير مقيس على الجهاز؛ Samsung DEFERRED.

### مراجعة خصوصية `cached_favorites_<uid>` (مراجعة فقط؛ لا تغيير)
- **الحقول (`CachedFavoriteItem`، Hive typeId قائم):** `id`، `type`، `title`، `subtitle`، `imageUrl`، `thumbnailUrl` (= `imageUrl`)، `addedAt`، `cachedAt`، `entityData` (= هوية وسائط البطاقة فقط `{k: offer-media:<uid>:<mediaId>, v: isVideo}`).
- **ما يدخل title/subtitle فعلاً:** Owners ⇒ **اسم المالك** + أنواع العقارات؛ Offices ⇒ اسم المكتب + **اسم المدير**؛ Brokers ⇒ **اسم الوسيط**؛ Watchmen ⇒ **اسم الحارس** + اسم المبنى؛ Offers/Requests ⇒ نوع العقار + المدينة + نطاق السعر. **⇒ بيانات شخصية لعملاء (أسماء)**. لا أرقام هواتف ولا ملاحظات ولا مواقع دقيقة. `imageUrl` = أول `mediaUrls` فقط لسجل بلا وسائط خاصة (روابط قديمة)؛ هل يمكن أن يصل رابط موقّع إلى هنا **غير مُتحقَّق** (قراءات القوائم الحالية لا تحمل روابط حسب توثيق الكاش).
- **التشفير:** `Hive.openBox<CachedFavoriteItem>` بلا cipher ⇒ نص مقروء على القرص.
- **النسخ الاحتياطي:** `app_flutter/cached_favorites_<uid>.hive` **غير مستثنى** في `backup_rules.xml` ولا `data_extraction_rules.xml` ⇒ يدخل Auto Backup ونقل الجهاز ويُستعاد مقروءاً على جهاز آخر (يُعرض فقط إن دخل الحساب نفسه، لكن الملف نفسه مكشوف). iOS: غير مفحوص.
- **الخروج:** يرفع `FavoriteService` عدّاد الجيل فقط؛ الصندوق يبقى على القرص لكل حساب (كالقوائم المشفّرة). **حذف الحساب:** `Hive.deleteBoxFromDisk(cached_favorites_<uid>)` ⇒ يُحذف.
- **إعادة الاستخدام:** `EncryptedAccountListCache<T>` عام (encode/decode/ownerOf/idOf + مفتاح لكل حساب في Keystore + HMAC + `offline_lists` المستثنى) ⇒ صالح لقائمة المفضلات دون بنية جديدة.

**الخطوة الأمنية التالية المقترحة — FU-FAV-CACHE-ENCRYPT (تحتاج موافقة منفصلة):** نقل نسخة المفضلات إلى `EncryptedAccountListCache` (صندوق جديد داخل `offline_lists`، مفتاح لكل حساب، HMAC)، وحذف `cached_favorites_<uid>` القديم بعد أول كتابة مشفّرة ناجحة، وإبقاء حذف الحساب يكنس الاثنين؛ بلا تغيير في الواجهة ولا P3.4/P4.4. **بديل مؤقت أصغر:** استثناء `cached_favorites_*.hive` من النسخ (قاعدة XML لا تدعم wildcard للملفات ⇒ يتطلب نقل الصندوق إلى مجلد فرعي — أي تغيير مسار؛ لذا الأفضل التشفير مباشرة). القرار للمالك.

**الحالة:** FU-FAV-OFFLINE-NAV = **CODE_PROVEN** (ليس REAL_DEVICE_VERIFIED). **الملفات (غير مدمجة):** `lib/src/views/Screens/home/favorites/favorites_card.dart`؛ جديد `lib/src/services/favorite_saved_records.dart`؛ جديد `test/favorites/favorites_offline_navigation_test.dart`؛ وهذا الملف. **NOW:** موافقة المالك على commit. **NEXT:** P4.5a أو FU-FAV-CACHE-ENCRYPT بقرار. **STOP:** لا P4.5 تلقائياً؛ لا تغيير تشفير/صيغة/نسخ احتياطي دون موافقة؛ لا commit/push.

## 7AQ) FU-FAV-CACHE-ENCRYPT — تصميم وفحص مسبق للترحيل — 2026-11-04 (DESIGN؛ لا تغيير كود؛ ينتظر موافقة المالك)

**Git:** `perf/phase-1-startup-baseline` @ `d71f725` = `origin` (`git ls-remote` ⇒ **مدفوع**)؛ المعدّل فقط ملفات plugin الثلاثة؛ stashes = 2. الدليل: قراءة المصدر فقط (لم يُشغَّل شيء).

### الوضع الحالي (SOURCE-READ)
- **الكتابة الوحيدة:** `FavoriteService.cacheFavorites(list, expectedGeneration)` (4 مواضع في `FavoritesViewModel`: قراءة كاملة ×3، إزالة محلية ×1) ⇒ `box.clear()` ثم `addAll(CachedFavoriteItem…)` في `Hive.openBox<CachedFavoriteItem>('cached_favorites_<uid>')` **بلا cipher** في جذر `app_flutter` (غير مستثنى من النسخ).
- **القراءة:** `getCachedFavoritesSync()` **متزامنة** من صندوق مفتوح (يفتحه `initializeCache()` عند الإقلاع عبر `_initializeFavoritesServiceAsync` وعند فتح الشاشة)؛ وإن لم يكن مفتوحاً عند بناء الشاشة، يرسم الـ VM الكاش بعد `initializeCache()` (مسار قائم).
- **الحراس القائمة:** صندوق لكل uid، `_hasValidCacheBoxForCurrentUser`، عدّاد الجيل عند تغيّر الحساب، P4.4 (الفشل لا يكتب أبداً). **الخروج:** الصندوق يبقى. **حذف الحساب:** `deleteBoxFromDisk`.
- **صندوق قديم مشترك `cached_favorites`** (قبل عزل الحسابات): لا يُفتح أبداً، **وتُرك عمداً** — حذفه جُرّب وأُلغي لأنه أتلف بيانات محفوظة (`main.dart`). غير مشفّر ويُنسخ احتياطياً.

### اكتشاف حاسم
`EncryptedAccountListCache._prepare` ينقل تلقائياً أي ملف `<boxPrefix><uid>.hive` من جذر المستندات إلى `offline_lists`. **إعادة استخدام البادئة `cached_favorites_` = نقل الصندوق غير المشفّر ثم فشل فتحه بالمفتاح ⇒ يُعامل كتالف.** ⇒ **بادئة جديدة إلزامية.**

### التصميم المقترح (أصغر تغيير؛ إعادة استخدام كاملة للبنية القائمة)
1. **جديد `FavoritesLocalCache extends EncryptedAccountListCache<SavedFavorite>`** — نفس نمط القوائم الست: بادئة `favorites_v1_`، مفتاح Keystore لكل حساب `favorites_cache_key_v1_<uid>`، `listKey: 'favorites_v1'`، HMAC-v2، داخل `offline_lists` (**مستثنى من النسخ أصلاً ⇒ لا تغيير XML**). السجل: `{account, id, type, title, subtitle, imageUrl?, addedAt, media{k,v}}`؛ `ownerOf = account` (يُرفض أي سجل لحساب آخر عند الكتابة والقراءة). يُحذف `thumbnailUrl` (نسخة من `imageUrl`) و`cachedAt` (لا يُقرأ).
2. **`FavoriteService` (التواقيع بلا تغيير):** `initializeCache()` = قراءة النسخة المشفّرة للـ uid إلى **لقطة في الذاكرة** (للعملية فقط، تُمسح عند تغيّر الجيل)؛ `getCachedFavoritesSync()` يعيد اللقطة ⇒ **الرسم الأول بلا تغيير** حيث يحدث اليوم (التسخين عند الإقلاع قائم)، والحالة الباردة تمر بالمسار القائم «ارسم بعد `initializeCache`» — **لا واجهة جديدة ولا قفزة تخطيط جديدة**. `cacheFavorites()` يكتب المشفّر بالحراس نفسها (الجيل + الحساب + الجلسة).
3. **الترحيل — بلا استيراد من النص الصريح:** النسخة المشفّرة تُملأ **فقط** من جواب خادم كامل (عقد P4.4) أو تعديل محلي بعده؛ **لا تُنسخ** محتويات `cached_favorites_<uid>` إليها (وإلا يُوقَّع بـ HMAC ملفٌ ربما عُدِّل أو استُعيد من نسخة احتياطية). بعد أول كتابة مشفّرة **مُتحقَّق منها بالقراءة الراجعة** للـ uid ⇒ `Hive.deleteBoxFromDisk('cached_favorites_<uid>')` لذلك الحساب فقط. لا حذف قبل ذلك أبداً (يحترم درس الصندوق المشترك).
4. **الفشل مغلق:** مفتاح مفقود/صندوق تالف/HMAC فاشل ⇒ لا مفضلات من الكاش (تحميل الخادم كما اليوم)؛ الاستبدال فقط بجواب خادم (`mayRecover`) — كالقوائم الست.
5. **حذف الحساب:** خطوة `FavoritesLocalCache().forgetAccount(uid)` بجانب حذف الصندوق القديم (يبقى).
6. **الملفات المتوقعة:** جديد `lib/src/services/favorites_local_cache.dart`؛ `favorites_service.dart` (داخلياً)؛ `deleted_account_local_data_cleaner.dart` (خطوة)؛ اختبارات جديدة + تحديث `favorites_account_isolation_test` (50 مرجعاً للصندوق القديم) و`favorites_viewmodel_initial_load_test` وبدائل الملفات الأخرى (3 لكلٍّ). **لا** `main.dart` (تسجيل المحوّل يبقى لقراءة الانتقال)، لا خادم، لا تبعيات، لا UI، لا P3.4/P4.4.

### قرارات المالك المطلوبة
- **D1 (فترة الانتقال، حتى أول جواب خادم بعد التحديث):** **(A، موصى به)** عرض الصندوق القديم للحساب نفسه **للقراءة فقط** كما اليوم ثم حذفه بعد أول كتابة مشفّرة — لا فقدان offline عند الترقية؛ **(B)** عدم عرضه أبداً — أول فتح بعد الترقية ينتظر الخادم (offline ⇒ حالة الخطأ القائمة).
- **D2 (`imageUrl` القديم):** **(موصى به)** إبقاؤه في النسخة المشفّرة لتطابق البطاقات؛ أو حذفه (بطاقات بلا صورة قديمة offline).
- **D3 (الصندوق المشترك القديم `cached_favorites`):** **(موصى به، منفصل)** إضافة استثناء نسخ احتياطي **بالمسار الدقيق** `app_flutter/cached_favorites.hive` (لا حذف بيانات)؛ أو تركه كما هو (قرار سابق).

### حدود باقية حتى بعد التنفيذ
- صناديق `cached_favorites_<uid>` لحسابات لا تسجّل الدخول مجدداً على الجهاز تبقى (ولا يمكن استثناؤها بقاعدة XML لأن الاسم يحمل uid). تُحذف عند دخول ذلك الحساب أو حذفه.
- إعادة تشغيل ملف مشفّر أقدم صالح (replay) ممكنة كما في القوائم الست (HMAC يغطي الحمولة لا الملف).
- iOS backup غير مفحوص. لا شيء REAL_DEVICE_VERIFIED.

### خطة الأدلة (عند الموافقة)
اختبارات حمراء أولاً (Hive مؤقت + secure storage وهمي): ذهاب وإياب للحقول؛ سجل حساب آخر يُرفض؛ HMAC/مفتاح خاطئ ⇒ لا شيء؛ A/B؛ خروج ودخول الحساب نفسه (جلسة جديدة)؛ إعادة تشغيل؛ الفشل لا يكتب (P4.4)؛ **لا استيراد من الصندوق القديم**؛ حذف القديم فقط بعد كتابة مُتحقَّقة؛ D1(A) عرض القديم للقراءة فقط؛ حذف الحساب يزيل الاثنين؛ لا ملف مقروء نصاً تحت `app_flutter` بعد الترحيل. ثم طفرات، وانحدار `test/favorites` + `r2_search_favorites_responsive`، Analyzer مركّز، تنسيق 3.5، `git diff --check`.

### الحالة و NOW / NEXT / STOP
- **FU-FAV-CACHE-ENCRYPT = DESIGN (OPEN).** `d71f725` مدفوع.
- **NOW:** قرارات المالك D1/D2/D3 وموافقة صريحة على التنفيذ. **NEXT:** التنفيذ بالخطة أعلاه وحدها، ثم P4.5a. **STOP:** لا تنفيذ قبل الموافقة؛ لا حذف بيانات قبل كتابة مشفّرة مُتحقَّقة؛ لا تغيير XML دون D3؛ لا commit/push؛ Samsung DEFERRED.

### التنفيذ — 2026-11-04 (CODE_PROVEN؛ غير مدمج) — موافقة المالك: D1 = A، D2 بشرط، D3 = استثناء ضيق
**Git عند البدء:** `d71f725` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس.

**D2 — فُحص `imageUrl` قبل التنفيذ ⇒ شرط التوقف انطبق:** `getOffersByIds` يمرّ عبر `_withDisplayMedia` ⇒ `applyOfferMedia` يضع **روابط R2 موقّعة** في `mediaUrls`؛ و`FavoritesViewModel` يضع `imageUrl = offer.mediaUrls.first` حين `FavoriteCardMedia.fromOffer` = null (مثلاً عرض بفيديو بلا إطار قابل للعرض) ⇒ **رابط موقّع قصير العمر كان يُحفظ في النسخة غير المشفّرة** (و`thumbnailUrl` نسخة منه). Owners: `mediaUrls` فارغة دائماً في Supabase ⇒ `imageUrl` = null. **البديل الآمن المُنفَّذ:** النسخة المشفّرة **لا تحفظ أي رابط** — فقط هوية الوسائط الثابتة القائمة (`FavoriteCardMedia.toStored` = `{k: offer-media:<uid>:<mediaId>, v}`)، وحتى العرض المؤقت من النسخة القديمة لا يحمل `imageUrl`. **العرض online بلا تغيير** (البطاقات من الخادم تحمل الرابط في الذاكرة)؛ بطاقة من الكاش كانت ستعرض رابطاً منتهياً (خطأ تحميل) تعرض الآن البديل الافتراضي. **مقترح لاحق (غير مُنفَّذ):** اشتقاق وسائط البطاقة لتلك العروض من هويات `mediaObjectIds` بدل الرابط.

**الملفات:**
- جديد `lib/src/services/favorites_local_cache.dart`: `FavoritesLocalCache extends EncryptedAccountListCache<StoredFavorite>` — بادئة **`favorites_v1_`** (لا تصطدم بـ `cached_favorites_*`)، مفتاح Keystore `favorites_cache_key_v1_<uid>`، `listKey: favorites_v1`، داخل `offline_lists`؛ السجل `{account,id,type,title,subtitle,addedAt,media}` فقط. و`FavoritesMemory` (ذاكرة العملية للنسخة المفكوكة + علامة «من النص الصريح») — **في `services/` عمداً**: `favorites_service` يُستورد بتهجئتين (`Views`/`views`) ⇒ مكتبتان وحالتان static منفصلتان؛ اختبار حذف الحساب كشف ذلك (الذاكرة لم تُمسح) قبل النقل.
- `encrypted_account_list_cache.dart`: **إضافة قراءة فقط** `hasSavedBox(uid)` (لا تنشئ/تنقل/تفتح؛ عند الشك ⇒ `true` كي لا يُختار النص الصريح). **لا تغيير صيغة/HMAC/علامات.**
- `favorites_service.dart` (التواقيع القائمة بلا تغيير): `initializeCache` ⇒ مشفّرة إن وُجدت؛ **موجودة وغير مقروءة (مفتاح مفقود/تالفة) ⇒ لا شيء، أبداً النص الصريح**؛ لا مشفّرة إطلاقاً ⇒ القديمة **للقراءة فقط** (D1-A). `getCachedFavoritesSync` من `FavoritesMemory`. `cacheFavorites` (الجواب الكامل للخادم فقط) ⇒ كتابة مشفّرة (`mayRecover` لاستبدال نسخة غير مقروءة بجواب الخادم فقط) ⇒ **قراءة راجعة ومطابقة حرفية** ⇒ ثم فقط حذف `cached_favorites_<uid>` لذلك الحساب. جديد `cacheFavoritesAfterRemoval` (للإزالة المحلية) **لا يُنشئ النسخة المشفّرة أبداً**. عناصر النص الصريح معلَّمة ولا تُكتب أبداً في النسخة المشفّرة. `invalidateForAccountChange` يمسح الذاكرة.
- `favorites_viewmodel.dart`: سطر واحد — الإزالة تستدعي `cacheFavoritesAfterRemoval`.
- `deleted_account_local_data_cleaner.dart`: `FavoritesMemory.forget` + `FavoritesLocalCache().forgetAccount` (الصندوق والمفتاح) بجانب حذف الصندوق القديم القائم.
- `backup_rules.xml` و`data_extraction_rules.xml` (cloud-backup **و** device-transfer): استثناء **المسار الدقيق** `app_flutter/cached_favorites.hive` و`.lock` فقط (الصندوق المشترك القديم؛ **لا حذف**). لا استثناء واسع.
- اختبارات: جديد `test/favorites/favorites_encrypted_cache_test.dart`؛ `favorites_account_isolation_test.dart` (إعداد التخزين المشفّر في setUp/tearDown فقط — التوقعات بلا تغيير).

**سلوك الترحيل (مُثبت):** قراءة لا تُنشئ شيئاً؛ القديمة تُعرض حتى أول جواب كامل؛ الجواب (حتى الفارغ المؤكد) يُنشئ المشفّرة ثم يحذف القديمة لذلك الحساب فقط؛ كتابة غير مؤكدة (مفتاح لا يُحفظ، أو رفض الكاش) ⇒ **القديمة تبقى وتُعرض**؛ قديمة متروكة بجانب مشفّرة سليمة (تنظيف مقطوع) ⇒ تُحذف عند الفتح التالي؛ قديمة لحساب آخر ⇒ لا تُلمس؛ مفتاح مفقود/صندوق تالف ⇒ لا مفضلات من الكاش، **القديمة لا تُعرض ولا تُحذف**، وأول جواب كامل يستعيد ثم يحذفها.

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- أحمر أولاً: الملف الجديد لم يُترجَم على الكود دون تغيير (الواجهة غير موجودة).
- `favorites_encrypted_cache_test` **24/24** + `favorites_account_isolation_test` **11/11**: حفظ مشفّر + لا أسماء مقروءة في الملف + المفتاح في secure storage + إعادة تشغيل بالحقول والترتيب وهوية الوسائط بلا رابط؛ لا `imageUrl` في السجل؛ قائمة فارغة مؤكدة تُحفظ فارغة؛ عملية دافئة ⇒ عرض فوري لشاشة جديدة؛ كتابة قديمة الجيل تُرفض؛ A/B بعد إعادة التشغيل؛ خروج ⇒ لا شيء وذاكرة ممسوحة، دخول ⇒ تعود؛ **حذف الحساب عبر `DeletedAccountLocalDataCleaner` الحقيقي** ⇒ المشفّرة والمفتاح والقديمة والذاكرة تُزال وB باقٍ؛ مسارات الترحيل السبعة أعلاه؛ رفض الكاش ⇒ القديمة تبقى؛ مفتاح مفقود/صندوق تالف ⇒ لا رجوع؛ قواعد XML (مرة في full-backup، مرتان في Android 12+، لا استثناء لـ `app_flutter` كله)؛ الملف داخل `offline_lists`.
- **الطفرات 8/8 التُقطت** (الملفان أُعيدا، SHA-256 مطابق): رجوع للنص الصريح عند صندوق غير مقروء؛ بلا مرشّح عناصر النص الصريح؛ الإزالة تُنشئ النسخة؛ بلا مطابقة القراءة الراجعة (**نجت أولاً ⇒ أُضيف اختبار «كتابة رفضها الكاش لا تُعدّ مؤكدة»**)؛ الذاكرة لا تُمسح عند تغيّر الحساب؛ بلا حذف المتروك عند الفتح؛ بلا `mayRecover`؛ المنظّف بلا `forgetAccount`.
- **انحدار مركّز:** `test/favorites` + `r2_search_favorites_responsive` + `test/account` + `offline_lists_storage_test` + `owners_local_first_test` ⇒ **320 PASS، 2 FAIL — كلاهما سابق ومُصنّف:** `delete_account_test` (ملف الهجرة التاريخي) و`delete_account_ui_test` «a completed deletion…» (**FU-ACCOUNT-UI-BASELINE-1**؛ أُعيد إثبات استقلاله: نسخ HEAD من الملفات الأربعة المعدّلة مؤقتاً ⇒ يفشل بالطريقة نفسها، ثم أُعيدت بـ SHA-256 مطابق). حراس النسخ الاحتياطي في scanner/image_to_pdf/signature ⇒ PASS؛ `combine_source_guards` «honesty…» **يفشل على HEAD أيضاً** (`combine_pdfs_view.dart` في HEAD يحوي `LinearProgressIndicator`؛ لم يُلمس) ⇒ **FU-COMBINE-GUARD-1 (OPEN، مستقل)**.
- **Analyzer** (7 ملفات) ⇒ No issues. **Format 3.5:** الملفان الجديدان مُنسّقان؛ المعدّلة بلا انحراف جديد (`favorites_viewmodel` 30 = 30 سابقة؛ البقية 0). **`git diff --check`** نظيف؛ CRLF؛ XML يُحلَّل.

**أثر التحميل (MEASURED على VM الاختبار في Windows، secure storage وهمي — ليس Samsung ولا Keystore):** أول قراءة بعد «إعادة تشغيل»: 0 / 100 / 1,000 / 5,000 مفضّل ⇒ مشفّرة **13 / 16 / 37 / 97 ms** مقابل النص الصريح 3 / 6 / 21 / 24 ms (تشغيل منفرد)؛ تحت حمل الانحدار 28 / 44 / 97 / 289 مقابل 11 / 31 / 70 / 73. **الرسم المتزامن في أول إطار يحدث فقط بعد أن قُرئت النسخة في هذه العملية** (تسخين الإقلاع القائم `_initializeFavoritesServiceAsync` أو زيارة سابقة)؛ أول فتح بارد قبل اكتمال القراءة **غير متزامن** — يمر بمسار الـ VM القائم «ارسم الكاش بعد `initializeCache`» (لا واجهة جديدة). زمن Keystore الحقيقي غير مقيس.

**المخاطر الباقية (نص صريح):**
- `cached_favorites_<uid>` لحسابات لا تسجّل الدخول مجدداً على الجهاز يبقى (ويُنسخ احتياطياً — لا يمكن استثناؤه بالمسار لأن الاسم يحمل uid) حتى دخولها أو حذفها؛ قد يحوي روابط R2 موقّعة **منتهية** وأسماء عملاء.
- الصندوق المشترك القديم `cached_favorites` يبقى على القرص (قرار سابق، لا حذف)؛ الآن **مستثنى** من النسخ الجديدة؛ **النسخ الاحتياطية التاريخية** التي أُخذت قبل هذا التغيير ما زالت تحويه (خارج سيطرة التطبيق).
- مساران من ثلاثة لا يكتبان الجواب الفارغ المؤكد (`_refreshImmediately`، `_loadFreshFavoritesImmediately` — سلوك سابق)؛ المسار الثالث (`loadFavorites`/`refresh`) يكتبه، ولذلك يُرحَّل الحساب ذو الصفر عند أول تحميل عادي.
- عنصر قديم معروض كان قيد تبديل وقت أول جواب ⇒ يُستبعد من النسخة المشفّرة (لا يُوقَّع)؛ الجواب التالي يُكمله.
- إعادة تشغيل ملف مشفّر أقدم صالح (replay) ممكنة كالقوائم الست. iOS backup غير مفحوص. **لا شيء REAL_DEVICE_VERIFIED.**

**الحالة:** **FU-FAV-CACHE-ENCRYPT = CODE_PROVEN** (ليس REAL_DEVICE_VERIFIED). **NOW:** مراجعة المالك ثم موافقة commit منفصلة. **NEXT:** P4.5a بقرار. **STOP:** لا commit/push؛ لا P4.5 تلقائياً؛ Samsung/البناء الأصلي DEFERRED (قبول الجهاز: ترقية فوق نسخة فيها نص صريح، offline بعد الترقية، فقدان Keystore، حذف الحساب).

### المراجعة الأمنية والتوافقية النهائية — 2026-11-04 (قبل الإيداع)
**Git:** `d71f725` = `origin`؛ stashes = 2؛ ملفات plugin الثلاثة لم تُلمس. **قرار المالك D2:** موافقة على **عدم حفظ روابط R2 الموقّعة**، وقبول بديل افتراضي مؤقت لمفضّل offline بلا هوية وسائط ثابتة؛ العرض online وتخزين الوسائط بالهوية يبقيان.

| # | البند | النتيجة |
|---|---|---|
| 1 | أسماء مميزة | PASS — صندوق `favorites_v1_<uid>` في `offline_lists`، مفتاح `favorites_cache_key_v1_<uid>`؛ لا تصادم مع `cached_favorites_<uid>` (جذر `app_flutter`) ولا مع بادئات القوائم الست (`cached_<entity>_` / `<entity>_cache_key_v1_`). `_moveEarlierBox` يبحث عن `favorites_v1_<uid>.hive` في الجذر ⇒ لا ملف قديم بهذا الاسم ⇒ لا نقل. |
| 2 | الإنشاء من جواب خادم فقط | PASS — `cacheFavorites` له 3 مستدعين فقط (`favorites_viewmodel` 215/462/618)، كلها بعد `getAllFavoritesWithMetadata` الناجح (عقد P4.4: كامل أو استثناء، والفراغ مؤكد الجلسة). الإزالة (962) ⇒ `cacheFavoritesAfterRemoval` لا يُنشئ. `OptimisticFavoritesService` لا يكتب الكاش. عناصر النص الصريح لا تُكتب أبداً (طفرة M2). المصالحة قد تُبقي عنصراً **سبق أن جاء من الخادم** قيد تبديل (سلوك P3/P4 القائم) — لا عنصر غير مؤكد. |
| 3 | الفراغ المؤكد ≠ فشل الشبكة | PASS — الفشل لا يصل إلى `cacheFavorites` (اختبارات P4.4 `cacheWrites` فارغة — ضمن الانحدار 320)؛ الفراغ المؤكد يُحفظ قائمة فارغة **مقروءة** (`readSaved` ≠ null). |
| 4 | حذف القديمة بعد التحقق | PASS — كتابة ⇒ `readSaved` (HMAC، `authenticated`) ⇒ مطابقة حرفية لكل سجل ⇒ ثم الحذف (طفرة M4 + اختبار «كتابة رفضها الكاش»). |
| 5 | الانقطاع/إعادة التشغيل/الحسابات/الخروج/التلف/المفتاح/الاستعادة | PASS — مغطاة؛ **وُجدت فجوة ضيقة وأُغلقت (أدناه).** |
| 6 | لا رجوع للنص الصريح | PASS بعد الإصلاح — **فجوة:** انقطاع `_recover` بين `rename(current ⇒ .recovery/*.unreadable)` و`rename(spare ⇒ current)` يترك الصندوق في `.recovery` فقط ⇒ كان `hasSavedBox` يُرجع false ⇒ تُعرض النسخة القديمة. **الإصلاح:** `hasSavedBox` يعدّ أيضاً `.recovery/<file>` و`.recovery/<file>.unreadable`. **اختبار جديد** «a recovery cut off between its renames does not fall back» — **أحمر بدون الإصلاح، أخضر معه** (الملف أُعيد، SHA-256 مطابق). |
| 7 | لا روابط/أسرار/حسابات أخرى | PASS — `StoredFavorite` = `account,id,type,title,subtitle,addedAt,media` فقط؛ `media` = `{k: offer-media:<uid>:<mediaId>, v}` (يُرفض عند القراءة ما لا يبدأ بـ `offer-media:`)؛ `ownerOf` يُسقط سجلات حساب آخر عند الكتابة والقراءة؛ `account` = uid الكاتب دائماً. |
| 8 | online بلا تغيير | PASS — `git diff` لـ `favorites_service.dart` محصور في قسم الكاش (أسطر HEAD 3–349)؛ الجلب والترقيم P4.4 والدفعات P3.4 وبناء `FavoriteItem` (مع `imageUrl` في الذاكرة) و`FavoriteCard` بلا تغيير. الترتيب: المحفوظ بترتيب الكتابة (مرتّب `addedAt` تنازلياً)، والقديم مرتّب تنازلياً. |
| 9 | النسخ الاحتياطي وحذف الحساب | PASS — استثناء المسار الدقيق `app_flutter/cached_favorites.hive`/`.lock` (مرة في `full-backup-content`، مرتان في Android 12+)، لا استثناء واسع؛ حذف الحساب: القديمة + المشفّرة + المفتاح + الذاكرة (اختبار بالمنظّف الحقيقي). |
| 10 | الذاكرة عبر `Views`/`views` | PASS — `FavoritesMemory` (والعلامة) في `services/` بتهجئة واحدة؛ اختبار حذف الحساب يجتاز **عبر التهجئتين فعلاً** (الاختبار `views`، المنظّف `Views`) — وهو ما كشف المشكلة قبل النقل. (`_accountGeneration` في `FavoriteService` ما زال static قابلاً للازدواج عبر التهجئتين — **سابق**، التطبيق يستخدم `Views` وحدها.) |
| 11 | أول فتح بارد | موثّق أعلاه — لا ادعاء رسم فوري في أول إطار قبل قراءة النسخة في العملية؛ Keystore غير مقيس. |
| 12 | نطاق `encrypted_account_list_cache.dart` | PASS — إضافة دالة قراءة واحدة `hasSavedBox` (لا تكتب/تنقل/تفتح/تنشئ مفتاحاً)؛ مستدعوها في `favorites_service` فقط؛ لا تغيير في `read`/`write`/`_recover`/`_prepare`/HMAC/العلامات/`directoryName` ⇒ D-1a/D-2/D-3 والقوائم الست بلا تأثير. |

**الوسائط بلا هوية ثابتة ⇒ إلى نقطة Offline Media لاحقاً (FU-FAV-MEDIA-NO-IDENTITY، OPEN):** عرض Offer لا ينتج `FavoriteCardMedia` (مثلاً فيديو أول بلا إطار قابل للعرض، أو أنواع غير معروفة في `OfferMediaUrlCache`) كان يعتمد على `imageUrl` = رابط موقّع؛ offline الآن بديل افتراضي. المقترح: اشتقاق الوسائط من `mediaObjectIds` بالهوية. لا نظام وسائط جديد هنا.

**الأدلة الإضافية (شغّلها الوكيل):** `favorites_encrypted_cache_test` **25/25** (بعد التنسيق)؛ `offline_lists_storage_test` + `offline_lists_integrity_test` + الملف الجديد ⇒ **70/70**؛ Analyzer (الملفان) ⇒ No issues؛ Format 3.5: الجديدان مطابقان، `encrypted_account_list_cache.dart` 0 انحراف؛ `git diff --check` نظيف؛ CRLF في كل الملفات المعدّلة. لم يُكرَّر الانحدار الكامل (التغيير محصور في `hasSavedBox` + اختبار).

**الحكم:** **PASS — FU-FAV-CACHE-ENCRYPT = CODE_PROVEN.** المخاطر الباقية للنص الصريح (منفصلة): `cached_favorites_<uid>` لحسابات غير نشطة على الجهاز (غير قابلة للاستثناء بالمسار)؛ الصندوق المشترك القديم على القرص (مستثنى الآن)؛ النسخ الاحتياطية التاريخية؛ FU-FAV-MEDIA-NO-IDENTITY؛ FU-COMBINE-GUARD-1 مستقل. **STOP:** موافقة commit النهائية من المالك.

## 7AR) P4.5a — البحث من النسخ المحلية المشفّرة أولاً — 2026-11-05 (CODE_PROVEN؛ غير مدمج)

**Git عند البدء:** `perf/phase-1-startup-baseline` @ `bcf4b9a` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس.

### السبب الجذري لاعتماد Search على الشبكة (SOURCE-READ)
`DefaultSearchDataSource.load` = ست قراءات خادم كاملة (`getX().first`، ترقيم P4) **دون أي قراءة للنسخ المشفّرة** ⇒ أول بحث offline = خطأ شبكة دائماً. موجود سابقاً ومحفوظ: مجموعة بيانات واحدة لكل VM صالحة 5 دقائق + debounce 300 ms + قراءة واحدة مشتركة ⇒ **لا قراءة لكل حرف**. فجوات إضافية مُثبتة: (1) `.first` يُبقي الاشتراك حياً حتى أول قائمة ⇒ **إغلاق Search أثناء القراءة لا يوقف الصفحات**؛ (2) `Future.wait` بلا `eagerError` ⇒ فشل قائمة واحدة **لا يوقف الخمس الأخرى**؛ (3) قوائم فارغة تحت جلسة مُزاحة تُقبل بلا تأكيد (`_pagedRows` يُرجع `[]` حين العدّ = 0) ⇒ «لا نتائج» كاذبة؛ (4) بعد فشل، **كل بحث تالٍ** يعيد ست قراءات؛ (5) مجموعة البيانات مربوطة بالحساب لا بالجلسة.

### التنفيذ (ملفان إنتاجيان؛ لا خادم/RLS/Auth/SAD/صيغة كاش/HMAC/علامات/نسخ احتياطي/تبعيات/واجهة)
- **`search_data_source.dart`:** واجهة اختيارية `LocalFirstSearchSource` (`currentSessionId`، `loadSaved()`، `cancelReads()`) — البدائل القائمة في الاختبارات بلا تغيير. `loadSaved()` يقرأ **القوائم المشفّرة الست للحساب الحالي فقط** عبر `*LocalCache.read(uid)` القائم (HMAC، سجلات الحساب وحده، إخفاء علامات الحذف، رفض المحجوب) ⇒ `SavedSearchData(data, covered)`؛ قائمة غير مقروءة/مفقودة/محجوبة = **غير مغطاة، لا قائمة فارغة**؛ تغيّر الحساب أو الجلسة أثناء القراءة ⇒ لا شيء. `load()`: نفس القوائم الست (P4 بلا تغيير: 500/صفحة، 20,000، أخطاء الاكتمال)، لكن باشتراك مُدار: أول قائمة ثم إلغاء، `eagerError` ⇒ فشل أي قائمة يُلغي البقية فوراً، `cancelReads()` يوقف كل الصفحات الجارية؛ **أي قائمة فارغة ⇒ تأكيد جلسة واحد** (`ListSessionCheck.confirmFor`، كشاشات القوائم) وإلا `ListSessionNotCurrent`.
- **`search_viewmodel.dart`:** حين لا مجموعة صالحة للحساب **والجلسة**: قراءة النسخ المحلية أولاً ⇒ جواب فوري منها ⇒ ثم قراءة الخادم ⇒ تحلّ محلها. فشل الخادم ⇒ تبقى النتائج المحلية. **التغطية:** نتيجة فارغة لنوع (أو «الكل») غير مغطى بالكامل محلياً ⇒ **ليست «لا نتائج»**: تنتظر الخادم، وإن فشل ⇒ حالة خطأ الشبكة القائمة (لا نص جديد). مجموعة الخادم المتأخرة لحساب/جلسة سابقة ⇒ **تُسقط** (لا تستبدل مجموعة الجلسة الحالية). بعد فشل الخادم للجلسة نفسها ⇒ **لا إعادة قبل 30 ث** ما دامت هناك سجلات محلية (Retry/التحديث يتجاوزان)؛ فشل قطعه تغيّر الجلسة لا يؤخر الجلسة التالية. `dispose` ⇒ `cancelReads()`. مُعرَّض للاختبار فقط: `resultsFromSavedCopy`، `savedCoverage`. مجموعة واحدة في الذاكرة (المحلية تُستبدل بالخادم — لا نسخة دائمة مكررة).
- **مطابقة الحقول:** كل حقل يطابقه `SearchEngine` محفوظ في الكاشات الست؛ الوسائط ليست فيها ولا في قراءات الخادم الجماعية ⇒ **المطابقة والترتيب والفلاتر والعربية/الإنجليزية متطابقة** (اختبار مقارنة مباشر).

### عدد الطلبات (MEASURED — حتمي، بدائل)
| الحالة | قبل | بعد |
|---|---|---|
| أول بحث online | 6 قوائم خادم (مرقّمة) ثم جواب | 6 قراءات **محلية** ⇒ جواب فوري، ثم 6 قوائم خادم (كما قبل) |
| أول بحث offline بلا نسخ | خطأ | خطأ (كما قبل) |
| أول بحث offline مع نسخ | خطأ | **جواب محلي**؛ محاولة خادم واحدة |
| 5 حروف سريعة | قراءة واحدة | قراءة واحدة (محلية واحدة + خادم واحد) |
| بحوث متتالية offline | 6 قوائم **لكل بحث** | **0** لمدة 30 ث بعد الفشل |
| إغلاق Search أثناء القراءة | الصفحات تستمر حتى أول قائمة | **تتوقف** (إلغاء الاشتراكات) |
| فشل قائمة واحدة (صفحة 2) | الخمس الأخرى تستمر | **تُلغى فوراً**؛ لا قائمة جزئية |
| أي قائمة فارغة | تُقبل | **+1** تأكيد جلسة (`is_current_app_session`) |

**زمن البحث المحلي (MEASURED على VM الاختبار في Windows، ليس Samsung):** 12,000 سجل محفوظ (2,000 × 6): أول بحث (قراءة + فهرسة + بحث، بدائل) **134–226 ms**؛ 20 بحثاً لاحقاً **173–241 ms إجمالاً** (~9–12 ms لكل بحث). فك تشفير Keystore الحقيقي على الجهاز **غير مقيس**.

### الأدلة (شغّلها الوكيل بتفويض هذه المهمة)
- **أحمر أولاً:** `search_local_first_test.dart` لم يُترجَم على الكود دون تغيير (الواجهة غير موجودة).
- **جديد `test/search/search_local_first_test.dart` — 32/32:** offline مع نسخ؛ بلا نسخ؛ نوع واحد وخمسة مفقودة (الإخفاق ≠ «لا نتائج»، فلتر غير مغطى ⇒ خطأ شبكة)؛ الست مغطاة (إخفاق حقيقي)؛ المحلي يظهر قبل الخادم ثم يُستبدل؛ فشل بعد المحلي يُبقيه؛ فراغ موثوق من الخادم يستبدل؛ حساب آخر؛ خروج؛ جلسة جديدة للحساب نفسه تقرأ مجدداً؛ جواب خادم لجلسة سابقة يُسقط؛ قراءة قطعها تغيّر الجلسة لا تؤخر التالية؛ إغلاق ⇒ `cancelReads`؛ كتابة سريعة ⇒ قراءة واحدة؛ تأخير 30 ث وRetry؛ الفلاتر والترتيب والعربية متطابقة مع مسار الخادم؛ النتيجة تحمل سجلها المحفوظ للتنقل؛ 12,000 سجل. **مع الكاش المشفّر الحقيقي:** الست مغطاة ولحسابها؛ نوع واحد فقط؛ لا شيء؛ حساب آخر لا يُقرأ؛ علامة حذف ⇒ مستبعد؛ HMAC مزوّر ⇒ غير مغطى؛ مفتاح خاطئ ⇒ غير مغطى؛ خروج/تغيّر الحساب أو الجلسة أثناء القراءة ⇒ لا شيء. **قوائم الخادم:** قراءة واحدة لكل قائمة ثم إلغاء؛ فشل قائمة ⇒ فشل وإلغاء الخمس؛ `cancelReads` ⇒ إلغاء الست؛ الفارغة ⇒ تأكيد واحد (true يُقبل، false ⇒ `ListSessionNotCurrent`، null يُقبل)؛ بلا فراغ ⇒ لا تأكيد. **ربط حقيقي:** المصدر الحقيقي + VM + Owners محفوظة + كل قراءات الخادم تفشل ⇒ النتيجة تظهر.
- **الطفرات 10/10 التُقطت** (الملفات أُعيدت، SHA-256 مطابق): بلا الجلسة في صلاحية المجموعة؛ إبقاء جواب جلسة سابقة (**نجت أولاً ⇒ قُوّي الاختبار**)؛ بلا فحص التغطية؛ بلا التأخير؛ بلا الإلغاء عند الإغلاق؛ تأخير عبر الجلسات؛ بلا تأكيد الفراغ؛ بلا `eagerError`؛ بلا إعادة الفحص بعد القراءة المحلية؛ ادعاء تغطية أنواع مفقودة.
- **انحدار مركّز:** `test/search` كاملاً + `r2_search_favorites_responsive` + `offline_lists_integrity` + `confirmed_deletion` + `offline_lists_storage` + `list_false_empty` + `entity_keyset_pagination` + `auth/single_active_session_source` ⇒ **585/585**؛ بعد الإصلاحات الأخيرة `test/search` + responsive ⇒ **373/373**، ثم الملفان المعنيان بعد التنسيق ⇒ **103/103**. **ملاحظة:** أول تشغيل كشف 10 إخفاقات في `search_viewmodel_test` (فجوة async إضافية حتى لمصادر بلا القدرة المحلية) ⇒ أُصلح بتجاوز القراءة المحلية لتلك المصادر — سلوكها كما كان حرفياً.
- **Analyzer** (3 ملفات) ⇒ No issues. **Format 3.5:** `search_viewmodel.dart` 0 انحراف؛ `search_data_source.dart` (أُعيدت كتابته؛ 0 في HEAD) نُسّق؛ الاختبار الجديد نُسّق. **`git diff --check`** نظيف؛ CRLF.

### الحدود الباقية
- **لا مؤشر واجهة** للنتائج المحلية أو للتغطية الجزئية (بلا نص جديد بقرار المالك)؛ النتائج المحلية قد تكون قديمة حتى ينجح الخادم (حداثتها = آخر قراءة لكل قائمة، P2.5c).
- البحث المحلي يغطي فقط الأنواع التي فُتحت شاشة قائمتها لهذا الحساب على هذا الجهاز (هي ما يكتب الكاش)؛ **Search نفسه لا يكتب الكاش**.
- أول فتح بعد إعادة تشغيل offline ما زال خاضعاً لبوابة الجلسة القائمة عند الإقلاع (Retry) — لا تجاوز.
- التفاصيل offline: كل الأنواع الست تفتح بسجل النتيجة (`extra: result.data` = حقول القائمة المحفوظة)؛ Offers by-id تعرضه ثم تحاول التحديث الموثوق (يفشل offline بحالتها القائمة). وسائط بطاقات النتائج: السلوك القائم (المحفوظ بالهوية أولاً ثم حلّ بحد 3) — **لا تنزيلات جديدة**.
- الذاكرة: المجموعة الكاملة (حتى 6 × 20,000) في الذاكرة طوال عمر شاشة Search كما قبل؛ ذروة القراءة الأولى = المحلية ثم الخادم بالتتابع (لا تداخل دائم). غير مقيس على الجهاز.
- **P4.3-ACCEPT-NONEMPTY: OPEN.** Samsung/البناء الأصلي DEFERRED — قبول الجهاز المقترح: بحث offline بعد فتح القوائم، ترقية، تبديل حساب، إغلاق أثناء القراءة على شبكة بطيئة.

### الحالة و NOW / NEXT / STOP
- **P4.5a = CODE_PROVEN** (ليس HOSTED ولا REAL_DEVICE_VERIFIED).
- **الملفات (غير مدمجة):** `lib/src/views/Screens/home/search/search_data_source.dart`؛ `lib/src/views/Screens/home/search/search_viewmodel.dart`؛ جديد `test/search/search_local_first_test.dart`؛ وهذا الملف.
- **NOW:** مراجعة المالك وموافقة commit. **NEXT (اقتراح):** قياس فتح الشاشات السبع (P4.7) أو Quotations (ترقيم وإبقاء القائمة). **STOP:** لا commit/push؛ لا المرحلة التالية تلقائياً.

## 7AS) P4.7 — خط أساس فتح الشاشات السبع — 2026-11-05 (BASELINE؛ لا تغيير كود إنتاجي)

**Git:** `perf/phase-1-startup-baseline` @ `f14f3e6` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس. **الملف الوحيد الجديد:** `test/perf/list_open_baseline_test.dart` (أداة قياس للاختبار فقط، 25/25).

**طبقات الدليل:** (M) قيس بالاختبارات الآلية على VM الاختبار في Windows (JIT، secure storage وهمي بدل Keystore) — **للمقارنة النسبية فقط، ليس زمن هاتف**؛ (S) من المصدر؛ (E) تقدير؛ (D) Samsung — **غير مُتحقَّق، DEFERRED**.

### 1) مسار الفتح (S) — الست متطابقة
فتح الشاشة ⇒ `ChangeNotifierProvider` يُنشئ VM جديداً ⇒ `watchUser*LocalFirst()` ⇒ `localFirstList`: **(1)** `readSaved` على الـ main isolate: قراءة مفتاح secure storage + فتح صندوق Hive المشفّر (AES) + `json.decode` للغلاف + HMAC-SHA256 (Dart خالص) على الحمولة كلها + `json.decode` + تحويل كل سجل + العلامات + **`fingerprintOf` = إعادة ترميز JSON للقائمة كلها** ⇒ أول قائمة؛ **(2) فقط بعدها** تبدأ قراءة الخادم (تتابعي) = ترقيم P4 كامل: `ceil(n/500)` طلباً (+عدّ)، **في كل فتح** (لا إعادة استخدام بين نسخ الشاشة؛ `minRefreshInterval` يخص إشارات الاستئناف فقط)؛ **(3)** جواب الخادم ⇒ `fingerprintOf` ثانية ⇒ عرض فقط إن تغيّر ⇒ **`cache.write` دائماً** (ترميز ثالث + ختم HMAC + تشفير + كتابة + قراءة راجعة وتحقق HMAC) على الـ main isolate. **البناء:** كل `notifyListeners` ⇒ فلترة + فرز + **تجميع أسبوعي لكل القائمة** + بطاقات إحصاء. القوائم lazy (SliverList) — لا تبني صفوفاً خارج الشاشة. لا وسائط بعيدة في بطاقات القوائم الست.

### 2) القياسات (M — VM الاختبار)
**قراءة النسخة المحفوظة حتى أول قائمة (`localFirst firstList`) وتكاليف الأجزاء:**
| القائمة | n | الحمولة | أول قائمة | قراءة باردة / دافئة | HMAC | `json.decode` | fingerprint | حفظ بعد جواب الخادم |
|---|---|---|---|---|---|---|---|---|
| Owners | 1,000 | 428 KiB | 49 ms | 67 / 37 | 8 | 5 | 8 | 64 ms |
| Owners | 5,000 | 2.1 MiB | 764 ms | 597 / 501 | 126 | 44 | 91 | 1,126 ms |
| Owners | 20,000 | 8.5 MiB | 3,012 ms | 2,574 / 2,054 | 535 | 194 | 403 | 3,453 ms |
| Offers | 1,000 | 601 KiB | 192 ms | 191 / 136 | 35 | 19 | 10 | 147 ms |
| Offers | 5,000 | 3.0 MiB | 1,039 ms | 884 / 629 | 177 | 72 | 128 | 1,380 ms |
| Offers | 20,000 | 11.9 MiB | 4,122 ms | 3,262 / 2,619 | 744 | 382 | 542 | 5,604 ms |
- الست عند 1,000 (قراءة باردة): Requests 171، Offers 194، Owners 142، Offices 115، Brokers 78، Watchmen 123 ms — **التكلفة تتبع حجم السجل** (Offers/Requests الأثقل).
- **إعادة الفتح أثناء التشغيل** (صندوق مفتوح): 70–85% من البارد فقط ⇒ العمل الأساسي ليس فتح الصندوق بل HMAC + فك JSON + التحويل + fingerprint في كل فتح.
- **جواب خادم مطابق:** لا إعادة بناء (fingerprint يمنع)، **لكن الحفظ يحدث دائماً** — 1.1–5.6 s على الـ main isolate بعد ظهور الشاشة ⇒ **تجمّد/تقطّع مرشّح (E)**.

**بناء الشاشة (Owners/Offers/Requests):**
| n | إطار القائمة الأول | إطار خامل | إعادة بناء عند تحديث مطابق |
|---|---|---|---|
| 1,000 | 447–475 ms | 3–6 ms | 300–332 ms |
| 5,000 | 1,282–1,511 ms | 2–4 ms | 1,172–1,518 ms |
(أول اختبار widget يشمل إحماء JIT: Owners n=100 = 1,330 ms.) الإطار الخامل رخيص ⇒ لا رسوم متحركة لكل إطار؛ **التكلفة O(n) في كل build يحمل القائمة.**

**تحديد السبب (M):** لـ 5,000 Offers لكل build: `filteredOffers` 0.5–1.3 ms؛ نسخ + فرز 0.4–1.7 ms؛ **التجميع الأسبوعي بنسخة مطابقة لـ `_getWeekKey` = 897–1,087 ms** (تواريخ هذا الأسبوع) و**1,284–1,395 ms** (تواريخ موزّعة على سنتين). ⇒ **السبب الجذري الأول لبطء البناء:** `_getWeekKey` (منسوخ حرفياً في الشاشات الست) يُنشئ ~6 `DateTime` محلية (بحث منطقة زمنية) + `DateTime.now()` **لكل سجل في كل build** — عند الظهور، وعند كل تحديث، وحذف، وتبديل فلتر.
**مرشّح الإصلاح (اختبار فقط، ليس إنتاجاً):** حدود «هذا الأسبوع/الماضي» مرة لكل build + يوم السجل بحساب UTC ⇒ **2.5 ms** (هذا الأسبوع) و**99–113 ms** (موزّعة) بدل 1,087/1,395 ms، **ومفاتيح مطابقة حرفياً لـ 13,212 تاريخاً** (محلي وUTC، 3 سنوات، 6 ساعات/يوم). (E) تخزين المفتاح لكل يوم تقويمي يخفض الباقي أكثر.

### 3) Quotations (S + M) — مستقل
- **لا نسخة محلية**؛ `StreamBuilder` يعرض المؤشر حتى **طلب خادم واحد بلا ترقيم** (`select listColumns order by created_at`) ⇒ **قص صامت عند 1,000** (`max_rows` مُتحقَّق)؛ كل فتح وكل تعديل كيان في التطبيق (`CoreEntityMutationNotifier`) ⇒ قراءة جديدة.
- **(M) فشل تحديث لاحق يستبدل القائمة المعروضة بحالة الخطأ** (`hasError` يُفحص قبل البيانات) — مُثبت باختبار يوثّق السلوك الحالي.
- البناء: `Column` غير lazy (كل البطاقات) لكنه رخيص: 35 / 66 / 114 ms لـ 100 / 500 / 1,000 — **ليس السبب**؛ الزمن الغالب = انتظار الشبكة (D).
- البطاقات بلا شبكة/صور بعيدة؛ PDF: نسخة محلية بمعرّف الوسائط إن وُجدت، وإلا رابط موقّع + تنزيل عند الفتح فقط. **الحسابات لم تُلمس.**

### 4) الأسباب الجذرية بالأولوية (مُثبتة)
1. **التجميع الأسبوعي O(n) مكلف لكل build** — الست، المصدر الأكبر لزمن ظهور القائمة وإعادة البناء.
2. **عمل التشفير/الترميز على الـ main isolate يتناسب مع الحجم**: قراءة النسخة (HMAC + فك JSON + fingerprint) قبل أي شيء، و**حفظ كامل بعد كل جواب خادم حتى لو لم يتغير شيء**.
3. **قراءة الخادم تبدأ بعد النسخة المحفوظة** (تتابعي) و**تُعاد كاملة في كل فتح**.
4. **Quotations:** شبكة فقط، بلا ترقيم، والفشل اللاحق يمسح القائمة.

### 5) التوصيات بالأولوية (الفوائد تقديرات حتى قياس الجهاز)
- **P4.7a (موصى به أولاً — مشترك للست، لا تغيير واجهة/أمان/كاش):** مساعد واحد مشترك لمفاتيح الأسبوع (الحدود مرة لكل build + حساب UTC + كاش لكل يوم) يستبدل `_getWeekKey` في الست، **مع اختبار تطابق حرفي** للمفاتيح؛ واختيارياً تذكّر التجميع في الـ VM حتى تتغير القائمة أو الفلتر. (M على VM الاختبار: ~400× للأسبوع الحالي، ~13× موزّعاً). الأقل خطراً لأنه منطق عرض فقط.
- **P4.7b (حساس — نواة الكاش؛ قرار منفصل):** عدم إعادة حفظ قائمة مطابقة (تحديث سجل الحداثة فقط) وتجنّب `fingerprintOf` الزائد عند القراءة ⇒ يزيل 1–5 s من عمل الـ main isolate بعد كل فتح. يمس `encrypted_account_list_cache.dart` (بلا تغيير صيغة) ⇒ مراجعة D-3.
- **P4.7c (لاحقاً):** نقل فك/ترميز JSON وHMAC إلى isolate؛ أو بدء قراءة الخادم بالتوازي مع المحفوظة (يتطلب ضمان الترتيب).
- **P4.7d (قرار منتج):** عدم إعادة قراءة القائمة كاملة عند إعادة الفتح خلال نافذة قصيرة لنفس الحساب/الجلسة (حداثة مقابل كلفة الشبكة).
- **Q-1 (Quotations، مرحلة مستقلة):** ترقيم keyset بعقد P4 + إبقاء القائمة عند فشل لاحق؛ نسخة محلية بقرار أمان/منتج منفصل.

### 6) الحدود والمؤجل
- كل الأرقام من VM الاختبار (JIT، Windows، secure storage وهمي) — **زمن Samsung (Keystore الحقيقي، AOT، ARM) غير مقيس**؛ البناء لم يُقس بـ profile build.
- بيانات الاختبار متجانسة (أسبوع واحد في القياس العام؛ قياس منفصل للتوزيع)؛ لا قياس لزمن الشبكة الحقيقي ولا لعدد الطلبات المستضافة (من المصدر: `ceil(n/500)` + عدّ لكل فتح).
- لم تُشغَّل انحدارات (لا تغيير إنتاجي). الإخفاقات التاريخية كما هي: FU-AUTH-BASELINE-7، اختبار ملف هجرة Delete Account، FU-ACCOUNT-UI-BASELINE-1، FU-COMBINE-GUARD-1. **P4.3-ACCEPT-NONEMPTY: OPEN.**
- **قبول الجهاز المقترح (D):** profile build؛ فتح كل شاشة من السبع بارداً/دافئاً بأحجام صغيرة وكبيرة؛ زمن أول محتوى، وتقطّع ما بعد جواب الخادم، وoffline.

### الحالة و NOW / NEXT / STOP
- **P4.7 baseline = MEASURED (VM الاختبار) + SOURCE-READ.** لا تغيير إنتاجي.
- **NOW:** موافقة المالك على **P4.7a**. **NEXT:** P4.7a وحده. **STOP:** لا تنفيذ قبل الموافقة؛ لا Quotations offline؛ لا تغيير حسابات؛ لا commit/push؛ Samsung DEFERRED.
- **(وافق المالك على P4.7a — نُفِّذ أدناه.)**

### P4.7a — مساعد مفاتيح الأسبوع المشترك للشاشات الست — 2026-11-05 (CODE_PROVEN؛ غير مدمج)
**Git:** `f14f3e6` = `origin`؛ §7AS و`test/perf/` من خط الأساس ما زالا غير مدمجين؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس.

**التنفيذ (منطق عرض فقط؛ لا تغيير واجهة/ترتيب/كاش/أمان/خادم):**
- جديد `lib/src/common/utils/list_week_keys.dart` — `ListWeekKeys(now)`: يحسب **مرة لكل عملية تجميع** ما يعتمد على «الآن» فقط (اليوم، حدود هذا الأسبوع والماضي، وتواريخ المقارنة الأربع) **بالعمليات المحلية نفسها حرفياً**؛ `keyOf(date)` ينفّذ ما يعتمد على السجل **بالعمليات المحلية نفسها وبالترتيب نفسه** (منتصف ليل اليوم المحلي، `isAfter`/`isBefore`، `date.subtract(weekday - 1)`، `year-month-day`) + تذكّر منتصف الليل المحلي لكل يوم تقويمي (دالة صافية لليوم وحده). **لا حساب UTC بدل التقويم المحلي.** لا حالة تتقادم: كل build يصنع نسخة من `DateTime.now()` الخاص به.
- الشاشات الست (`requests`/`offers`/`owners`/`offices`/`brokers`/`watchmen`_list_view.dart): حُذف `_getWeekKey` الخاص (كان متطابقاً بايتياً في الست)؛ في `_group…ByWeek`: `final weeks = ListWeekKeys(DateTime.now());` قبل الحلقة و`weeks.keyOf(date)` بدل `_getWeekKey(date)`. **الفرز والحلقة ومعالجة التاريخ الفارغ (`?? DateTime.now()`) بلا تغيير.** حُفظ CRLF وBOM القائم (requests/owners).

**التكافؤ (مُثبت):**
- جديد `test/lists/list_week_keys_test.dart` — **21/21**: نسخة حرفية من `_getWeekKey` القديم بساعة متحكَّم بها مقابل `ListWeekKeys` لـ **16 «الآن»** (اثنين 00:00، أحد آخر لحظة، منتصف أسبوع، أول/آخر الشهر، نهاية/بداية سنة وأسبوع يمتد عبر سنتين، 29 فبراير وما بعده، أيام تغيّر DST الأمريكي/الأوروبي، `now()` محلي وUTC) × **442 يوماً** × **9 أوقات** (حول منتصف الليل والظهيرة) × محلي/UTC ⇒ >7,000 مقارنة لكل ساعة؛ تواريخ تاريخية/مستقبلية/epoch؛ نسخة واحدة تعطي المفتاح نفسه دائماً؛ تجميع جديد بعد منتصف الليل يرى اليوم الجديد؛ حارس مصدر: لا `_getWeekKey` في الست، و`ListWeekKeys(DateTime.now())` مرة واحدة و`weeks.keyOf(date)` في كلٍّ.
- **مناطق زمنية:** الملف نفسه **21/21** تحت إزاحات +4 (الافتراضية) و`TZ=EST5EDT` (−5) و`UTC0` (0) و`PST8PDT` (−8). `NZST-12` لم يُطبَّق (رجع 0) ⇒ +12 غير مغطى. **انتقالات DST نفسها غير قابلة للتنفيذ هنا** (Dart على Windows يتبع إزاحة TZ لا قواعد DST) ⇒ مغطاة **بالبناء** (العمليات المحلية نفسها)، لا بالتشغيل.
- جديد `test/lists/list_week_grouping_screens_test.dart` — **12/12**: الشاشات الست الحقيقية × العربية/الإنجليزية، سجلات هذا الأسبوع/الماضي/أسابيع أقدم/قبل سنة/حافة سنة/(للأنواع الثلاثة ذات التاريخ الاختياري) سجل بلا تاريخ؛ الفواصل بالترتيب تطابق مفاتيح المساعد القديم؛ تحديث بالسجلات نفسها يعرض الشيء نفسه؛ **بصمة SHA-256 لكل النصوص المعروضة بالترتيب: 12/12 متطابقة قبل التغيير (تشغيلان) وبعده (تشغيلان).**
- **ملاحظة سلوك سابق (لم يتغير):** سجلّان **بلا تاريخ** (Brokers/Offices/Watchmen) يُفرزان بقراءات ساعة أثناء الفرز ⇒ قد يتبادلان الموضع بين بناءين — قائم قبل P4.7a وباقٍ (الفرز لم يُلمس). الاختبار يستخدم سجلاً واحداً بلا تاريخ لذلك.

**الأداء (M — VM الاختبار، الظروف نفسها؛ ليس جهازاً):**
| القياس (5,000 سجل) | قبل | بعد |
|---|---|---|
| التجميع الأسبوعي، تواريخ موزّعة على سنتين | 1,284–1,395 ms | **141 ms** |
| التجميع الأسبوعي، تواريخ هذا الأسبوع | 681–1,087 ms | **1.3 ms** |
| الشاشة الحقيقية: إطار القائمة الأول (Owners/Offers/Requests) | 1,282–1,511 ms | **111–133 ms** |
| الشاشة الحقيقية: إعادة البناء عند تحديث مطابق | 1,172–1,518 ms | **34–68 ms** |
| عند 1,000: إطار أول / إعادة بناء | 447–475 / 300–332 ms | 115–190 / 44–72 ms |
(بيانات Part 2 من أسبوع واحد؛ الموزّعة تُقاس في Part 3. الحساب «المرشّح UTC» من خط الأساس بقي للمقارنة فقط: 100 ms موزّعاً — الإنتاج يستخدم الحساب المحلي الحرفي.)

**الطفرات 4/4 التُقطت** (الملف أُعيد، SHA-256 مطابق): حدّ نهاية الأسبوع ناقص يوماً؛ تصادم مفتاح كاش منتصف الليل؛ اتفاقية بداية الأسبوع؛ «اليوم» ليس منتصف الليل.

**الانحدار المركّز:** `test/lists` كاملاً (يشمل الشاشات الست، الـ VMs، الكاشات المشفّرة، العلامات، الترقيم، الحداثة) + `r5a`/`r5b`/`r5c`/`r5d` (brokers/offices/watchmen/related cards) responsive + `test/perf/list_open_baseline_test.dart` ⇒ **853/853**. **Analyzer** (المساعد + الشاشات الست + 3 اختبارات) ⇒ No issues. **Format 3.5:** الجديدة مُنسّقة؛ الشاشات الست بلا انحراف جديد (offers 10 = 10، requests 165 = 165 سابقة؛ البقية 0). **`git diff --check`** نظيف؛ CRLF.

**الملفات (غير مدمجة):** جديد `lib/src/common/utils/list_week_keys.dart`؛ الشاشات الست `lib/src/views/Screens/ViewLists/{requests,offers,owners,offices,brokers,watchmen}_list_view.dart`؛ جديد `test/lists/list_week_keys_test.dart`؛ جديد `test/lists/list_week_grouping_screens_test.dart`؛ `test/perf/list_open_baseline_test.dart` (خط الأساس + قياس المساعد المشحون)؛ وهذا الملف.

**الحدود الباقية:** زمن Samsung (AOT/ARM) غير مقيس — التحسّن على الجهاز **تقدير**؛ ما زال كل build يعيد الفلترة والفرز والتجميع (رخيصة الآن) — لا تذكّر بين البناءات (خارج النطاق)؛ قراءة النسخة المحفوظة (HMAC/JSON/fingerprint) والحفظ بعد كل جواب خادم بلا تغيير ⇒ **P4.7b**؛ Quotations لم تُلمس (Q-1)؛ +12 وDST الفعلي غير مُنفَّذين اختبارياً. **P4.3-ACCEPT-NONEMPTY: OPEN.**

**الحالة:** **P4.7a = CODE_PROVEN** (ليس REAL_DEVICE_VERIFIED). **NOW:** مراجعة المالك ثم موافقة commit. **NEXT (اقتراح): P4.7b** — عدم إعادة حفظ قائمة مطابقة لجواب الخادم (تحديث سجل الحداثة فقط) وإزالة `fingerprintOf` الزائد عند القراءة، في `encrypted_account_list_cache.dart` بلا تغيير صيغة، مع مراجعة D-3. **STOP:** لا P4.7b تلقائياً؛ لا commit/push؛ Samsung DEFERRED.

## 7AT) P4.7b — عدم إعادة حفظ قائمة مطابقة + بصمة مؤجلة — 2026-11-06 (CODE_PROVEN؛ غير مدمج)

**Git:** `perf/phase-1-startup-baseline` @ `bff0f1c` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان لم تُلمس. **ملاحظة:** ظهر ملفان غير متتبَّعين ليسا من هذا العمل (`docs/ADD_DETAILS_AREA_CATALOG.csv`، `docs/ADD_DETAILS_DESIGNER_INVENTORY.md`) — لم يُلمسا.

### الفحص المسبق (S + M)
- **حفظ قائمة مطابقة يعيد كتابتها كاملة — مُؤكَّد:** `accept` في `localFirstList` يستدعي `cache.write` بعد **كل** جواب خادم، و`_store` يكتب `v2` دائماً (ترميز JSON + ختم HMAC + تشفير AES + **إلحاق بملف Hive** + قراءة راجعة وHMAC ثانٍ) ثم سجل الحداثة. Hive إلحاقي ⇒ **الملف ينمو بحجم القائمة كاملة في كل تحديث مطابق** حتى الضغط: (M) 475 KB / 2.4 MB / **9.6 MB** لكل حفظ مطابق لـ 1,000 / 5,000 / 20,000 Owner.
- **البصمة:** `showSavedThenListen` يحسب `fingerprintOf(saved.items)` (إعادة ترميز JSON للقائمة كلها) **قبل** إصدار القائمة المحفوظة ⇒ يؤخر أول محتوى.
- فتح الصندوق/فك التشفير، HMAC، وفك JSON عند القراءة: مقيسة في §7AS (لم تتغير هنا).

### التنفيذ (`lib/src/services/encrypted_account_list_cache.dart` وحده؛ **لا تغيير صيغة/مفاتيح/HMAC/علامات/نسخ احتياطي**)
1. **`write`:** يحسب `_verified(...)` للقائمة الموجودة **مرة واحدة** (كان يحسبها أصلاً لفحص الأصالة) ويمرّرها إلى `_store(current: …)`.
2. **`_store`:** إن كانت القائمة الموجودة **مُتحقَّقاً منها** (HMAC تحت هذا المفتاح والحساب والقائمة) **وحمولتها تساوي الحمولة الجديدة حرفياً** (مقارنة سلسلة JSON كاملة: كل السجلات والحقول والترتيب) ⇒ **لا تُكتب `v2` من جديد**؛ ما عدا ذلك بلا تغيير: سجل الحداثة يُختم ويُكتب **في كل قراءة خادم ناجحة** مربوطاً بوسم القائمة نفسها المُتحقَّق منه (الوسم حتمي ⇒ مطابق لما كانت القراءة الراجعة ستعطيه)، وإزالة قائمة v1 القديمة + الضغط (S2) تبقى. قائمة مفقودة/غير مُتحقَّقة/مختلفة ⇒ المسار القديم حرفياً (كتابة + قراءة راجعة). كل الحراس قبل `_store` بلا تغيير (حذف مؤكد هذه الدورة، الحجب، `mayRecover`، العلامات غير المقروءة، D-2).
3. **`localFirstList`:** القائمة المحفوظة تُصدر **أولاً**، وبصمتها تُحسب **عند أول جواب خادم فقط** (`shownFingerprint()`) ⇒ الإصدارات ومنع التكرار بلا تغيير.

### القياس (M — VM الاختبار، تشغيل متتابع قديم/جديد مرتين؛ ليس جهازاً)
| Owners | حفظ مطابق قبل ⇒ بعد | نمو الملف عند الحفظ المطابق | أول قائمة قبل ⇒ بعد | بصمات قبل الخادم |
|---|---|---|---|---|
| 0 | 8–9 ⇒ 5–6 ms | 363 B ⇒ 248 B | 24–35 ⇒ 26–27 ms | 1 ⇒ 0 |
| 100 | 21–43 ⇒ 13–16 ms | 47 KB ⇒ 248 B | 41–43 ⇒ 32–45 ms | 1 ⇒ 0 |
| 1,000 | 103–106 ⇒ **40 ms** | 475 KB ⇒ **248 B** | 89–92 ⇒ 69–89 ms | 1 ⇒ 0 |
| 5,000 | 477–669 ⇒ **208–281 ms** | 2.4 MB ⇒ **248 B** | 329–430 ⇒ 380–508 ms (ضجيج) | 1 ⇒ 0 |
| 20,000 | 3,030–3,238 ⇒ **982–1,105 ms** | 9.6 MB ⇒ **248 B** | 2,038–2,333 ⇒ **1,569–1,830 ms** | 1 ⇒ 0 |
- **الحفظ عند التغيير:** المسار نفسه (الفروق ضجيج VM). **ما بقي في الحفظ المطابق** (~1 s عند 20,000 على VM): ترميز JSON للقائمة الجديدة + HMAC للتحقق من الموجودة + بصمة قائمة الخادم + البصمة المؤجلة للمحفوظة ⇒ **P4.7c**.
- الكتابة على القرص لكل تحديث مطابق: **سجل حداثة واحد (~250 B) بدل القائمة كلها** ⇒ ضغط Hive أقل تكراراً (E).

### الأدلة (شغّلها الوكيل بتفويض هذه المهمة)
- **أحمر أولاً:** `offline_lists_unchanged_save_test.dart` على الكود دون تغيير ⇒ 4 إخفاقات مقصودة (إعادة الكتابة ×2، الست، البصمة قبل الإصدار) + خطأ في اختبار نفسه (`.single` لخمسة عناصر) أُصلح.
- **جديد `test/lists/offline_lists_unchanged_save_test.dart` — 25/25:** مطابق ⇒ لا إعادة كتابة (`v2` نفسه بايتياً، نمو < 2 KB) والحداثة = وقت القراءة الجديدة؛ بلا وقت ⇒ يبقى السابق؛ فارغة موثوقة مكررة ⇒ فارغة صالحة + حداثة؛ بعد إعادة التشغيل؛ **سجل واحد تغيّر حقله، إعادة ترتيب، إضافة، إزالة، غير فارغة بعد فارغة ⇒ كتابة كاملة**؛ وسم HMAC مكسور بحمولة مطابقة ⇒ **ليست «مطابقة»** (بلا `mayRecover` لا كتابة؛ معه استعادة)؛ سجل حداثة تالف ⇒ يُستبدل؛ **S2:** v1 وحدها ⇒ v2 وتُزال v1؛ v1 بجانب v2 مطابقة ⇒ تُزال؛ **D-2:** مفتاح مفقود ⇒ استعادة فقط بقائمة خادم موثقة؛ علامات حذف غير مقروءة ⇒ حجب ولا حفظ؛ قائمة فيها سجل حُذف مؤكداً هذه الدورة ⇒ رفض والحداثة القديمة باقية؛ حسابان منفصلان؛ **Delete Account** يزيل الصندوق والمفتاح؛ ثلاث حفظات متزامنة ⇒ ترتيبها محفوظ والأخيرة تفوز؛ **التدفق:** القائمة المحفوظة تُعرض بلا أي بصمة، قائمة خادم مطابقة لا تُعرض ثانية، المتغيرة تُعرض؛ **الست** (Requests/Offers/Owners/Offices/Brokers/Watchmen) ⇒ حداثة فقط عند التطابق؛ قياسات 0/100/1,000/5,000/20,000.
- **الطفرات 6/6 التُقطت** (الملف أُعيد، SHA-256 مطابق): مقارنة الطول فقط؛ أي قائمة مُتحقَّقة = «مطابقة»؛ المطابق يتخطى الحداثة وv1؛ المطابق يتخطى إزالة v1؛ البصمة المؤجلة لا تُحسب أبداً (إصدار مكرر)؛ البصمة المبكرة قبل أول قائمة.
- **انحدار مركّز:** `test/lists` كاملاً (التكامل، الحداثة، العلامات، الاسترداد، التخزين، القوائم الست local-first، الترقيم، الشاشات) + `test/favorites` (يشمل الكاش المشفّر للمفضلات على النواة نفسها) + `search_local_first_test` + `test/account` + `test/perf/list_open_baseline_test` ⇒ **893 PASS، 2 FAIL — كلاهما تاريخي ومُصنّف** (ملف هجرة Delete Account؛ FU-ACCOUNT-UI-BASELINE-1 بالتوقع نفسه `['Your account has been deleted.']`). بعد تصحيح التنسيق: الجديد + التكامل + الحداثة ⇒ **66/66**.
- **Analyzer** (ملفان) ⇒ No issues. **Format 3.5:** النواة 0 انحراف (كان 0)؛ الاختبار الجديد مُنسّق. **`git diff --check`** نظيف؛ CRLF.

### التوافق الأمني
لا صيغة جديدة ولا قاعدة ثقة جديدة: «مطابق» يتطلب قائمة **اجتازت HMAC** بالمفتاح والحساب والقائمة نفسها **ومساواة الحمولة حرفياً** — لا عدّ صفوف ولا checksum. القائمة التالفة/المفقودة/غير المُتحقَّقة/v1/المحجوبة لا تُعامل كمطابقة أبداً. سجل الحداثة مختوم ومربوط بوسم القائمة كما كان. D-1a/D-2/D-3/العلامات/حذف الحساب/عزل الحسابات بلا تغيير.

### الحدود الباقية
- الحفظ المطابق ما زال يرمّز القائمة الجديدة ويتحقق بـ HMAC من الموجودة (~1 s عند 20,000 على VM)؛ قراءة النسخة المحفوظة (فك/HMAC/JSON) بلا تغيير؛ كل ذلك على الـ main isolate.
- لا قياس على Samsung (Keystore/AOT/ARM) — التحسّن على الجهاز **تقدير**. **P4.3-ACCEPT-NONEMPTY: OPEN.**

**الملفات (غير مدمجة):** `lib/src/services/encrypted_account_list_cache.dart`؛ جديد `test/lists/offline_lists_unchanged_save_test.dart`؛ وهذا الملف.

**الحالة:** **P4.7b = CODE_PROVEN.** **NOW:** مراجعة المالك ثم موافقة commit. **NEXT (اقتراح): P4.7c** — نقل ترميز/فك JSON وHMAC للقوائم الكبيرة إلى isolate خلفي (Hive يبقى على الرئيسي)، أو بدء قراءة الخادم بالتوازي مع المحفوظة بضمان الترتيب — يحتاج تصميماً ومراجعة D-3. **STOP:** لا P4.7c تلقائياً؛ لا commit/push؛ Samsung DEFERRED.

## 7AU) P4.7c — تصميم وفحص مسبق لعمل الـ main isolate — 2026-11-06 (DESIGN + MEASURED؛ لا تغيير إنتاجي)

**Git:** `perf/phase-1-startup-baseline` @ `e3e461a` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان والملفان غير المتتبَّعين `docs/ADD_DETAILS_*` لم تُلمس. **الملف الوحيد الجديد:** `test/perf/main_isolate_probe_test.dart` (أداة قياس للاختبار فقط، 9/9).

**طبقات الدليل:** (M) VM الاختبار في Windows (JIT، secure storage وهمي) — مقارنة نسبية فقط؛ (S) المصدر؛ (E) تقدير؛ (D) Samsung غير مُتحقَّق. «أطول حجب» = أطول فجوة بين نبضات مؤقت 1 ms على الـ isolate نفسه أثناء العملية (= زمن عدم قدرة واجهة المستخدم على رسم إطار).

### 1) ما يجري على الـ main isolate (S، مؤكَّد بالقياس)
- **قراءة النسخة (`readSaved`)**: فتح الصندوق (Hive يقرأ الملف ويفك AES لكل الإطارات) ⇒ ثم **مقطع متزامن واحد بلا أي await**: `json.decode` للغلاف (الحمولة مخزّنة **كسلسلة JSON داخل JSON** ⇒ فك الهروب لكامل الحمولة) + `utf8.encode` + HMAC-SHA256 + `json.decode` للحمولة + `Map.from` وبناء النموذج لكل سجل + العلامات + سجل الحداثة. ⇒ **القراءة كلها حجب واحد**.
- **جواب الخادم (`accept`)**: بصمة قائمة الخادم (`json.encode`) + البصمة المؤجلة للمحفوظة (P4.7b) + `write`: `json.encode` ثانٍ للقائمة نفسها + `_verified` للقائمة الموجودة (فك الغلاف + HMAC) ⇒ إن تطابقت: سجل حداثة فقط (P4.7b)؛ وإلا ختم (ترميز الغلاف بالهروب + HMAC) + `put` (تشفير + إلحاق بالملف) + **قراءة راجعة** (فك الغلاف + HMAC مرة أخرى).
- **تحليل جواب الخادم نفسه (PostgREST JSON)**: على الـ main isolate (S) — غير مقيس هنا (بلا شبكة).
- **تسليم القائمة للـ VM**: `controller.add` على الـ isolate نفسه — O(1).
- **حقيقة حاسمة (M):** Hive يُرجع **نفس كائن String** الذي وُضع بـ `put` ما دام الصندوق مفتوحاً (`afterPut=true`, `stableWhileOpen=true`)، وكائناً جديداً بعد إعادة الفتح (`afterReopen=false`) ⇒ **«القراءة الراجعة» في `_store` تتحقق من الكائن نفسه في الذاكرة الذي خُتم للتو، لا من القرص.**

### 2) القياسات (M — كل خلية: الإجمالي / أطول حجب، ms)
| | Owners 1k | Offers 1k | Owners 5k | Offers 5k | Owners 20k | Offers 20k |
|---|---|---|---|---|---|---|
| الحمولة | 422 KiB | 595 KiB | 2.1 MiB | 2.9 MiB | 8.4 MiB | 11.8 MiB |
| قراءة باردة | 52/39 | 69/58 | 456/457 | 691/691 | 1,705/1,690 | 2,288/2,261 |
| قراءة دافئة (إعادة فتح) | 31/31 | 43/42 | 252/253 | 435/435 | 1,274/1,274 | 1,892/1,892 |
| فتح الصندوق (AES) | 11/10 | 15/12 | 144/144 | 137/137 | 426/410 | 568/552 |
| **فك الغلاف** | 8/8 | 16/16 | 147/147 | 164/164 | **600/600** | **802/802** |
| HMAC | 7/7 | 12/12 | 119/119 | 159/159 | 432/432 | 512/512 |
| فك الحمولة | 2/2 | 3/3 | 22/23 | 39/39 | 217/217 | 193/193 |
| بصمة (ترميز) | 5/5 | 6/6 | 75/76 | 66/66 | 307/307 | 531/531 |
| حفظ مطابق (P4.7b) | 30/30 | 39/38 | 242/241 | 457/456 | 1,097/1,097 | 1,520/1,519 |
| حفظ متغيّر | 78/55 | 122/93 | 875/653 | 1,295/915 | 3,489/2,518 | 4,635/3,445 |
| **isolate: فك + HMAC** | 12/2 | 32/15 | 141/16 | 235/38 | 567/59 | **843/93** |
| isolate: ترميز | 6/1 | 22/17 | 75/24 | 131/40 | 368/65 | 619/103 |
| HMAC مجزّأ (64 KiB + yield) | 12/5 | 38/8 | 81/12 | 161/26 | 422/53 | 663/93 |
- بدء isolate: ≈0–5 ms. ذاكرة RSS عند فك 20k في isolate ونقل النتيجة: +41 MB (Owners) / +68 MB (Offers) مؤقتاً. عند 100 سجل كل شيء ≤ 15 ms.
- **ما تبقّى من القراءة الدافئة** (20k Offers): 1,892 − (802 + 512 + 193) ≈ **385 ms** = `Map.from` + بناء النماذج + العلامات/الحداثة (استنتاج من الفرق).
- **حفظ مطابق 20k Offers ≈ 1.5 s** = ترميز (~0.53) + فك غلاف الموجودة (~0.8) + HMAC (~0.5) — وهي قائمة **تحقق منها هذا الـ isolate قبل لحظات** عند القراءة.

### 3) الخيارات
**A — isolate خلفي** (`Isolate.run`، موجود سابقاً في `image_pdf_executor`): نقل فك الغلاف + HMAC + فك الحمولة + بناء النماذج (دوال `_decode` ثابتة ⇒ قابلة للإرسال؛ النتيجة تُنقل بـ `Isolate.exit` بلا نسخ). Hive يبقى على الرئيسي. **الفائدة (M):** حجب الرئيسي عند 20k Offers من ~1.9–2.3 s إلى ~0.1 s؛ **الإجمالي لا يقل** (843 مقابل ~1,507 للأجزاء نفسها؛ أحياناً أبطأ قليلاً). **الكلفة:** نسخ الغلاف إلى الـ isolate (≈12 MB)، ذروة ذاكرة +40–70 MB مؤقتاً، **مفتاح MAC (المشتق، لا مفتاح الصندوق) يُمرَّر داخل العملية**، معالجة أخطاء يجب أن تبقى «لا شيء» حرفياً، تعقيد متوسط. يفيد **القراءة الباردة** (أول فتح بعد الإقلاع) التي لا يفيدها C.
**B — قراءة الخادم بالتوازي مع المحفوظة:** لا يقلل عمل الـ main isolate إطلاقاً (يتداخل فقط مع انتظار الشبكة)؛ مخاطر: جواب خادم قبل المحفوظة (يجب ألا تُعرض المحفوظة بعده)، تعارض الطابور مع `write` (`_oneAtATime` يحل الترتيب لكنه يغيّر توقيت الحفظ)، مراجعة كل حالات الجلسة/الإلغاء/D-2/الحجب. **الفائدة غير قابلة للقياس محلياً** (زمن الشبكة). **غير موصى به الآن.**
**C — تقليل العمل المكرر على الرئيسي (بلا isolate ولا تغيير ترتيب):**
- **C1 — تذكّر التحقق (memo):** لكل صندوق، آخر `(كائن الغلاف بالهوية، بايتات المفتاح) ⇒ (الحمولة، الوسم)` الذي اجتاز `_verified`. إن أعاد Hive **الكائن نفسه** (`identical`) تحت **المفتاح نفسه** ⇒ النتيجة نفسها لدالة صافية ⇒ لا فك غلاف ولا HMAC. يُمسح عند إغلاق الصندوق، `forgetAccount`، الاستعادة D-2، `debugForgetProcessState`. **لا قاعدة ثقة جديدة**: ما يُتحقق منه اليوم هو هذا الكائن في الذاكرة بالضبط. يزيل ~1.3 s (20k Offers) من: الحفظ المطابق، الحفظ المتغيّر (القراءة الراجعة لكائن خُتم للتو)، وإعادة الفتح الدافئة.
- **C2 — إعادة استخدام بصمة قائمة الخادم كحمولة:** `accept` يرمّز القائمة للبصمة ثم `write` يرمّزها مرة ثانية؛ حين `withoutConfirmedDeletions` يعيد **نفس القائمة** (لا شيء مخفي) وكل السجلات للحساب نفسه ⇒ الحمولة = البصمة حرفياً ⇒ ~0.5 s أقل.
- **C3 — مقارنة البصمة بحمولة المحفوظة المُتحقَّقة** بدل إعادة ترميز القائمة المحفوظة (P4.7b يؤجلها فقط): تساوٍ ⇒ لا إصدار (صحيح)؛ عدم تساوٍ ⇒ إصدار (قد يكون زائداً لكنه آمن الاتجاه — لا يفوّت تحديثاً أبداً)؛ فقط حين لا شيء مخفي.
- **تقدير C (E، من مجموع الأجزاء المقيسة، 20k Offers، VM):** جواب خادم مطابق ≈ **2.6 s ⇒ ~0.6 s** على الرئيسي؛ الحفظ المتغيّر −~1.3 s؛ إعادة الفتح الدافئة ~1.9 ⇒ ~0.6 s. **القراءة الباردة بلا تغيير** (لا memo بعد الإقلاع). ذاكرة: +حجم حمولة قائمة واحدة لكل صندوق مفتوح (≤ 12 MB عند 20k Offers) طوال فتحه.

### 4) المقارنة والتوصية
| | فائدة مقيسة/مقدّرة | حجب الرئيسي | ذاكرة | خطر أمني | تعقيد | قابلية الاختبار |
|---|---|---|---|---|---|---|
| **A** | قراءة باردة: حجب ~2.3 ⇒ ~0.1 s (M) | الأكبر | +40–70 MB مؤقتاً | متوسط (مفتاح MAC عبر isolate، تكافؤ الأخطاء) | متوسط–عالٍ | جيدة |
| **B** | غير مقيسة (شبكة) | لا شيء | لا شيء | متوسط (ترتيب/جلسات) | متوسط | صعبة |
| **C** | تحديث مطابق ~2.6 ⇒ ~0.6 s؛ متغيّر −1.3 s؛ دافئة ~1.9 ⇒ ~0.6 s (E) | كبير لغير البارد | +حمولة/صندوق | منخفض (memo لدالة صافية بالهوية) | منخفض | ممتازة |
**التوصية:** **P4.7c = الخيار C (C1 + C2 + C3)** أولاً — أصغر وأقل خطراً، بلا isolate ولا تغيير ترتيب، ويخفض أكبر تكرار مُثبت. **P4.7c-2 (اختياري، بعد قياس Samsung):** الخيار A للقراءة الباردة فقط وفوق عتبة حجم (مثلاً > 256 KiB) إن بقي التقطّع ملحوظاً على الجهاز. **B مؤجل.** عند ≤ 1,000 سجل كل المسارات ≤ ~120 ms على VM ⇒ لا حاجة لـ isolate للقوائم الصغيرة.

### 5) حدود أمنية (لكل الخيارات)
لا صيغة/مفتاح/HMAC جديد؛ D-1a/D-2/D-3، الغلاف v2 المُصادَق، حجب العلامات الصارم، عزل الحسابات، جلسة القراءة الأصلية، الخروج/الدخول للحساب نفسه، الفراغ المؤكد، انتقال v1، تنظيف حذف الحساب — **بلا تغيير**. الـ memo: في الذاكرة فقط، بلا تسجيل، مربوط بالهوية + بايتات المفتاح + الصندوق (uid + القائمة)، يُمسح عند الإغلاق/النسيان/الاستعادة. **قرار مراجعة D-3 مطلوب:** قبول أن «القراءة الراجعة» = التحقق من الكائن نفسه في الذاكرة (وهو ما تفعله اليوم فعلياً). الخيار A يحتاج قراراً إضافياً بتمرير مفتاح MAC المشتق إلى isolate داخل العملية.

### 6) الاختبارات المطلوبة عند التنفيذ (C)
memo يُصاب فقط للكائن نفسه والمفتاح نفسه؛ كائن مختلف بالمحتوى نفسه ⇒ تحقق كامل؛ مفتاح مختلف (D-2) ⇒ تحقق؛ وسم مكسور ⇒ لا memo ولا «مطابق»؛ بعد إغلاق/إعادة فتح ⇒ تحقق كامل؛ `forgetAccount`/الاستعادة/حذف الحساب ⇒ memo ممسوح؛ عزل الحسابات؛ C2 فقط حين لا مخفي وكل السجلات للحساب (سجل لحساب آخر ⇒ ترميز كامل)؛ C3 إصدار عند عدم التساوي ولا إصدار عند التساوي، ومع علامات مخفية ⇒ المسار القديم؛ كل اختبارات P4.7b والتكامل والحداثة والقوائم الست؛ طفرات للحراس الثلاثة؛ قياس قبل/بعد بالأداة نفسها.

### 7) المؤجل والمتابعات
- **Samsung (D):** القراءة الباردة/الدافئة والتقطّع بعد جواب الخادم بـ profile build، 1k/5k/20k، Keystore حقيقي — **يحدد إن كان P4.7c-2 (A) لازماً**.
- **P4.7d (قرار منتج):** عدم إعادة قراءة القائمة كاملة عند إعادة الفتح خلال نافذة قصيرة.
- **Q-1 (Quotations):** ترقيم keyset (حد 1,000) + إبقاء القائمة عند فشل لاحق — **أولوية منتج أعلى من P4.7c-2** لأنه خطأ صحة لا أداء.
- **P4.3-ACCEPT-NONEMPTY: OPEN.** الإخفاقات التاريخية (ملف هجرة Delete Account، FU-ACCOUNT-UI-BASELINE-1، FU-AUTH-BASELINE-7، FU-COMBINE-GUARD-1) كما هي؛ لم تُشغَّل انحدارات (لا تغيير إنتاجي).

### الحالة و NOW / NEXT / STOP
- **P4.7c = DESIGN + MEASURED (VM).** **NOW:** قرار المالك: C (موصى به) / A / تأجيل، وقبول بند مراجعة D-3. **NEXT:** المختار وحده. **STOP:** لا تنفيذ قبل الموافقة؛ لا commit/push؛ Samsung DEFERRED.
- **(وافق المالك على الخيار C بشروط أمنية صارمة — نُفِّذ أدناه.)**

### P4.7c — تنفيذ الخيار C — 2026-11-06 (CODE_PROVEN؛ غير مدمج)
**Git:** `e3e461a` = `origin`؛ §7AU (التصميم) و`test/perf/main_isolate_probe_test.dart` غير مدمجين؛ ملفات plugin الثلاثة وstashes الاثنان و`docs/ADD_DETAILS_*` لم تُلمس.

**التنفيذ (`lib/src/services/encrypted_account_list_cache.dart` وحده؛ لا صيغة/مفاتيح/HMAC/علامات/نسخ احتياطي):**
- **C1 — تذكّر الأغلفة المُتحقَّقة (`_verifiedEnvelopes` + `_checked`):** لكل صندوق، مدخل واحد `{Box, String sealed, uid, key, (payload, tag)}` يُنشأ **فقط بعد `_verified` كامل** لكائن أعاده Hive. يُعاد استخدامه **فقط** إن كان: الكائن نفسه (`identical`) + الـ Box نفسه (`identical`) والصندوق مفتوح + الـ uid نفسه + بايتات المفتاح نفسها. أي شيء آخر (نص مطابق في كائن آخر، صندوق أُعيد فتحه، مفتاح آخر، حساب آخر) ⇒ `_verified` كامل. **لا يُنشأ مدخل لكائن كتبناه نحن**: القراءة الراجعة في `_store` تتحقق منه كاملاً أول مرة (كائن جديد) ثم يُعاد استخدامه. يُمسح: عند إغلاق الصندوق (يُزال عند أول استخدام لاحق للخريطة)، عند بدء الاستعادة D-2 (`_recover`)، `forgetAccount` (قبل الطابور وداخله)، `debugForgetProcessState`. لا شيء منه يُكتب أو يُسجَّل. **مُستخدَم في:** `readSaved`، فحص الأصالة في `write`، والقراءة الراجعة في `_store`. لا يغيّر ما يُتحقق منه (كائن Hive في الذاكرة — كما كان) ولا يدّعي شيئاً عن القرص.
- **C2 — حمولة من بصمة الخادم:** `write` العامة بلا تغيير وتفوّض إلى `_write(…, encoded:)` الخاصة؛ `localFirstList.accept` يمرّر `shown` (= `fingerprintOf(visible)`) **فقط** حين `identical(visible, items)` (لا علامة حذف تخفي شيئاً)، و`_write` يستخدمها **فقط** إن كان كل سجل لحساب uid؛ وإلا ترميز كامل كما كان ⇒ التمثيل المحفوظ لا يتغير أبداً.
- **C3 — مقارنة بحمولة المحفوظة المُتحقَّقة:** `readSaved` يربط (Expando) الحمولة المُتحقَّقة بالـ `SavedList` **فقط** إن كانت v2 مُصادَقة ولا شيء مخفي (`identical(visible, items)`)؛ `localFirstList` يستخدمها كقيمة المقارنة بدل ترميز القائمة المحفوظة؛ وإلا البصمة المؤجلة (P4.7b). عدم التطابق ⇒ إصدار (اتجاه آمن: لا تحديث يُفوَّت).
- خطافات اختبار فقط (`@visibleForTesting`): `debugFullVerifications`، `debugEncodes`، `debugMemoIsFor`، `debugRetainedPayloadChars`، `debugSettled`.

**القياس (M — `main_isolate_probe_test`، قديم/جديد متتابعان مرتين، الأداة نفسها؛ الإجمالي / أطول حجب، ms؛ ليس جهازاً):**
| | Offers 20k قبل ⇒ بعد | Owners 20k قبل ⇒ بعد | Offers 5k | Owners 1k |
|---|---|---|---|---|
| **جواب خادم مطابق** (بعد إعادة تشغيل) | 2,105–2,369 / 1,510–1,597 ⇒ **320–330 / 307–320** | 1,480–1,515 / 956–964 ⇒ **211–225 / 206–216** | 543–556 / 364–375 ⇒ 75–95 / 71–90 | 35–45 / 22–26 ⇒ 6–7 / 5 |
| **جواب خادم متغيّر** | 5,037–5,084 / 3,217–3,274 ⇒ **3,200–3,360 / 1,769–1,885** | 3,337–3,559 / 2,177–2,366 ⇒ **2,062–2,064 / 1,084–1,120** | 1,243–1,313 / 840–856 ⇒ 830–865 / 488–509 | 89–91 / 59–62 ⇒ 55–62 / 29–32 |
| **قراءة دافئة** (إعادة فتح) | 1,552–1,628 ⇒ **515–591** | 1,068–1,157 ⇒ **389–404** | 407–453 ⇒ 139–152 | 29–32 ⇒ 11 |
| قراءة باردة (أول فتح بعد الإقلاع) | ~2.1–2.2 s ⇒ ~2.2 s (**بلا تغيير، متوقع**) | ~1.4–1.6 s ⇒ ~1.3–1.4 s | ~0.5–0.6 s | ~45–60 ms |
- **100 سجل:** لا تراجع (كل المسارات ≤ ~40 ms، الدافئة 6–13 ⇒ 3–4 ms).
- «حفظ مطابق» المباشر في الأداة (`cache.write` بعد إعادة فتح الصندوق يدوياً داخل الأداة) لا يتحسن — **عن قصد**: الكائن جديد بعد إعادة الفتح ⇒ تحقق كامل. المسار الواقعي هو «جواب الخادم» أعلاه.
- **الذاكرة المحتفظ بها (حساب، لا RSS):** المدخل يُبقي **حمولة القائمة كسلسلة** طالما صندوقها مفتوح = عدد أحرف الحمولة (اختبار: `debugRetainedPayloadChars == payload.length`) ⇒ ~بايت/حرف للنص اللاتيني، 2 بايت/حرف إن وُجد نص عربي. مثال: Offers 20k ≈ 12 MB، Owners 20k ≈ 8.4 MB، 1k ≈ 0.4–0.6 MB. **الحد الأعلى لكل حساب:** 7 صناديق (القوائم الست + المفضلات المشفّرة) — عملياً ما فُتح منها فقط. يُحرَّر عند إغلاق الصندوق/النسيان/الاستعادة. (Hive نفسه يُبقي الغلاف المختوم في الذاكرة دائماً؛ المدخل يضيف ~نسخة واحدة من الحمولة.)

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- **أحمر أولاً:** الملف الجديد على كود HEAD ⇒ 28 خطأ ترجمة (الخطافات غير موجودة).
- **جديد `test/lists/offline_lists_verified_reuse_test.dart` — 21/21:** إعادة استخدام الكائن نفسه (0 تحقق إضافي)؛ **نص مطابق في كائن آخر ⇒ تحقق كامل**؛ غلاف مزوّر في كائن جديد ⇒ مرفوض؛ إغلاق/إعادة فتح ⇒ كامل؛ إعادة تشغيل ⇒ كامل؛ مفتاح مفقود ⇒ لا قراءة ثم استعادة D-2 ⇒ صحيحة؛ مفتاح خاطئ ⇒ لا فتح؛ **مفتاح استُبدل والصندوق مفتوح (Hive يعيد الصندوق والكائن نفسيهما) ⇒ تحقق تحت المفتاح الجديد ⇒ null كما قبل**؛ حساب آخر لا يستعمل تحقق هذا؛ علامات غير مقروءة ⇒ حجب رغم المذكَّر؛ **Delete Account** يمسح المدخل؛ قراءات/كتابات متزامنة مرتبة؛ مدخل واحد لكل صندوق مفتوح يُحرر عند الإغلاق؛ **التدفق:** مطابق ⇒ لا إصدار ولا إعادة كتابة والحداثة مُحدَّثة و**ترميز واحد فقط** (قائمة الخادم)؛ حقل متغيّر/إعادة ترتيب/إضافة ⇒ إصدار والحمولة = `fingerprintOf` الخادم حرفياً؛ سجل لحساب آخر ⇒ مستبعد من الحمولة؛ علامة حذف مخفية ⇒ الحمولة كما أرسلها الخادم (D-3) والمقارنة بالترميز؛ v1 لا تُعامل كـ v2 وتُرحَّل؛ قائمة محجوبة ⇒ لا حفظ؛ فارغة موثوقة ⇒ فارغة صالحة؛ **الأنواع السبعة** (6 + المفضلات) ⇒ `fingerprintOf(decode(payload)) == payload` حرفياً (ما يعتمد عليه C3) والمدخل يُنشأ.
- **الطفرات 7/8 التُقطت** (الملف أُعيد، SHA-256 مطابق): مساواة المحتوى بدل الهوية؛ بلا فحص المفتاح؛ `forgetAccount` يُبقي المدخل؛ C2 بلا فحص الملكية؛ C2 مع علامات مخفية؛ C3 مع علامات مخفية؛ أي مدخل يُصادق أي كائن. **نجت 1 — مكافئة:** إزالة فحص `uid` (المدخل مفهرس باسم الصندوق الذي يتضمن uid ⇒ لا يمكن أن يختلف عبر الواجهة؛ أُبقي دفاعاً في العمق). فحص هوية الـ Box كذلك دفاع في العمق (الصندوق المعاد فتحه يعطي كائنات String جديدة).
- **انحدار مركّز:** `test/lists` كاملاً + `test/favorites` + `search_local_first_test` + `test/account` + `test/perf` (الأداتان) ⇒ **923 PASS، 2 FAIL — التاريخيان نفسهما** (ملف هجرة Delete Account؛ FU-ACCOUNT-UI-BASELINE-1 بالتوقع نفسه). بعد التنسيق: الجديد + P4.7b ⇒ **46/46**.
- **Analyzer** (3 ملفات) ⇒ No issues. **Format 3.5:** النواة 0 انحراف؛ الاختباران مُنسّقان. **`git diff --check`** نظيف؛ CRLF.

**الحدود الباقية:** القراءة الباردة (أول فتح بعد الإقلاع) **بلا تحسّن** — تبقى حجباً واحداً (~2.2 s عند 20k Offers على VM) ⇒ قرار P4.7c-2 (الخيار A) بعد قياس Samsung؛ الجواب المتغيّر ما زال ~1.1–1.9 s حجباً عند 20k (ختم + HMAC + القراءة الراجعة الأولى لكائن جديد + فك الحمولة)؛ ذاكرة +حمولة واحدة لكل صندوق مفتوح؛ تحليل JSON لجواب PostgREST غير مقيس؛ **لا قياس Samsung**. **P4.3-ACCEPT-NONEMPTY: OPEN.**

**الملفات (غير مدمجة):** `lib/src/services/encrypted_account_list_cache.dart`؛ جديد `test/lists/offline_lists_verified_reuse_test.dart`؛ جديد `test/perf/main_isolate_probe_test.dart` (أداة §7AU + قياس جواب الخادم)؛ وهذا الملف.

**الحالة:** **P4.7c (C) = CODE_PROVEN.** **NOW:** مراجعة المالك ثم موافقة commit. **NEXT (اقتراح):** Q-1 (Quotations: ترقيم + إبقاء القائمة) أولوية صحة؛ ثم قياس Samsung لتقرير P4.7c-2 (A) وP4.7d. **STOP:** لا A/B/P4.7d/Quotations تلقائياً؛ لا commit/push.

## 7AV) Q-1a — ترقيم قائمة Quotations وموثوقية التحديث — 2026-11-06 (CODE_PROVEN؛ غير مدمج)

**Git:** `perf/phase-1-startup-baseline` @ `9a31d7b` = `origin`؛ ملفات plugin الثلاثة وstashes الاثنان و`docs/ADD_DETAILS_*` لم تُلمس.

### الفحص (S — من الهجرات والمصدر)
- **الجدول:** `public.quotations` — `id uuid primary key`، `owner_id uuid not null`، `created_at timestamptz not null`، `deleted_at timestamptz`، فهرس `(owner_id, created_at desc)` ⇒ **الشكل نفسه للقوائم الست** ⇒ مفتاح keyset `(created_at desc, id desc)` فريد وكلي.
- **RLS:** `quotations_select_own` = `owner_id = auth.uid()` + **بوابة `app_session_gate` المقيِّدة** (SAD؛ `20261005175500`) ⇒ الجلسة المُزاحة تُجاب بلا صفوف (كالقوائم الست). الحذف: `deleted_at` يُرشَّح في الطلب.
- **السبب الجذري للقص:** `listQuotations` = طلب **واحد بلا `limit` ولا عدّ** ⇒ يُقص بصمت عند `max_rows` المستضاف (1,000، §7AL). **(M)** قبل: 1,200 / 5,000 / 10,000 عرض سعر ⇒ **1,000 فقط، طلب واحد، بلا خطأ.**
- **السبب الجذري لاختفاء القائمة:** `StreamBuilder` في `list_quotation_view.dart` يفحص `hasError` قبل البيانات، و`StreamBuilder` **يُسقط بياناته عند حدث خطأ** ⇒ فشل إعادة القراءة (بعد أي تعديل كيان) يستبدل القائمة المعروضة بحالة الخطأ (مُثبت باختبار §7AS).
- **فراغ بلا تأكيد:** لا تأكيد جلسة لقائمة فارغة (جلسة مُزاحة ⇒ «لا عروض أسعار» كاذبة).
- **الحسابات/PDF:** القائمة تقرأ أعمدة البطاقة فقط (`listColumns`)؛ الحسابات في `AddQuotationViewModel`/`aggregateFromRow` وPDF في `pdf_generation_service`/`QuotationPdfCache` — **لم تُلمس**.

### التنفيذ (أصغر تغيير؛ لا SQL/RLS/Auth/SAD/حسابات/PDF/واجهة)
1. **`lib/src/services/supabase_core_entities_service.dart`:** طريقة عامة واحدة `readWholeOwnedList(table, columns, {stillWanted})` **تفوّض حرفياً إلى `_wholeList`** (P4: 500/صفحة، `count=exact` في الأولى، مؤشر keyset بالنص الخام، 40 صفحة / 20,000، `badPage`/`missingCount`/`tooLarge`/`changedDuringRead`، تأكيد الجلسة + عدّ HEAD عند عدم التطابق، `ListSessionNotCurrent` عند تغيّر الحساب/الجلسة) — **لا تغيير في منطق P4**.
2. **`…/quotation/services/supabase_quotation_service.dart`:** `listQuotations()` (العقد العام بلا تغيير) ⇒ `_listQuotations(stillWanted)`: القارئ المرقّم على **العميل نفسه** (مُنشأ عند الاستخدام الأول مع مساعد وسائط على العميل نفسه — لا `Supabase.instance`)؛ **قائمة فارغة ⇒ تأكيد جلسة واحد** (`ListSessionCheck.confirmFor`) وإلا `ListSessionNotCurrent`؛ الأخطاء تمر عبر `_translate` القائم (الشبكة ⇒ `network`، الباقي ⇒ `unknown`). `watchQuotations` يمرّر `() => controller.hasListener` ⇒ **شاشة مغلقة لا تقرأ صفحة أخرى**. الفلتر صار يتضمن `owner_id = <الحساب>` صراحة (مطابق لسياسة RLS).
3. **`…/quotation/list_quotations_viewmodel.dart`:** محوّل على تدفق القائمة: **قبل أول قائمة** الخطأ يصل للشاشة كما كان (حالة الخطأ القائمة)؛ **بعدها** يُبقى المعروض ولا يُستبدل بحالة الخطأ — كقاعدة القوائم الست (`EntityListState`)؛ القائمة التالية (أو فارغة موثوقة) تحل محله. **`list_quotation_view.dart` بلا تغيير.**

### القياس (M — محاكي PostgREST حتمي بحد `max_rows`=1000، VM الاختبار؛ ليس شبكة مستضافة ولا Samsung)
| عروض الأسعار | قبل: المُعاد / الطلبات | بعد: المُعاد / الطلبات / بايتات الجسم |
|---|---|---|
| 0 / 1 / 100 | كلها / 1 | كلها / 1 (+ تأكيد جلسة عند 0) |
| 500 / 501 | كلها / 1 | كلها / 1 / 2 |
| 1,000 | 1,000 / 1 | 1,000 / 2 / 451 KB |
| 1,200 | **1,000 بصمت** / 1 | **1,200 / 3** / 541 KB |
| 5,000 | **1,000 بصمت** / 1 | **5,000 / 10** / 2.26 MB |
| 10,000 | **1,000 بصمت** / 1 | **10,000 / 20** / 4.52 MB |
| > 20,000 | 1,000 بصمت | **فشل `tooLarge` بعد طلب واحد** (لا قائمة جزئية) |
- زمن القراءة في المحاكي (VM): 10,000 ⇒ ~1.1 s (يشمل كلفة المحاكي) — **ليس زمن شبكة**. البناء (القائمة غير lazy، بلا تغيير): 18 / 42 / 84 ms لـ 100 / 500 / 1,000 بطاقة. **عرض فشل التحديث:** قبل ⇒ حالة الخطأ تستبدل القائمة؛ بعد ⇒ **القائمة باقية** (`list kept: true; error shown: false`).
- **التكلفة الجديدة المقصودة:** القائمة الآن كاملة ⇒ طلبات وذاكرة تتناسب مع العدد الحقيقي (حتى 20,000) بدل سقف 1,000 صامت.

### الأدلة (شغّلها الوكيل بتفويض هذه المهمة)
- **أحمر أولاً:** `quotation_list_pagination_test` على الكود دون تغيير ⇒ 1,200/5,000/10,000 ⇒ 1,000 فقط وإخفاقات متعددة؛ `quotation_list_refresh_test` على VM الـ HEAD ⇒ إخفاق «فشل التحديث يُبقي القائمة».
- **جديد `test/quotation/quotation_list_pagination_test.dart` — 26/26:** 0/1/499/500/501/1,000/1,200/10,000 ⇒ كلها وبالترتيب وعدد الطلبات المتوقع (1/1/1/1/2/2/3/20) وكل طلب بـ `owner_id` و`deleted_at=is.null` و`created_at.desc`+`id.desc` و`limit=500` بلا الجداول الفرعية، والأول `count=exact`؛ أوقات متطابقة عبر حدود الصفحات ⇒ كل سجل مرة؛ المحذوف وصفوف حساب آخر لا تُعرض؛ **حقول البطاقة كما كانت** (العنوان، `totalAmount`، الأقساط، العملة، المكتب، `hasPdf`، الإصدار)؛ > 20,000 ⇒ رفض بعد طلب واحد؛ صف مكرر ⇒ رفض؛ عدّ مفقود/`*`/تالف ⇒ رفض؛ فشل الصفحة 2 ⇒ `network` بلا قائمة؛ حذف بين الصفحات ⇒ عدّ HEAD و1,199؛ فارغة ⇒ تأكيد واحد (true يُقبل، false يُرفض، null يُقبل)، غير فارغة ⇒ بلا تأكيد؛ **حساب آخر / الحساب نفسه بجلسة جديدة بعد الصفحة 1 ⇒ لا صفحة 2 ولا قائمة**؛ جلسة مُزاحة (صفحات فارغة) ⇒ رفض؛ **إغلاق الشاشة أثناء الصفحة 1 ⇒ لا صفحة 2**؛ فشل إعادة قراءة ⇒ حدث خطأ والتدفق يستمر ثم يتعافى (يشمل إعادات عميل PostgREST التلقائية لـ GET)؛ قياسات.
- **جديد `test/quotation/quotation_list_refresh_test.dart` — 5/5** (الشاشة الحقيقية): فشل بعد قائمة ⇒ القائمة باقية بلا حالة خطأ ولا مؤشر تحميل؛ فشل قبل أي قائمة ⇒ حالة الخطأ القائمة؛ بعد الفشل القائمة التالية تحل محلها؛ فارغة موثوقة ⇒ حالة الفراغ؛ التحديث بلا مؤشر واشتراك واحد.
- **حُدِّث عمداً:** `supabase_quotation_service_test` «the list is live rows only…» — الجواب يحمل `content-range` (مطلوب للعدّ الدقيق) + توقعات `owner_id` و`id.desc` و`limit=500` و`count=exact` (كل التوقعات القديمة باقية)؛ `test/perf/list_open_baseline_test` Part 4 — كان يوثّق الخلل، صار يثبت الإصلاح.
- **الطفرات 5/5 التُقطت** (الملفات أُعيدت، SHA-256 مطابق): بلا تأكيد الفراغ؛ الشاشة المغلقة تواصل القراءة؛ فشل التحديث يستبدل القائمة؛ إخفاء الفشل الأول؛ جدول خاطئ (**نجت أولاً لأن المحاكي قبل أي مسار يبدأ بـ `quotations` ⇒ شُدّد المحاكي ليطابق المسار حرفياً ثم التُقطت**).
- **انحدار مركّز:** `test/quotation` كاملاً (**الحسابات** `add_quotation_viewmodel_test`، **PDF/الوسائط** `quotation_service_test`/`quotation_media_workflow_test`/`r2_quotation_media_service_test`، المُحوِّل، الحفظ، إزالة الإرث) + `entity_keyset_pagination_test` + `requests_keyset_pagination_test` + `list_row_cap_characterization_test` + `test/home` + `test/perf` ⇒ **688/688**. بعد التنسيق: الملفات الثلاثة المعنية ⇒ **53/53**.
- **Analyzer** (7 ملفات) ⇒ No issues. **Format 3.5:** `supabase_quotation_service.dart` 22 انحرافاً سابقاً = 22 (لا جديد)؛ البقية 0؛ الاختباران الجديدان مُنسّقان. **`git diff --check`** نظيف؛ CRLF.

### الحدود الباقية
- **غير مُتحقَّق مستضافاً:** ترقيم Quotations على PostgREST الحقيقي — يُضاف إلى **P4.3-ACCEPT-NONEMPTY (OPEN)**؛ أداة P4.3b لم تُوسَّع لـ Quotations.
- **إعادة قراءة مع كل تعديل كيان:** `CoreEntityMutationNotifier` بلا نوع ⇒ تعديل Owner/Offer يعيد قراءة Quotations كاملة (صار أثقل مع اكتمالها) ⇒ **Q-1b (اقتراح):** إشعار بنوع الكيان.
- **مسار عدّ Home القديم** (`home_viewmodel` يقرأ `getUserQuotations().first` لعدّ) ⇒ صار كاملاً ومرقّماً إن استُخدم؛ العدّ الحالي في Home عبر HEAD (P3.3).
- القائمة غير lazy (`Column`) — رخيصة حتى 1,000 (84 ms)؛ للآلاف تُقاس لاحقاً.
- **Quotations Offline-First غير مُنفَّذ** (لا نسخة محلية؛ offline ⇒ حالة الخطأ أول مرة): يحتاج قرار أمان/منتج (كاش مشفّر للحساب على نواة P2، ربط PDF المحلي، الحسابات تبقى على الخادم).
- لا قياس Samsung/شبكة حقيقية. **P4.3-ACCEPT-NONEMPTY: OPEN.**

**الملفات (غير مدمجة):** `lib/src/services/supabase_core_entities_service.dart`؛ `lib/src/views/Screens/home/quotation/services/supabase_quotation_service.dart`؛ `lib/src/views/Screens/home/quotation/list_quotations_viewmodel.dart`؛ جديد `test/quotation/quotation_list_pagination_test.dart`؛ جديد `test/quotation/quotation_list_refresh_test.dart`؛ `test/quotation/supabase_quotation_service_test.dart`؛ `test/perf/list_open_baseline_test.dart`؛ وهذا الملف.

**الحالة:** **Q-1a = CODE_PROVEN — STAGING_UNVERIFIED، REAL_DEVICE_UNVERIFIED.** **NOW:** مراجعة المالك ثم موافقة commit. **NEXT (اقتراح):** Q-1b (إشعار تعديل بنوع الكيان) أو توسيع P4.3-ACCEPT-NONEMPTY لـ Quotations. **STOP:** لا Quotations Offline/P4.7d/وسائط تلقائياً؛ لا commit/push؛ Samsung DEFERRED.

### مراجعة تجربة فشل التحديث — 2026-11-06 (CODE_PROVEN؛ غير مدمج)
- **التحميل الأول الفاشل** (لا قائمة): حالة الخطأ القائمة كما كانت (`quotationListLoadFailed`) — مُثبت.
- **فشل تحديث والقائمة معروضة:** القائمة باقية — مُثبت. **لكن (خلل UX حقيقي في Q-1a كما سُلّم):** المحوّل كان **يبتلع الخطأ بصمت** — لا أي إشارة للمستخدم (السلوك نفسه في القوائم الست عبر `EntityListState`، وهو خارج هذا النطاق).
- **الإصلاح الأصغر (إعادة استخدام آلية قائمة، بلا تصميم ولا نص جديد):** الشاشة تستخدم أصلاً **toast أحمر** (`_showToast`، Fluttertoast) لأخطاء PDF/الحذف، والنص `quotationListLoadFailed` موجود (EN/AR). ⇒ `QuotationListViewModel.onRefreshFailed` (تضبطه الشاشة عند إنشاء الـ VM) يُستدعى عند فشل إعادة قراءة **بعد** أول قائمة؛ الشاشة تعرض الـ toast بالنص القائم **فقط إن كانت المسار الظاهر** (`ModalRoute.isCurrent` — إعادات القراءة تتبع تعديلات على شاشات أخرى، مثل حفظ عرض سعر في شاشة الإضافة فوقها). **مرة واحدة لكل سلسلة فشل** (لا تكرار)؛ قراءة ناجحة تعيد التسليح؛ فشل تحت شاشة أخرى لا يُعدّ «قيل» ⇒ الفشل التالي على الشاشة يقوله. التحميل الأول الفاشل: حالة الخطأ وحدها، بلا toast.
- **الملفات:** `list_quotations_viewmodel.dart` (الحقل + منطق المرة الواحدة)؛ `list_quotation_view.dart` (ربط `onRefreshFailed` في `create` + `_refreshFailed` بفحص المسار، يستعمل `_showToast` القائم). البطاقات/الترتيب/التنقل/الحسابات/PDF/فحوص الحساب والجلسة/عقد P4 بلا تغيير.
- **الأدلة:** `quotation_list_refresh_test` **7/7** (+2: «يُقال مرة بالـ toast القائم، لا تكرار في السلسلة، ويُقال ثانية بعد نجاح»، «تحت شاشة أخرى لا يُقال، وبعد العودة يقوله الفشل التالي»، + التحميل الأول الفاشل بلا toast). **طفرات 3/3 التُقطت** (toast لكل فشل؛ بلا فحص المسار؛ بلا إعادة تسليح بعد النجاح) — الملفان أُعيدا بـ SHA-256 مطابق. **المتأثر:** `test/quotation` كاملاً + `test/perf/list_open_baseline_test` ⇒ **232/232**. Analyzer (3 ملفات) ⇒ No issues؛ Format 3.5: الـ VM 0؛ الشاشة 20 سابقة = 20؛ `git diff --check` نظيف؛ CRLF.
- **حدّ موثّق (قرار منتج منفصل، لم يُنفَّذ):** القوائم الست ما زالت تُبقي القائمة **بصمت** عند فشل التحديث (`EntityListState`) — توحيد الإشارة عبر الشاشات السبع قرار تصميم/منتج.

---

## 7AW) Q-1b — تحديث Quotations بحسب نوع الكيان — 2026-11-07 (CODE_PROVEN؛ غير مدمج)

**Git (مُتحقَّق قبل البدء):** `perf/phase-1-startup-baseline` @ `f717951` = `origin` (0/0 بعد `git fetch`)؛ stashes الاثنان باقيان؛ ملفات plugin الثلاثة و`docs/ADD_DETAILS_*` لم تُلمس.

### تدقيق الاعتماديات (S — من المصدر والهجرات)
- **ما تقرأه القائمة:** `listColumns` = أعمدة `quotations` وحدها (العنوان، النوع، التاريخ، `total_amount`، الأقساط، `office_name`، العملة، `office_logo_media_id`، `pdf_media_id`، الإصدار، الأوقات) — **بلا مورد مضمَّن ولا join**؛ كل طلب القائمة إلى `/rest/v1/quotations` فقط (مُثبت باختبار).
- **الجدول:** `public.quotations` يشير فقط إلى `profiles(id)`؛ **لا FK** إلى requests/offers/owners/offices/brokers/watchmen؛ `office_name` **نص محفوظ في عرض السعر** (ليس مرجعاً لـ `offices`). المحفّزات على `quotations`: `bump_sync_version` و`validate_direct_media_ownership` فقط؛ **لا محفّز على الجداول الست يكتب `quotations`**. كتابة `quotations` تأتي فقط من `save_quotation` و RPC وسائط Quotation و soft delete — وكلها عبر `QuotationService` في العميل.
- **مصادر الإشارة (`CoreEntityMutationNotifier.notify`):** 12 حفظ/تعديل + 6 حذف (عبر `_softDeleteAndNotify`) في `SupabaseCoreEntitiesService` للأنواع الست؛ إشارتان في `QuotationService` (المفردة والمجمّعة: حفظ، شعار، PDF، حذف). **لا مصدر آخر في `lib/`.**
- **الحسابات/PDF:** الحسابات في `AddQuotationViewModel`/`aggregateFromRow` والـ PDF في `pdf_generation_service`/`QuotationPdfCache` لا تقرأ أي كيان من الست (`AddQuotationViewModel` لا يقرأ `offices`)؛ `hasPdf` يُشتق من `pdf_media_id` على الصف نفسه.
- **الخلاصة:** تعديل أي نوع من الست **لا يمكن أن يغيّر** أي حقل تعرضه قائمة Quotations ⇒ إعادة القراءة بعده عمل ضائع. **لا اعتماد كيان مرتبط يجب حفظه.** تغيّر الجلسة/الحساب لا يمر عبر هذه الإشارة أصلاً (يبقى كما كان: فحوص الجلسة في القارئ + `AppSessionCoordinator`).
- **تحديث صريح:** الشاشة بلا سحب للتحديث ولا lifecycle resume؛ المسار الصريح الوحيد `QuotationListViewModel.refreshQuotations()` (تدفق جديد ⇒ قراءة كاملة) — بلا تغيير.

### التنفيذ (4 ملفات إنتاجية؛ لا SQL/RLS/Auth/SAD/حسابات/PDF/مسارات ملفات/عقود CRUD/واجهة/تبعيات)
1. **`lib/src/services/core_entity_mutation_notifier.dart`:** `enum CoreEntityKind {request, offer, owner, office, broker, watchman, quotation}`؛ `notify([CoreEntityKind? kind])` (الإشارة بلا نوع = «قد يكون أي شيء»)؛ **`changes` بلا تغيير** (كل إشارة لكل المستمعين: القوائم الست، أعداد Home، Search، Map)؛ جديد `changesTo(kind)` = إشارات ذلك النوع **+ الإشارات بلا نوع** (افتراض آمن). التسليم متزامن كما كان.
2. **`lib/src/services/supabase_core_entities_service.dart`:** كل `notify()` صار `notify(CoreEntityKind.<نوع الطريقة>)`؛ `_softDeleteAndNotify(table, id, kind)`. **منطق القوائم الست/الحذف/P4 بلا تغيير** (القوائم الست ما زالت تستمع لـ `changes` كلها).
3. **`…/quotation/services/quotation_service.dart`:** الإشارتان ⇒ `CoreEntityKind.quotation` (التجميع بلا تغيير).
4. **`…/quotation/services/supabase_quotation_service.dart`:** `watchQuotations` يستمع إلى `changesTo(CoreEntityKind.quotation)` بدل `changes`. حلقة القراءة الواحدة (`reading`/`readAgain`)، `stillWanted`، ترقيم Q-1a، معالجة الفشل وtoast المرة الواحدة **بلا تغيير**.

### عدد الطلبات (M — محاكي PostgREST حتمي، `max_rows`=1000، VM الاختبار؛ ليس شبكة مستضافة ولا Samsung)
السيناريو: فتح القائمة؛ ستة تعديلات منفصلة (حذف Request ثم Offer ثم Owner ثم Office ثم Broker ثم Watchman، كلٌّ يستقر)؛ ثم حذف Quotation واحد.

| عروض الأسعار | الفتح | بعد الستة — قبل | بعد الستة — بعد | حذف Quotation (قبل = بعد) |
|---|---|---|---|---|
| 0 | 1 | 6 طلبات / 12 B | **0 / 0 B** | 1 |
| 3 | 1 | 6 / 7,986 B | **0 / 0 B** | 1 |
| 1,200 | 3 | 18 / 3,247,776 B | **0 / 0 B** | 3 |
| 10,000 | 20 | **120 / 27,113,484 B** | **0 / 0 B** | 20 |
- «قبل» = الكود عند `f717951` بالاختبار نفسه (تشغيل أحمر)؛ «بعد» = بعد Q-1b. إشارات كثيرة أثناء قراءة: **قبل** إشارات الست وحدها ⇒ قراءة إضافية كاملة؛ **بعد** ⇒ لا شيء؛ إشارات Quotation متعددة ⇒ قراءة إضافية **واحدة** (قبل = بعد).

### الأدلة (شغّلها الوكيل بتفويض هذه المهمة)
- **أحمر أولاً:** `quotation_list_type_aware_refresh_test` على الكود دون تغيير ⇒ **13 إخفاقاً** (كلها قراءات بعد أنواع أخرى أو إشارات بلا نوع)؛ اختبارات الحفظ (إنشاء/تعديل/حذف، التجميع، الإشارة بلا نوع، إشارات متعددة، التحديث الصريح، الإغلاق، تبديل الحساب أثناء القراءة) نجحت على الـ HEAD = **سلوك محفوظ**.
- **جديد `test/quotation/quotation_list_type_aware_refresh_test.dart` — 23/23** (مصدرو الإشارة الحقيقيون على عميل واحد): القائمة تقرأ `quotations` وحدها؛ كل مصدر في `lib/` يسمّي نوعه، كل حفظ/تعديل/حذف من الست يسمّي **نوعه هو**، إشارتا Quotation = `quotation`؛ حذف من الأنواع الست ⇒ **0** قراءة (1,200 صف)؛ إنشاء/تعديل/حذف Quotation ⇒ قراءة كاملة لكل منها بالحقول الجديدة؛ حفظ مجمّع ⇒ قراءة واحدة؛ إشارة بلا نوع ⇒ قراءة؛ 3 حذف Quotation + 6 أنواع أخرى أثناء قراءة ⇒ قراءة إضافية واحدة؛ أنواع أخرى فقط أثناء قراءة ⇒ لا شيء؛ التحديث الصريح ⇒ قراءة كاملة؛ فشل إعادة القراءة ⇒ القائمة باقية، toast مرة لكل سلسلة، النجاح يعيد التسليح، الأنواع الأخرى لا تسبب قراءة/فشلاً؛ فشل أول تحميل ⇒ حالة الخطأ بلا toast؛ جلسة مُزاحة ⇒ رفض بعد إشارة Quotation فقط، بلا فراغ كاذب، بلا فحص جلسة بعد الأنواع الأخرى؛ حساب آخر ⇒ لا قراءة بعد الأنواع الأخرى، وقراءته هو (`owner_id=eq.B`) بعد إشارة Quotation؛ تبديل الحساب أثناء قراءة مرقّمة ⇒ لا صفحة 2 ولا نتيجة متأخرة؛ خروج ⇒ لا طلب، ثم الحساب نفسه بجلسة جديدة ⇒ قراءة بعد Quotation فقط؛ إغلاق الشاشة ⇒ لا قراءة أياً كانت الإشارة، وإغلاق أثناء قراءة ⇒ لا صفحة تالية؛ حقول البطاقة كما كانت؛ قياسات.
- **جديد `test/services/core_entity_mutation_notifier_test.dart` — 5/5:** `changes` يسلّم كل الأنواع + بلا نوع؛ `changesTo(quotation)` يسلّم Quotation وبلا نوع فقط؛ أي نوع آخر بالمثل؛ التسليم متزامن؛ المستمع الملغى لا يستلم.
- **الطفرات 8/8 التُقطت** (كل ملف أُعيد بـ SHA-256 مطابق، ومُتحقَّق بـ `sha256sum -c`): M1 القائمة تستمع لكل الإشارات (7 إخفاقات)؛ M2 الفلتر يُسقط الإشارة بلا نوع (3)؛ M3 الفلتر يمرّر كل شيء (8)؛ M4 إشارة Quotation المفردة بنوع Office (11)؛ M5 الإشارة المجمّعة بنوع Office (2)؛ M6 حذف Owner بنوع Quotation (7)؛ M7 مساعد الحذف يتجاهل نوعه (8)؛ M8 `saveOffice` بنوع Offer (1 — يلتقطه اختبار المصدر وحده، إذ لا أثر سلوكي له على Quotations).
- **انحدار مركّز — 1,889/1,889:** `test/quotation` كاملاً (**الحسابات** `add_quotation_viewmodel_test`، **PDF/الوسائط** `quotation_service_test`/`quotation_media_workflow_test`/`r2_quotation_media_service_test`، ترقيم Q-1a، toast Q-1a، المُحوِّل، إزالة الإرث) + `test/services/core_entity_mutation_notifier_test` + `test/lists` كاملاً (القوائم الست، الحذف المؤكَّد، تدفق التحديث، الكاش) + `test/home` + `test/search` + كل اختبارات `test/map` التي تستخدم الإشارة + `favorites_request_count_test` + `offer_media_save_test` + `owner_media_test` + `related_items_service_test` + `r2_search_favorites_responsive_test` + `test/perf/list_open_baseline_test`. بعد آخر تعديل (مسافات/import فقط) أُعيد الملفان الجديدان ⇒ **28/28**.
- **Analyzer** (6 ملفات) ⇒ No issues. **Format 3.5:** الملفات الإنتاجية 0 / 0 / 0 / 22 سابقة = الـ HEAD (لا جديد)؛ الاختباران الجديدان مُنسّقان. **`git diff --check`** نظيف؛ CRLF.

### السلوك المحفوظ
قراءة كاملة بعد إنشاء/تعديل/شعار/PDF/حذف Quotation؛ الإشارة المجمّعة الواحدة للحفظ؛ قراءة واحدة في كل مرة + قراءة إضافية واحدة لما وصل أثناءها؛ التحديث الصريح؛ ترقيم Q-1a (500/صفحة، عدّ دقيق، 20,000) وتأكيد الفراغ؛ إبقاء القائمة عند الفشل وtoast المرة الواحدة؛ حالة الخطأ لأول تحميل؛ فحوص الحساب/الجلسة بين الصفحات (`ListSessionNotCurrent`)؛ إيقاف القراءة عند إغلاق الشاشة؛ القوائم الست وأعداد Home وSearch وMap تستمع لكل الإشارات كما كانت؛ عدّ Home القديم عبر `getUserQuotations().first` بلا تغيير.

### الحدود الباقية
- **الإشارة محلية للعملية فقط** (كما كانت): تغييرات من جهاز آخر لا تصل إلى القائمة حتى إعادة فتحها — لا تغيير.
- **أثر جانبي مقصود:** قبل Q-1b كان تعديل كيان آخر يعيد قراءة Quotations «مجاناً» بعد فشل تحديث سابق (فيتعافى) أو يكتشف جلسة مُزاحة؛ الآن التعافي يحدث بأول تعديل Quotation أو بإعادة فتح الشاشة، والجلسة المُزاحة يكتشفها `AppSessionCoordinator` وبقية الشاشات كما كان.
- **الإشارة بلا نوع ما زالت تعيد القراءة** (افتراض آمن)؛ لا يوجد مصدر كهذا في `lib/` اليوم، واختبار المصدر يمنع إضافته دون نوع.
- **غير مُتحقَّق مستضافاً ولا على Samsung:** يُضاف **D-55** إلى §7N؛ ترقيم Quotations المستضاف ما زال ضمن **P4.3-ACCEPT-NONEMPTY (OPEN)**.

**الملفات (غير مدمجة):** `lib/src/services/core_entity_mutation_notifier.dart`؛ `lib/src/services/supabase_core_entities_service.dart`؛ `lib/src/views/Screens/home/quotation/services/quotation_service.dart`؛ `lib/src/views/Screens/home/quotation/services/supabase_quotation_service.dart`؛ جديد `test/quotation/quotation_list_type_aware_refresh_test.dart`؛ جديد `test/services/core_entity_mutation_notifier_test.dart`؛ وهذا الملف.

**الحالة:** **Q-1b = CODE_PROVEN — STAGING_UNVERIFIED، REAL_DEVICE_UNVERIFIED.** **NOW:** مراجعة المالك ثم موافقة commit (المالك يدفع). **NEXT (مرحلة منفصلة تحتاج موافقة):** **Q-2 — نسخة Quotations المحلية المشفّرة (Offline)** — تصميم وموافقة أمان/منتج أولاً؛ الحسابات وPDF ومسارات الملفات محمية. **STOP:** لا Q-2 تلقائياً؛ لا commit/push؛ Samsung DEFERRED.

---

## 7AX) Q-2a — تصميم Quotations Offline-First وفحص أمني مسبق — 2026-11-07 (DESIGN؛ لا تغيير كود؛ ينتظر موافقة المالك)

**Git (مُتحقَّق):** `perf/phase-1-startup-baseline` @ `2a75427` = `origin` (0/0 بعد `git fetch`)؛ stashes الاثنان باقيان؛ ملفات plugin الثلاثة و`docs/ADD_DETAILS_*` لم تُلمس. **هذا القسم وحده تغيّر.**

### 1) تدقيق البيانات (S — من المصدر والهجرات)
- **مسار القائمة اليوم:** `QuotationListViewModel` ← `QuotationService.getUserQuotations()` ← `SupabaseQuotationService.watchQuotations()` (Q-1a ترقيم كامل؛ Q-1b `changesTo(quotation)`) ⇒ **خادم فقط، لا نسخة محلية**؛ offline ⇒ حالة الخطأ في أول فتح. `getUserQuotations().first` يستعمله أيضاً مسار عدّ Home القديم (`home_viewmodel.dart:441`).
- **التفاصيل = نموذج التعديل:** النقر ⇒ `/add-quotation?mode=edit&id=<id>` ⇒ `AddQuotationViewModel.loadForEdit()` ⇒ `getQuotationById` (التجميع كاملاً من الخادم) + اسم الشعار وروابط موقّعة. offline ⇒ حالة `loadFailed` القائمة. **لا يستعمل نموذج القائمة إلا `id`.**
- **الحسابات:** `totalAmount` وبقية المبالغ **قيم يدخلها المستخدم** في `AddQuotationViewModel` وتُرسل كما هي إلى `save_quotation`؛ الخادم يحفظها ويفرض القيود (`numeric(14,2)`، غير سالبة، الأقساط > 0، العملة كبيرة). **لا مبلغ يُشتق في القائمة**؛ `AdministrativeFees.total` وحده يُحسب عند إعادة الفتح (مجموع البنود) — في التفاصيل لا في القائمة.

**تصنيف الحقول** (القائمة تقرأ `listColumns` الـ 14 فقط):

| الحقل | البطاقة | التفاصيل | مالي | مشتق | من الخادم | PDF/وسائط | يُحفظ محلياً (اقتراح) |
|---|---|---|---|---|---|---|---|
| `id` | مفتاح/تنقل | نعم | — | — | نعم | — | **نعم** |
| `owner_id` → `userId` | فحص الحساب | — | — | — | نعم | — | **نعم** (فحص الملكية) |
| `property_title` | نعم | نعم | — | — | نعم | في PDF | **نعم** |
| `property_type` | نعم | نعم | — | — | نعم | في PDF | **نعم** |
| `display_date` | نعم | نعم | — | — | نعم | في PDF | **نعم** |
| `total_amount` | نعم (`aed` + `toStringAsFixed(2)`) | نعم | **نعم** | لا (مُدخل) | نعم | في PDF | **نعم — قرار D-Q1** |
| `number_of_installments` | نعم | نعم | **نعم** | لا | نعم | في PDF | **نعم — D-Q1** |
| `currency_code` | لا (البطاقة تعرض `aed` ثابتاً) | نعم | **نعم** | لا | نعم | في PDF | **نعم — D-Q1** (المبلغ بلا عملته بيانات ناقصة) |
| `office_name` | نعم | نعم | — | — | نعم (نص محفوظ) | في PDF | **نعم** |
| `pdf_media_id` | `hasPdf` + فتح/مشاركة | — | — | — | نعم (RPC وسائط) | **نعم** | **نعم — قرار D-Q2** |
| `office_logo_media_id` | لا | الشعار | — | — | نعم | **نعم** | **لا** |
| `version` | لا | التحرير (يُقرأ من الخادم) | — | — | نعم | — | **لا** |
| `created_at` / `updated_at` | ترتيب/النموذج يتطلبهما | — | — | — | نعم | — | **نعم** (المُنشئ يتطلبهما؛ هوية الترتيب) |
| بقية التجميع: `professional_fee`، `insurance_*`، `payment_type`، الدفعات، الرسوم الحكومية/الإدارية، `custom_note`، رسالة الترحيب، `subtitle`، `parking`، تواريخ البداية/النهاية | — | نعم | **نعم** (أغلبها) | `admin total` | نعم | في PDF | **لا — لا تقرأها القائمة أصلاً** |
| `officeLogoUrl`، روابط موقّعة، مسارات ملفات | — | عرض مؤقت | — | — | — | — | **لا أبداً** |

### 2) التصميم الأمني — أصغر امتداد للنواة القائمة (لا نظام تشفير جديد)
- **`QuotationsLocalCache extends EncryptedAccountListCache<QuotationModel>`** (نسخة من نمط `OfficesLocalCache`، ~60 سطراً): `boxPrefix = 'cached_quotations_'`، مفتاح `quotations_cache_key_v1_<uid>` (`SecureAccountCacheKeyStore`: Keystore/Keychain)، `listKey = 'quotations_v1'`، `ownerOf = userId`، `idOf = id`، encode/decode **للحقول الـ 12 الموسومة «نعم» فقط**.
- **موروث كما هو بلا تعديل:** AES-256 لكل حساب؛ غلاف v2 مُصادَق (HMAC، D-3)؛ مجلد `app_flutter/offline_lists` المستثنى من النسخ الاحتياطي ونقل الجهاز (Android — القاعدة قائمة، **لا تغيير XML**)؛ D-1a نقل الصندوق القديم (لا يوجد صندوق قديم)؛ D-2 الاستعادة بعد قراءة خادم مُعتمدة فقط؛ فشل مغلق عند مفتاح مفقود/خاطئ/صندوق تالف (لا قراءة ولا كتابة)؛ حجب السلامة لعلامات تالفة؛ إسقاط سجلات حساب آخر عند الحفظ والقراءة.
- **`localFirstList`** يوفّر الباقي حرفياً: النسخة المحفوظة **للحساب المسجّل فقط**؛ كل جواب مربوط **بجلسة بدء القراءة** (خروج ثم دخول — ولو للحساب نفسه — ⇒ الجواب المتأخر يُسقط ولا يُحفظ والقائمة تتوقف)؛ **القائمة الفارغة لا تُقبل ولا تُحفظ إلا بعد تأكيد الجلسة** (الجلسة المُزاحة تُجاب بلا صفوف)؛ قائمة الخادم تستبدل المحفوظة كاملة (الفارغة الموثوقة تُحفظ فارغة)؛ لا شيء يُحفظ عند الفشل (فشل الصفحة 2 ⇒ لا قائمة ⇒ المحفوظة كما هي)؛ وقت آخر قراءة (`serverReadAt`، P2.5c) مؤشر لا سلطة.
- **SAD والإقلاع البارد:** بلا تغيير — شاشة Quotations لا تُبلغ قبل بوابة الجلسة (الإقلاع البارد offline يتوقف عند Retry كما في P1)؛ الكاش ليس سلطة وصول.
- **فحص التصادم (S):** لا `cached_quotations_` ولا `quotations_cache_key` في `lib/` ولا في تاريخ git (`git log -S` فارغ)؛ بادئات الست + Favorites مختلفة؛ صناديق Hive الأخرى (`pending_uploads`، `local_media`، `local_profile`، `pending_profile_uploads`، analytics، offline_data) لا تتقاطع؛ ملفات PDF `quotation_<id>_<mediaId>.pdf` في **جذر** المستندات و`QuotationPdfCache` يمسح الجذر بلا تعمّق ⇒ لا تقاطع مع `offline_lists/`.
- **Delete Account:** `DeletedAccountLocalDataCleaner` يمسح كاش الست بـ `forgetAccount` ⇒ **Q-2b يضيف سطراً لـ `QuotationsLocalCache`**.
- **فجوة خاصة بـ Quotations (S، حاسمة لـ Q-2b):** `localFirstList` يعيد المحاولة ويستمع لإشارات الاستئناف/الشبكة فقط بعد `isRetryableListError` (Socket/Timeout/Handshake/Http/ClientException). لكن `SupabaseQuotationService._translate` يحوّل فشل الشبكة إلى **`QuotationException(network)`** ⇒ بلا معالجة، **أول فشل شبكة يوقف إعادة المحاولة وإشارات العودة نهائياً** لقائمة Quotations ⇒ **قرار D-Q4**.
- **فجوة الحذف المؤكد (S):** علامات الحذف (P3.1d، لا تُتقاعد أبداً) تُكتب فقط عبر `deleteThenRemember` بعد حذف **أكّده الخادم**. `SupabaseQuotationService.softDelete` يطلب `select('id')` **ويتجاهل النتيجة** (نجاح بلا صف = نجاح — كالست قبل P3.1a) ⇒ علامة بعد حذف غير مؤكد قد تُخفي عرض سعر حياً في النسخة المحلية ⇒ **قرار D-Q3**.

### 3) السلامة المالية
- النسخة المحلية **لقطة تاريخية لقيم خزّنها الخادم**، لا سلطة: لا حساب ولا PDF ولا حفظ ولا تحقق يقرأ منها؛ القيم تُعرض كما أرسلها الخادم (double من `numeric(14,2)`، بلا تقريب جديد؛ البطاقة تبقى `toStringAsFixed(2)`).
- **لا كتابة offline** (لا إنشاء/تعديل/حذف/طابور مزامنة)؛ الحفظ يبقى `save_quotation` مع `expectedVersion` على الخادم.
- **التفاصيل لا تُحمَّل من النسخة المحلية** (نموذج تعديل؛ تحميل لقطة قديمة في نموذج قابل للحفظ = خطر خلط) ⇒ تبقى من الخادم.
- **الإشارة إلى القِدم بلا واجهة جديدة:** فتح offline بنسخة محفوظة ⇒ تُعرض النسخة ثم يأتي فشل القراءة ⇒ **toast Q-1a القائم مرة واحدة** (`quotationListLoadFailed`) — هذا الإشعار الوحيد المتاح دون نص/تصميم جديد ⇒ **قرار D-Q5**. لا ادعاء «حالي» في أي مكان.
- **حقل يحتاج قراراً منفصلاً:** `total_amount` + `number_of_installments` + `currency_code` (D-Q1). البقية المالية **لا تُحفظ** (القائمة لا تقرأها).
- **ملاحظة واجهة (backlog، لا تنفيذ):** البطاقة تعرض `aed` ثابتاً لا `currency_code` — سلوك قائم سابق.

### 4) حدود PDF والتفاصيل (S)
- **مكان الملفات:** `getApplicationDocumentsDirectory()` **الجذر** (`app_flutter/` على Android، Documents على iOS): `quotation_<id>_<mediaId>.pdf` (`QuotationPdfCache`) + ملف التوليد المؤقت `quotation_<id>.pdf` (`pdf_generation_service.dart:244`) قبل `adopt` (قد يبقى إن انقطع الحفظ).
- **غير مشفّرة**؛ **ليست لكل حساب** (المعرّف UUID لا يتصادم، لكن الملف يبقى بعد الخروج/تبديل الحساب)؛ **غير مستثناة من النسخ الاحتياطي** (Android: `backup_rules.xml`/`data_extraction_rules.xml` تستثني مجلدات محددة فقط، الجذر ليس منها؛ iOS: لا `isExcludedFromBackup` لها)؛ **Delete Account لا يحذفها** (المنظِّف لا يذكرها)؛ الحذف من القائمة يحذف نسخة ذلك العرض (`purge`).
- **المحتوى:** PDF يحمل التجميع المالي كاملاً (الرسوم، الدفعات، التأمين، الملاحظات، رسالة الترحيب، اسم/شعار المكتب) ⇒ **أشد حساسية من حقول القائمة**.
- **إعادة الفتح offline:** `resolvePdfFile` يعيد النسخة المحلية **قبل أي شبكة** إن طابقت `pdfMediaId` ⇒ **مع D-Q2 = نعم**، ملف نُزّل سابقاً يُفتح/يُشارك offline تلقائياً (لا كود PDF جديد). `pdfMediaId` قديم (PDF أُعيد توليده من جهاز آخر) ⇒ يُفتح **الإصدار المحلي الأقدم بالضبط** (اسم الملف يحمل المعرّف) — لقطة تاريخية أيضاً.
- **التوصية:** **Q-2b = القائمة فقط.** **Q-2c (منفصل، يحتاج تصميماً وموافقة):** نقل ملفات PDF إلى مجلد لكل حساب (`app_flutter/quotation_pdfs/<uid>/`)، استثناؤه من النسخ (Android XML + iOS)، مسحه في Delete Account (وقرار الخروج)، ترحيل/تنظيف الملفات الجذرية القديمة وملف التوليد المتبقي، وقرار تشفيرها. **تفاصيل offline للقراءة فقط** = واجهة جديدة ⇒ قرار منتج منفصل (Q-2d أو لاحقاً).

### 5) التحديث والأداء
- **الربط:** `QuotationService.watchUserQuotationsLocalFirst()` = `localFirstList(server: _remote.watchQuotations, cache: QuotationsLocalCache(), currentUserId: authRepository.currentUserId)` — مطابق للست. **`getUserQuotations()` يبقى خادماً فقط** (عدّ Home القديم بـ `.first` لا يجوز أن يأخذ النسخة المحلية).
- **Q-1a:** الترقيم وتأكيد الفراغ في `_listQuotations` بلا تغيير؛ فشل أي صفحة ⇒ لا قائمة ⇒ لا حفظ. **ملاحظة قياس:** قائمة فارغة تُؤكَّد مرتين (الخدمة ثم `localFirstList`) ⇒ طلب تحقق جلسة إضافي **فقط لحساب بلا عروض** — يُقاس في Q-2b، لا يُزال دون قرار.
- **Q-1b:** إعادات القراءة بعد تعديل Quotation تمر عبر التدفق نفسه وتُحفظ؛ الأنواع الست لا تسبب قراءة ولا كتابة.
- **التحديث الصريح:** `refreshQuotations()` يعيد إنشاء التدفق ⇒ النسخة المحفوظة ثم الخادم.
- **الاستئناف/عودة الشبكة:** إشارات `ListRefreshSignals` الافتراضية — **تعمل فقط بعد D-Q4**.
- **الخطأ/toast:** محوّل Q-1a في الـ VM بلا تغيير: النسخة المحفوظة تُعدّ «قائمة مُسلّمة» ⇒ فشل لاحق = toast مرة (D-Q5)؛ بلا نسخة وفشل ⇒ حالة الخطأ كما هي.
- **الإغلاق/الحساب/الجلسة:** `localFirstList` (إلغاء، لا قراءة خادم إن أُغلقت الشاشة أثناء قراءة النسخة) + `stillWanted` و`ListSessionNotCurrent` من Q-1a.
- **القوائم الكبيرة:** حتى 20,000 (حد P4). تقدير الحمولة (من قياس Q-1a ~452 B/صف لـ 14 عموداً): **~8–9 MB JSON** مشفّر في مدخل واحد عند 20,000 (Q-1a: 4.52 MB لكل 10,000 صف) — مثل الست (P4.7b/c: تخطي إعادة الكتابة المطابقة، إعادة استعمال الغلاف المُتحقَّق). **لا ادعاء لزمن الإطار الأول** — يُقاس في Q-2b على VM ثم Samsung.

### 6) قرارات المالك المطلوبة
- **D-Q1:** حفظ `total_amount` و`number_of_installments` و`currency_code` (لقطة مالية مشفّرة، للبطاقة) — **توصية: نعم** (البطاقة بدونها ناقصة؛ الحساسية مماثلة لهواتف Owners المحفوظة أصلاً).
- **D-Q2:** حفظ `pdf_media_id` (يفعّل فتح/مشاركة PDF نُزّل سابقاً offline — ملف غير مشفّر موجود أصلاً) — **توصية: نعم**، مع Q-2c لاحقاً لحماية الملفات. البديل: عدم حفظه ⇒ لا شارة PDF offline (يتطلب حيلة في النموذج — غير موصى).
- **D-Q3:** الحذف المؤكد: **(A موصى)** `softDelete` يتحقق من الصف المُعاد (و قراءة «محذوف أصلاً؟» واحدة كـ P3.1a) ثم `deleteThenRemember` ⇒ فشل كان صامتاً يصير toast `quotationDeleteFailed` القائم؛ **(B)** بلا علامات ⇒ عرض سعر محذوف قد يظهر offline حتى أول قائمة خادم ناجحة.
- **D-Q4:** إعادة المحاولة لـ `QuotationException(network)`: **(A موصى)** معامل اختياري إضافي `isRetryable` في `localFirstList` (افتراضه `isRetryableListError` ⇒ الست بلا تغيير سلوكي) تمرّره Quotations؛ **(B)** توسيع `isRetryableListError` نفسه (أبسط لكنه يلمس منطقاً مشتركاً).
- **D-Q5:** فتح offline بنسخة محفوظة ⇒ toast القائم مرة واحدة — **توصية: نعم** (بديل: صامت كالست).
- **D-Q6:** Q-2c لملفات PDF (أعلاه) — **توصية: مرحلة منفصلة بعد Q-2b**.

### 7) ترتيب تنفيذ Q-2b (عند الموافقة؛ لا SQL/RLS/حسابات/PDF/واجهة/تبعيات)
1. اختبارات حمراء أولاً (أدناه).
2. جديد `QuotationsLocalCache` (الحقول الـ 12).
3. D-Q4: معامل `isRetryable` الإضافي في `localFirstList`.
4. `QuotationService.watchUserQuotationsLocalFirst()`؛ `getUserQuotations()` بلا تغيير.
5. `QuotationListViewModel` يغيّر مصدر التدفق فقط (محوّل Q-1a بلا تغيير؛ الشاشة بلا تغيير).
6. D-Q3: حذف مؤكد + `deleteThenRemember`.
7. `DeletedAccountLocalDataCleaner`: `QuotationsLocalCache().forgetAccount`.
8. انحدار مركّز + طفرات + analyzer/format/`git diff --check` + هذا الملف.
**الملفات المتوقعة:** ~5–6 إنتاجية (`quotations_local_cache.dart` جديد، `encrypted_account_list_cache.dart` [معامل إضافي فقط]، `quotation_service.dart`، `supabase_quotation_service.dart` [D-Q3]، `list_quotations_viewmodel.dart` [سطر]، `deleted_account_local_data_cleaner.dart` [سطر]).

### 8) الاختبارات المطلوبة في Q-2b
- **إعادة الفتح offline بعد قراءة ناجحة:** النسخة تظهر فوراً، ثم فشل الخادم ⇒ القائمة باقية + toast مرة.
- **الإقلاع البارد:** بلا حساب مسجّل ⇒ لا قراءة صندوق ولا عرض؛ `currentUserId` null ⇒ خادم فقط كما الآن.
- **العزل لكل حساب:** صندوق ومفتاح لكل uid؛ سجل `userId` آخر يُسقط عند الحفظ والقراءة؛ الحساب B لا يرى صندوق A.
- **الحساب نفسه بجلسة جديدة / إبطال الجلسة:** جواب متأخر يُسقط ولا يُحفظ؛ قائمة فارغة لجلسة مُزاحة لا تُحفظ ولا تمسح النسخة.
- **الكتابة المنقطعة:** فشل أثناء الحفظ ⇒ النسخة السابقة سليمة.
- **مفتاح مفقود/خاطئ، HMAC تالف:** فشل مغلق؛ D-2 فقط بعد قراءة خادم مُعتمدة؛ علامات تالفة ⇒ حجب.
- **قائمة فارغة موثوقة:** تُحفظ فارغة وتظهر حالة الفراغ.
- **فشل تحديث متعدد الصفحات** (الصفحة 2 من 1,200): لا حفظ؛ المحفوظة كما هي.
- **أمانة الحقول المالية:** `totalAmount` (0، كسور مثل 0.1/0.7، 999,999,999,999.99، null)، الأقساط، العملة — تطابق البت بعد التشفير/فك التشفير؛ البطاقة نفسها.
- **الحقول المستبعدة لا تُكتب:** فك تشفير الحمولة في الاختبار ⇒ مفاتيحها = الـ 12 فقط (لا رسوم/دفعات/ملاحظات/شعار/روابط/مسارات).
- **PDF/التفاصيل:** `hasPdf` من النسخة؛ PDF محلي موجود يُفتح offline بلا أي طلب؛ غير موجود ⇒ فشل `resolvePdf` القائم؛ النقر يمرّر `id` فقط والتفاصيل من الخادم.
- **Delete Account:** يمسح صندوق Quotations ومفتاحه لذلك الحساب فقط.
- **إعادة تشغيل الكاش:** `debugForgetProcessState` ⇒ النسخة تُقرأ وتُتحقَّق من جديد.
- **قوائم كبيرة:** 1,200 / 10,000 / 20,000: زمن الحفظ/القراءة وبايتات الحمولة (VM)؛ تخطي إعادة الكتابة المطابقة.
- **خاص بـ Quotations:** `QuotationException(network)` يعيد المحاولة ويستجيب للاستئناف (D-Q4)؛ عدّ Home القديم يبقى خادماً؛ Q-1b (الأنواع الست لا تقرأ ولا تكتب)؛ حذف مؤكد ⇒ علامة، غير مؤكد ⇒ لا علامة وفشل ظاهر (D-Q3)؛ الحفظ المجمّع ⇒ قراءة وحفظ واحد؛ تأكيد الفراغ المزدوج يُقاس.

### 9) القبول المتبقي
- **مستضاف:** ترقيم Quotations غير الفارغ — **P4.3-ACCEPT-NONEMPTY (OPEN)**.
- **Samsung (DEFERRED):** D-55 (Q-1a/Q-1b) + عند Q-2b: فتح offline بعد قراءة، إعادة تشغيل التطبيق، تبديل الحساب، حذف الحساب، زمن أول إطار لقوائم كبيرة، وأثر النسخ الاحتياطي/الاستعادة (لا يمكن قراءة الصندوق المستعاد).
- **موروث (ليس جديداً، للتوثيق):** على iOS لا يُستدعى `isExcludedFromBackup` لـ `offline_lists` (كالست) — يُراجع ضمن Q-2c أو مهمة منصّة منفصلة.

**الحالة (Q-2a):** **DESIGN** — انتهى؛ القرارات أدناه.

### Q-2b — التنفيذ — 2026-11-07 (CODE_PROVEN؛ غير مدمج)

**موافقة المالك:** **D-Q1…D-Q6 كما أُوصي بها**: D-Q1 الحقول الـ 12 (بما فيها المبلغ/الأقساط/العملة كلقطة تاريخية)؛ D-Q2 `pdfMediaId` فقط (لا رابط موقّع ولا محتوى PDF ولا مسار ملف)؛ D-Q3 حذف مؤكد بدليل الخادم قبل أي علامة؛ D-Q4 تصنيف إعادة محاولة ضيق لـ `QuotationException(network)` دون تغيير الست؛ D-Q5 النسخة المحفوظة أولاً ثم toast القائم مرة لكل سلسلة وعلى الشاشة الظاهرة فقط؛ D-Q6 ملفات PDF مؤجلة إلى Q-2c.
**Git:** `perf/phase-1-startup-baseline` @ `2a75427` = `origin` (0/0)؛ تعديل Q-2a على هذا الملف محفوظ؛ stashes الاثنان وملفات plugin الثلاثة و`docs/ADD_DETAILS_*` لم تُلمس.

**الملفات الإنتاجية (7):**
1. **جديد `lib/src/services/quotations_local_cache.dart`** — `QuotationsLocalCache extends EncryptedAccountListCache<QuotationModel>`: صندوق `cached_quotations_<uid>`، مفتاح `quotations_cache_key_v1_<uid>` (Keystore/Keychain)، `listKey = quotations_v1` (المدخل المخزّن `quotations_v2`، العلامات `quotations_deleted_v1`)؛ encode/decode **للحقول الـ 12 فقط**؛ `ownerOf = userId`. **لا صيغة تشفير جديدة** — AES + v2/HMAC + `offline_lists` المستثنى + D-2 + الحجب كلها موروثة.
2. **`encrypted_account_list_cache.dart`** — معامل اختياري واحد `isRetryable` في `localFirstList` (افتراضه `isRetryableListError`؛ يُستعمل في `fail()` فقط) ⇒ **الست بلا تغيير سلوكي**.
3. **`quotation_service.dart`** — معاملات اختيارية `localCache`/`currentUserId`/`sessionOf` (الافتراض: `authRepository.currentUserId` كالست، وجلسة التطبيق)؛ جديد `watchUserQuotationsLocalFirst()` = `localFirstList(server: getUserQuotations, …, isRetryable: isRetryableListFailure)`؛ **`getUserQuotations()` بلا تغيير (خادم فقط)**؛ `isRetryableListFailure` = العامة + `QuotationException(network)` فقط؛ `deleteQuotation` عبر `deleteThenRemember` (ثم purge PDF والإشارة كما كانا).
4. **`supabase_quotation_service.dart`** — `softDelete` مؤكد (كـ P3.1a): `PATCH … select=id` يعيد الصف ⇒ تم؛ لا صف ⇒ قراءة واحدة `deleted_at=not.is.null` (سياسة `quotations_select_own` = المالك + بوابة الجلسة، بلا فلتر `deleted_at` ⇒ المالك يقرأ صفه المحذوف) ⇒ محذوف أصلاً = تم؛ وإلا تحقق الجلسة القائم + `QuotationException(notFound)` ⇒ VM يعرض `quotationDeleteFailed` القائم (لا PDF purge ولا إشارة).
5. **`list_quotations_viewmodel.dart`** — المصدر فقط ⇒ `watchUserQuotationsLocalFirst()` (محوّل Q-1a بلا تغيير؛ الشاشة بلا تغيير).
6. **`deleted_account_local_data_cleaner.dart`** — `QuotationsLocalCache().forgetAccount` + سطر توثيق (ملفات PDF ليست بعد ⇒ Q-2c).
7. (اختبارات) **`test/responsive/r6b_quotation_fakes.dart`** — الـ fake بـ `noSuchMethod` يحتاج تمرير `watchUserQuotationsLocalFirst()`؛ **`test/quotation/supabase_quotation_service_test.dart`** — «المحذوف أصلاً نجاح» صار يتطلب القراءة المؤكِّدة (`PATCH`،`GET`) — **تغيير مقصود لعقد D-Q3**.
**اختباران جديدان:** `test/quotation/quotation_confirmed_delete_test.dart` (6)، `test/quotation/quotation_list_local_first_test.dart` (31).

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- **أحمر أولاً:** `quotation_confirmed_delete_test` على الكود دون تغيير ⇒ 4 إخفاقات (الحذف بلا صف كان «نجاحاً» صامتاً). `quotation_list_local_first_test` كان **أحمر ترجمةً** (الكاش غير موجود) — سلوكه مُثبت بالطفرات أدناه.
- **جديد 37/37:** الحقول الـ 12 حرفياً وما سواها غائب (لا رسوم/دفعات/ملاحظات/رسائل/شعار/روابط/طريقة دفع)؛ قيم مالية وزمنية بالضبط بعد إعادة تشغيل (0، 0.1، 0.7، 999,999,999,999.99، null؛ ميكروثواني؛ الترتيب)؛ أسماء صندوق/مفتاح فريدة عن الست + Favorites والمفتاح في secure storage والصندوق في `offline_lists`؛ الست لا تتأثر؛ سجلات حساب آخر/بلا حساب لا تُحفظ؛ Keystore غير متاح ⇒ لا صندوق ولا قراءة؛ مفتاح آخر ⇒ لا قراءة والملف والمفتاح كما هما؛ **الشاشة الحقيقية**: 1,200 (3 صفحات) تُحفظ ثم تُفتح offline **قبل أي جواب** بالترتيب، تبقى، بلا حالة خطأ، toast مرة؛ بلا نسخة + offline ⇒ حالة الخطأ بلا toast؛ فشل الصفحة 2 ⇒ لا حفظ؛ فراغ مؤكد ⇒ يُحفظ فارغاً؛ فراغ جلسة مُزاحة ⇒ لا يُحفظ ولا يُعرض؛ **قياس: الفراغ يسأل تحقق الجلسة مرتين بالضبط** (قارئ Q-1a ثم `localFirstList`)، والقائمة غير الفارغة لا تسأل؛ حساب آخر لا يرى النسخة؛ بعد الخروج لا نسخة؛ **حساب آخر / الحساب نفسه بجلسة جديدة أثناء القراءة ⇒ الجواب يُسقط ولا يُحفظ**؛ إغلاق الشاشة أثناء القراءة ⇒ لا حفظ؛ Q-1b: الأنواع الست ⇒ لا قراءة ولا كتابة (البايتات نفسها)، Quotation ⇒ قراءة + حفظ؛ تغييرات متزامنة ⇒ قراءة إضافية واحدة والأخيرة تُحفظ؛ **offline ثم استئناف مع عودة الشبكة ⇒ تعافٍ** (D-Q4)؛ الافتراض لا يعيد محاولة `QuotationException(network)` (الست) ومُصنّف Quotations يعيد الشبكة فقط؛ حذف مؤكد ⇒ لا يظهر offline؛ حذف غير مؤكد ⇒ فشل وبلا علامة؛ علامات تالفة ⇒ `ListIntegrityBlocked` بلا قائمة ولا قراءة؛ HMAC تالف ⇒ لا شيء ثم قراءة خادم موثّقة تستعيد (D-2)؛ **Home: `getUserQuotations()` خادم فقط ولا يكتب**؛ بطاقة محفوظة تفتح PDF نُزّل سابقاً **بلا أي طلب**؛ Delete Account يمسح صندوق ومفتاح الحساب وحده؛ قياسات.
- **الطفرات 11/11 التُقطت** (SHA-256 مطابق بعد كلٍّ): M0 `softDelete` كما في الـ HEAD (4)؛ M1 حقل مالي إضافي محفوظ (1)؛ M2 تقريب المبلغ عند القراءة (2)؛ M3 الشاشة تقرأ الخادم فقط (14)؛ M4 بلا مُصنّف Quotations (1)؛ M5 كل فشل Quotation يُعاد (1)؛ M6 `localFirstList` يتجاهل `isRetryable` (2)؛ M7 الحذف لا يُعلَّم (2)؛ M8 الحذف غير المؤكد يُقبل (3)؛ M9 Delete Account يُبقي الصندوق (1)؛ M10 Home يقرأ النسخة المحفوظة (1).
- **انحدار مركّز — 2,503 نجاح / 4 إخفاقات، كلها خارج Q-2b:** `test/quotation` + `test/services` + `test/lists` + `test/home` + `test/search` + `test/favorites` + `test/account` + اختبارا auth للهوية/SAD + `test/share` + `save_cancel_buttons` + `r6b_quotations_responsive` + `perf/list_open_baseline`. الإخفاقات: (1) `supabase_quotation_service_test` «المحذوف أصلاً» = العقد القديم ⇒ **حُدِّث عمداً** (أعلاه)؛ (2) `delete_account_test` setUpAll يقرأ هجرة باسم غير موجود (`20260913000100_…`؛ الموجود `20260913175221_…`) — **خط أساس معروف**؛ (3) `delete_account_ui_test` = **FU-ACCOUNT-UI-BASELINE-1**؛ (4) `list_refresh_test` «retry في الخلفية» — **ليس تأكيداً بل teardown** (`deleteSync` على Windows: الملف مقفل) تحت الحمل؛ **ينجح منفرداً**. بعد التعديلات الأخيرة: الملفات المعنية (منها `list_refresh_test`، Q-1a/Q-1b، r6b) ⇒ **213/213**، ثم الملفان الجديدان ⇒ **37/37**.
- **Analyzer** (10 ملفات) ⇒ No issues. **Format 3.5:** كل الملفات 0 جديد (`supabase_quotation_service.dart` 22 سابقة = الـ HEAD)؛ الجديدة مُنسّقة. **`git diff --check`** نظيف؛ CRLF.
- **ملاحظة اختبار:** supabase 2.16.1 `from()` لا يمرّر خيارات إعادة المحاولة ⇒ كل GET يُعاد 3 مرات (1+2+4 ث) قبل فشل الشبكة؛ اختبارات offline تنتظر نتيجة الشاشة. **الإنتاج بلا تغيير**.

**القياس (M — VM الاختبار، تشغيلان؛ ليس Samsung):**

| عروض الأسعار | الحمولة | الكتابة | القراءة الباردة (بعد إعادة تشغيل) |
|---|---|---|---|
| 100 | 42.6 KB | 12–13 ms | 16–19 ms |
| 1,200 | 511 KB | 67–70 ms | 47–59 ms |
| 10,000 | 4.26 MB | 507–528 ms | 348–363 ms |
| 20,000 | 8.52 MB | 1,211–1,292 ms | 748–914 ms |
- القراءة الباردة تسبق ظهور النسخة؛ تخطي إعادة الكتابة المطابقة وإعادة استعمال الغلاف المُتحقَّق (P4.7b/c) موروثان. **لا ادعاء لزمن الإطار الأول على الجهاز.**

**التوافق المالي وPDF:** لا حساب/حفظ/PDF من النسخة؛ القيم كما أرسلها الخادم (اختبار تطابق)؛ الحسابات (`add_quotation_viewmodel_test`) وPDF/الوسائط (`quotation_service_test`، `quotation_media_workflow_test`، `r2_quotation_media_service_test`) ضمن الانحدار ⇒ نجحت؛ `pdf_generation_service`/`QuotationPdfCache`/المسارات **بلا تغيير**؛ التفاصيل تبقى من الخادم بـ `id`؛ لا كتابة offline.

**الحدود الباقية:**
- **Q-2c — OPEN (خصوصية PDF):** ملفات `quotation_<id>_<mediaId>.pdf` (+ بقايا `quotation_<id>.pdf`) **غير مشفّرة، ليست لكل حساب، غير مستثناة من النسخ الاحتياطي (Android + iOS)، لا يمسحها Delete Account**؛ مع D-Q2 صار PDF نُزّل سابقاً يُفتح offline من بطاقة محفوظة (الملف كان موجوداً أصلاً).
- `pdfMediaId` محفوظ قد يكون أقدم من الخادم ⇒ يُفتح الإصدار المحلي الأقدم بالضبط (لقطة تاريخية).
- نماذج البطاقة من النسخة بلا `version`/شعار (لا تُستعمل في القائمة؛ التحرير يقرأ من الخادم).
- الفراغ يكلّف تحقق جلسة مزدوجاً (مقيس: 2) — لم يُزل (قرار منفصل إن لزم).
- **iOS:** `offline_lists` بلا `isExcludedFromBackup` (موروث كالست).
- **غير مُتحقَّق مستضافاً:** عقد الحذف المؤكد على PostgREST الحقيقي (**لم تُعدَّل بيانات مستضافة**)، وترقيم Quotations غير الفارغ — **P4.3-ACCEPT-NONEMPTY: OPEN**.
- **Samsung (DEFERRED):** D-56 أدناه.

**الحالة:** **Q-2b = CODE_PROVEN — STAGING_UNVERIFIED، REAL_DEVICE_UNVERIFIED.** **NOW:** مراجعة المالك ثم موافقة commit (المالك يدفع). **NEXT (مرحلة منفصلة تحتاج موافقة):** **Q-2c — حماية ملفات PDF**. **STOP:** لا Q-2c تلقائياً؛ لا commit/push؛ **P4.3-ACCEPT-NONEMPTY: OPEN**؛ Samsung DEFERRED.

**تحديث Git:** Q-2b أُودع `a5b6ff9` والمالك دفعه (= `origin`).

---

## 7AY) Q-2c — أمن ملفات PDF لعروض الأسعار، عزل الحسابات والترحيل — 2026-11-07 (DESIGN؛ لا تغيير كود؛ ينتظر موافقة المالك)

**Git (مُتحقَّق):** `perf/phase-1-startup-baseline` @ `a5b6ff9` = `origin` (0/0 بعد `git fetch`)؛ stashes الاثنان باقيان. **ملاحظة:** شجرة العمل صارت **نظيفة تماماً** — ملفات plugin الثلاثة لم تعد معدّلة، و**`docs/ADD_DETAILS_AREA_CATALOG.csv` و`docs/ADD_DETAILS_DESIGNER_INVENTORY.md` غير موجودين** (غير متتبَّعين ⇒ لا يستعيدهما git؛ آخر تغيير لمجلد `docs/` 02:55 اليوم). **لم يلمسهما الوكيل**؛ يُبلَّغ المالك. **هذا القسم وحده تغيّر.** لم يُقرأ ولم يُنقل ولم يُحذف أي PDF.

### 1) مسارات PDF الحالية (S — من المصدر)
| # | السؤال | الجواب |
|---|---|---|
| 1 | أين يُكتب PDF المولَّد أولاً؟ | `PdfGenerationService.generateQuotationPdf` ⇒ **جذر المستندات** `quotation_<qid>.pdf` (`pdf_generation_service.dart:244`؛ بديل `quotation_<millis>.pdf` إن لم يوجد id — `AddQuotationViewModel` يمرّر id دائماً). |
| 2 | أين يُحفظ المنزَّل/المنشور؟ | `QuotationPdfCache` في **الجذر نفسه**: `quotation_<qid>_<mediaId>.pdf`؛ `publishPdf` ⇒ رفع ثم `adopt` (rename، أو copy+delete)؛ `resolvePdfFile` ⇒ `write` بعد تنزيل برابط موقّع لا يُحفظ. |
| 3 | ربط معرّف الوسائط بالملف | الاسم = `quotation_<qid>_<mediaId>.pdf`؛ `existing(qid, mediaId)` بالمطابقة الحرفية؛ `adopt`/`write` يحذفان نسخ العرض نفسه بمعرّفات أخرى (`_removeOthers`). |
| 4 | فرادة الأسماء | UUID مزدوج (عرض + وسائط) ⇒ فريدة عملياً عالمياً. |
| 5–6 | مشاركة/تصادم بين حسابات | **لا حساب في المسار أو الاسم**؛ معرّفات UUID ⇒ لا تصادم، لكن **ملفات كل الحسابات في مجلد واحد**. |
| 7 | إعادة الفتح | `resolvePdfFile` يعيد الملف المحلي **قبل أي شبكة** إن وُجد للمعرّف (Q-2b: يعمل offline من بطاقة محفوظة)؛ العرض `PdfViewerScreen(localFile)` والمشاركة (`ShareLive`، نسخة في `getTemporaryDirectory()/broker_wallet_share`) تحتاجان **ملفاً نصياً صريحاً**. |
| 8 | فتح PDF حساب آخر؟ | **عبر التطبيق: لا عملياً** — المعرّفات تأتي فقط من قائمة الحساب (RLS للخادم؛ نسخة Q-2b لكل حساب). **لكن** المحلّل لا يتحقق من الحساب؛ الحماية منطقية فقط، والملفات مقروءة لأي كود داخل sandbox التطبيق. |
| 9 | قِدم النسخة | المفتاح هو `mediaId` ⇒ لا تُفتح نسخة قديمة **بدل** الحالية حين يعرف السطر المعرّف الحالي؛ نسخة Q-2b offline بمعرّف قديم ⇒ تُفتح **النسخة القديمة بالضبط** (لقطة)؛ الأحدث يحلّ عند أول قائمة خادم. |
| 10 | ما يفوته Delete Account | **كل** `quotation_*.pdf` في الجذر (المنشورة/المنزّلة + بقايا التوليد `quotation_<qid>.pdf` إن قُطع التطبيق بين التوليد والـ adopt + أي `quotation_<millis>.pdf` قديم). |
- **النسخ الاحتياطي:** `backup_rules.xml`/`data_extraction_rules.xml` تستثني **مجلدات/ملفات مسماة فقط**؛ الجذر ليس منها ⇒ **ملفات PDF الحالية تُنسخ إلى Google ونقل الجهاز**. قواعد Android **لا تقبل أنماطاً (wildcards)** ⇒ لا يمكن استثناء `quotation_*.pdf` في الجذر دون نقلها. **iOS:** Documents تُنسخ إلى iCloud؛ الحارس القائم `PlatformScannerBackupGuard` (`com.example.broker_wallet/backup_exclusion` في `AppDelegate.swift`) يضع `isExcludedFromBackup` على مجلد/ملف — **قابل لإعادة الاستعمال بلا تغيير native**.
- **سابقة Toolkit (DECISIONS.md):** `<documents>/<أداة>/<account>/` (اسم الحساب UUID حرفياً وإلا hex، فلا يخرج عن المجلد)، مستثنى من النسخ (Android + iOS)، **بلا تشفير**؛ الملفات القديمة على مستوى الجهاز «لا تُرحَّل ولا تُعرض ولا تُحذف» — قرار مالك.

### 2) المخاطر (مرتبة)
1. **R1 (عالي):** ملفات PDF تحمل **التجميع المالي كاملاً** (رسوم، دفعات، تأمين، ملاحظات، رسالة ترحيب، المكتب/الشعار) **نصاً صريحاً** في مكان **يُنسخ احتياطياً** ⇒ يصل إلى نسخة Google/iCloud وأي جهاز منقول إليه.
2. **R2 (عالي):** Delete Account يترك كل ملفات PDF للحساب المحذوف.
3. **R3 (متوسط):** لا عزل حساب على الجهاز (مجلد واحد، لا فحص حساب في المحلّل) — الحماية من الحساب الآخر منطقية لا تشفيرية.
4. **R4 (منخفض):** بقايا توليد غير مرتبطة (`quotation_<qid>.pdf`) لا يقرؤها التطبيق أبداً لكنها تبقى وتُنسخ.
5. **R5 (منخفض، موروث):** جهاز مُزاح (SAD) offline يستطيع فتح PDF محلي حتى أول تواصل مع الخادم — كقوائم Q-2b؛ النسخة ليست سلطة.

### 3) المعمارية المقترحة للملفات الجديدة (أصغر تصميم آمن)
- **المكان:** `app_flutter/quotation_pdfs/` (`<documents>/quotation_pdfs`) — مجلد واحد **مستثنى من النسخ** (Android: سطر في `backup_rules.xml` وفي `cloud-backup` و`device-transfer` في `data_extraction_rules.xml`؛ iOS: الحارس القائم على المجلد عند إنشائه، best effort). **لا تغيير** لاستثناءات القوائم الست/Favorites/Quotations list/Toolkit/وسائط Offer وOwner.
- **التشفير — التوصية: نعم (الخيار B)، بلا نظام تشفير جديد:** صندوق Hive **LazyBox** لكل حساب `quotation_pdfs_<uid>` داخل ذلك المجلد، مشفّر بـ **HiveAesCipher** بمفتاح لكل حساب في Keystore/Keychain عبر `SecureAccountCacheKeyStore` (بادئة جديدة `quotation_pdfs_key_v1_`) — **نفس البدائيات المعتمدة في القوائم**؛ المدخل = `<qid>:<mediaId>` ⇒ البايتات + وسم سلامة (SHA-256 للبايتات + تحقق `%PDF-`؛ أو وسم HMAC على نمط D-3 إن وافق المالك على إخراج مشتقّه من `EncryptedAccountListCache` — قرار D-P1b). **السبب:** الملفات أشد حساسية من حقول القائمة المشفّرة أصلاً؛ تعطي **عزلاً تشفيرياً بين الحسابات** على الجهاز نفسه؛ نسخة تُستعاد/تُنقل رغم الاستثناء (حارس iOS قد يفشل، أو نسخ قديمة) **غير مقروءة** بلا مفتاح Keystore؛ تمنع تعديل مبالغ PDF محلياً دون كشف.
  - **العرض/المشاركة:** فك التشفير إلى `getTemporaryDirectory()/quotation_view/<random>.pdf` (مستثنى من النسخ على المنصتين) ⇒ `PdfViewerScreen`/`ShareLive` بلا تغيير؛ يُحذف عند إغلاق العارض/انتهاء المشاركة + كنس عند الإقلاع.
  - **دورة حياة المفتاح:** يُنشأ عند أول حفظ PDF للحساب؛ **يبقى بعد الخروج** (إعادة الفتح offline بعد دخول الحساب نفسه)؛ يُحذف مع الصندوق في Delete Account. **الاستعادة:** مفتاح مفقود/خاطئ (إعادة تثبيت، استعادة نسخة، إبطال Keystore) ⇒ الصندوق غير مقروء ⇒ **فشل مغلق** (لا فتح offline)؛ **لا فقد بيانات حقيقي** لأن R2 هو المصدر: يُستبدل الصندوق **فقط بعد تنزيل ناجح مُصرَّح به** للحساب (نمط D-2)، لا عند القراءة.
  - **الأداء (تقدير، يُقاس في التنفيذ):** PDF نموذجي 0.1–1 MB ⇒ AES بالـ ms على الجهاز؛ LazyBox لا يحمّل الصندوق كله في الذاكرة؛ نسخة temp إضافية لكل فتح. **لا ادعاء قبل القياس.**
  - **الخيار A (بديل أبسط، سابقة Toolkit):** ملفات صريحة في `quotation_pdfs/<uid>/` + استثناء النسخ + Delete Account. أقل كوداً؛ يُبقي R3 منطقياً ونسخة مستعادة مقروءة.
- **الملكية والجلسة:** المخزن يُفتح **لحساب `currentUserId` فقط**؛ المحلّل يرفض نموذجاً `userId ≠ الحساب المسجّل`؛ تنزيل بدأ تحت جلسة S1 وانتهى تحت جلسة/حساب آخر ⇒ **لا يُحفظ ولا يُفتح** (ربط بالجلسة كـ `localFirstList`)؛ الخروج **لا يحذف** شيئاً؛ تبديل الحساب ⇒ مخزن الحساب الآخر.
- **التوليد:** يكتب في `quotation_pdfs/.work/<uid>/` (مستثنى) بدل الجذر — **المحتوى والحسابات بلا تغيير**؛ `adopt` ⇒ يدخل المخزن ثم يُحذف ملف العمل؛ بقايا `.work` تُكنس عند الحفظ التالي/الإقلاع (لم تُربط بعرض أبداً).
- **لا تنزيل جماعي ولا تلقائي؛ لا كتابة مالية offline؛** لا يُستبدل PDF أحدث بأقدم (المفتاح `mediaId`؛ الأحدث يحذف نسخ العرض نفسه فقط كما اليوم).

### 4) ترحيل الملفات القديمة (آمن من الانقطاع)
- **الاكتشاف:** في الجذر فقط، أسماء تطابق حرفياً `^quotation_<uuid>_<uuid>\.pdf$` (منشورة/منزّلة) و`^quotation_<uuid>\.pdf$` (بقايا توليد)؛ أي شيء آخر (`quotation_<millis>.pdf`، أسماء مختلفة) ⇒ **لا يُلمس**.
- **دليل الملكية الموثوق (لا الاسم):** **قائمة خادم كاملة ناجحة** (Q-1a، تحت الجلسة الحالية للحساب) — عند `accept()` لتلك القائمة: كل سطر بـ `(qid, pdf_media_id)` وملف جذري مطابق تماماً ⇒ **الملف ملك هذا الحساب** (الخادم بـ RLS أكّد أن العرض له وأن هذا هو PDF المرتبط الحالي).
- **الخطوات لكل ملف:** نسخ (لا نقل) ⇒ تشفير إلى مدخل مؤقت في الصندوق ⇒ قراءة المدخل وفك تشفيره ومقارنة **SHA-256 + الحجم + `%PDF-`** مع الأصل ⇒ تثبيت المدخل النهائي ⇒ **ثم فقط** حذف الأصل. انقطاع/إعادة تشغيل في أي نقطة ⇒ الأصل باقٍ؛ المحاولة التالية **idempotent** (مدخل موجود ومطابق ⇒ يُحذف الأصل فقط؛ مدخل جزئي/غير مطابق ⇒ يُستبدل).
- **الحالات:** مكرر (المدخل موجود بالمعرّف نفسه) ⇒ تحقق ثم حذف الأصل؛ مفقود ⇒ لا شيء (يُنزّل عند الفتح)؛ تالف (لا `%PDF-`/حجم 0) ⇒ **يبقى في مكانه** ويُسجّل بفئة ثابتة (لا يُرحَّل، لا يُحذف) ⇒ قرار؛ امتلاء التخزين/صلاحيات ⇒ يتوقف الترحيل، الأصل باقٍ، يُعاد في التشغيل التالي، لا خطأ على الشاشة؛ عدة حسابات ⇒ كلٌّ يرحّل **ما يثبته خادمه فقط**.
- **ملف لعرض الحساب لكن بمعرّف قديم** (`qid` في القائمة، `mediaId ≠` الحالي): مالكه مُثبت؛ التطبيق لا يفتحه أبداً و`_removeOthers` يحذفه أصلاً عند أول تنزيل ⇒ **D-P3**.
- **بقايا التوليد** `quotation_<qid>.pdf` و`qid` في قائمة الحساب ⇒ مالكها مُثبت لكنها ليست PDF مرتبطاً (قد تكون نسخة فاشلة) ⇒ **D-P3**.
- **غير قابل للإسناد** (عرض محذوف، حساب لم يعد يدخل، حساب محذوف قبل Q-2c، أسماء غير مطابقة): **لا يُحذف تلقائياً أبداً** ⇒ يبقى مخفياً في مكانه (سابقة Toolkit) ⇒ **D-P4**؛ يبقى قابلاً للنسخ الاحتياطي (لا wildcard) — خطر تاريخي موثّق.

### 5) Delete Account
- يحذف **صندوق `quotation_pdfs_<uid>` ومفتاحه** و`.work/<uid>/` للحساب المحذوف فقط (بالـ uid؛ يعمل كان الحساب مسجّلاً أم لا).
- **الملفات الجذرية القديمة للحساب المحذوف:** قبل `QuotationsLocalCache().forgetAccount` (ترتيب مهم) يُقرأ **نسخة Q-2b المُتحقَّقة لهذا الحساب** (HMAC، مربوطة بالحساب، لا تُكتب إلا من قوائم خادمه) ⇒ تُحذف الملفات الجذرية `quotation_<qid>_*.pdf` و`quotation_<qid>.pdf` لكل `qid` فيها ⇒ **D-P5**؛ نسخة غير مقروءة/محجوبة ⇒ لا حذف جذري (يبقى غير مُسند).
- **لا يلمس:** ملفات حسابات أخرى، وسائط Offer/Owner، Toolkit، ملفات غير مطابقة للنمط.
- **الخروج العادي لا يحذف أي PDF.**
- **باقٍ:** ملفات جذرية لحساب حُذف **قبل** Q-2c أو بلا نسخة Q-2b، والنسخ الاحتياطية التاريخية.

### 6) النسخ الاحتياطي والخطر التاريخي
- **مقترح:** `app_flutter/quotation_pdfs` في القوائم الثلاث (Android ≤11 `full-backup-content`؛ 12+ `cloud-backup` + `device-transfer`)؛ iOS: `isExcludedFromBackup` على المجلد (والصندوق والـ `.work`) عبر الحارس القائم.
- **ما لا تفعله القواعد الجديدة:** **لا تمحو** نسخاً احتياطية سابقة في Google Drive/iCloud، ولا ملفات نُقلت إلى أجهزة أخرى، ولا الملفات الجذرية التي لم تُرحَّل (تبقى تُنسخ). قد لا تحتوي النسخة **التالية** على الملفات المُرحَّلة، لكن توقيت ذلك وبقاء النسخ القديمة **خارج سيطرة التطبيق — لا ادعاء**.

### 7) السلامة المالية والوظيفية
- بلا تغيير: الصيغ، العملة، التقريب، **محتوى** PDF، الإنشاء/التعديل، `pdf_media_id`، تفويض الخادم، SAD، Q-1a، Q-1b، كاش Q-2b. التغيير **مكان التخزين** فقط (+ تشفير إن D-P1 = B). لا تنزيل تلقائي، لا كتابة offline. يبقى فتح PDF نُزّل سابقاً offline (من المخزن المشفّر للحساب نفسه).

### 8) قرارات المالك المطلوبة
- **D-P1:** (B موصى) مخزن مشفّر لكل حساب (LazyBox + AES + Keystore، فك إلى temp للعرض/المشاركة) — أو (A) ملفات صريحة لكل حساب (سابقة Toolkit).
- **D-P1b (إن B):** السلامة بـ SHA-256 داخل المدخل المشفّر (أبسط) — أو وسم HMAC على نمط D-3 (يتطلب إخراج مشتق المفتاح من `EncryptedAccountListCache` كتغيير مشترك صغير).
- **D-P2:** دليل الملكية = قائمة خادم كاملة ناجحة للحساب، تطابق حرفي `(qid, pdf_media_id)` — **موصى**.
- **D-P3:** ملفات مُثبتة الملكية لكنها **قديمة الإصدار** أو **بقايا توليد**: حذفها بعد الإثبات (مطابق لسلوك `_removeOthers` اليوم) — **موصى** — أو إبقاؤها.
- **D-P4:** غير القابل للإسناد: **يبقى مخفياً بلا حذف** (موصى، سابقة Toolkit) — أو تنظيف يدوي/لاحق بموافقة صريحة.
- **D-P5:** Delete Account يحذف الملفات الجذرية المُسندة عبر نسخة Q-2b المُتحقَّقة — **موصى**.
- **D-P6:** الخروج يُبقي ملفات الحساب (فتح offline بعد عودته) — **موصى** — أو حذفها عند الخروج.
- **D-P7:** مجلد التوليد `.work` بدل الجذر (تغيير مكان لا محتوى في `pdf_generation_service`/مستدعيه) — **موصى**.

### 9) ترتيب التنفيذ المقترح (Q-2c-1، بعد الموافقة؛ ترحيل واحد)
1. اختبارات حمراء أولاً. 2. مخزن `QuotationPdfStore` لكل حساب (B أو A) خلف واجهة `QuotationPdfCache` القائمة (`existing/adopt/write/purge`) + ربط الحساب/الجلسة. 3. مجلد العمل للتوليد. 4. العرض/المشاركة عبر temp (إن B). 5. ترحيل مُسند بالخادم عند قائمة خادم ناجحة (idempotent). 6. قواعد النسخ (XML) + الحارس على iOS. 7. Delete Account (المخزن + الجذري المُسند). 8. انحدار مركّز + طفرات + analyzer/format/diff + هذا الملف.
**ملفات متوقعة:** جديد `quotation_pdf_store.dart`؛ `quotation_pdf_cache.dart`؛ `quotation_service.dart`؛ `pdf_generation_service.dart` (مكان الكتابة فقط)؛ `list_quotation_view.dart` (حذف ملف temp بعد العارض/المشاركة إن B — **سلوك لا واجهة**)؛ `deleted_account_local_data_cleaner.dart`؛ `backup_rules.xml`؛ `data_extraction_rules.xml`. **لا native** (القناة موجودة).

### 10) خطة الاختبار
- **VM (حتمي):** إعادة الفتح offline للحساب نفسه بلا طلب؛ عزل A/B (B لا يفتح مدخل A ولا ملفه؛ نموذج `userId` آخر يُرفض)؛ الخروج ثم دخول الحساب نفسه ⇒ يفتح؛ جلسة مُزاحة/تبديل أثناء التنزيل ⇒ لا حفظ ولا فتح؛ ترحيل: انقطاع بعد النسخ/قبل الحذف/أثناء الكتابة ⇒ الأصل باقٍ ثم يكتمل idempotent؛ إعادة تشغيل أثناء الترحيل؛ القديم والجديد معاً (المخزن أولاً ثم الجذري المُسند)؛ أسماء مكررة؛ ملكية غير مُثبتة ⇒ لا لمس؛ ملف تالف/مفقود؛ فشل النسخ/امتلاء القرص (I/O محقون) ⇒ لا فقد؛ مفتاح مفقود/خاطئ ⇒ فشل مغلق ثم استبدال بعد تنزيل مُصرَّح؛ وسم سلامة تالف ⇒ لا فتح؛ Delete Account ⇒ ملفات/مدخلات الحساب فقط، الآخرون وToolkit ووسائط Offer/Owner سليمة؛ `mediaId` قديم ⇒ النسخة القديمة بالضبط ثم الحالية بعد قائمة خادم؛ التوليد لا يكتب في الجذر؛ ملف temp يُحذف؛ الحسابات وPDF (`add_quotation_viewmodel_test`، `quotation_service_test`، `quotation_media_workflow_test`، `r2_quotation_media_service_test`، `share_quotation_test`) بلا تغيير؛ نص XML يحوي الاستثناءات والقديمة حرفياً كما هي؛ طفرات.
- **جهاز حقيقي فقط (Samsung/iOS، DEFERRED):** أن Android يستثني المجلد فعلاً (`bmgr`/نسخة سحابية ونقل جهاز)؛ `isExcludedFromBackup` على iOS؛ سلوك Keystore بعد إعادة التثبيت/الاستعادة؛ امتلاء القرص الحقيقي؛ زمن فك التشفير والعرض لملفات كبيرة؛ عرض PDF من temp في العارض الحقيقي؛ المشاركة إلى تطبيقات خارجية.

### 11) القبول المتبقي والخطر التاريخي
- **مستضاف:** لا يلزم لهذه المرحلة (لا خادم)؛ عقد الحذف المؤكد (Q-2b) ما زال غير مُتحقَّق مستضافاً؛ **P4.3-ACCEPT-NONEMPTY: OPEN**.
- **Samsung/iOS:** D-56 + بنود Q-2c أعلاه — DEFERRED.
- **تاريخي (لا يُغلق بالتنفيذ):** النسخ الاحتياطية الموجودة وما نُقل إلى أجهزة أخرى؛ الملفات الجذرية غير المُسندة؛ ملفات حسابات حُذفت قبل Q-2c.

**الحالة (Q-2c التصميم):** انتهى؛ القرارات أدناه.

### Q-2c-1 — الأجزاء الآمنة بذاتها — 2026-11-07 (CODE_PROVEN؛ غير مدمج) — وحد الموافقة على التشفير

**موافقة المالك (مع التشديدات):** D-P1 مخزن مشفّر لكل حساب؛ **D-P1b** سلامة مُصادَقة بـ **HMAC-SHA256** مع فصل نطاقات واشتقاق مفاتيح على مبادئ D-3 (SHA-256 وحده ليس وسماً) — **وإن تطلّب ذلك صيغة تشفير/معمارية جديدة لا تعيد استعمال البدائيات القائمة بأمان ⇒ STOP لموافقة ضيقة**؛ D-P2 ملكية بدليل الخادم للحساب الحالي (`qid` + `pdf_media_id` الحالي؛ تطابق الاسم ليس دليلاً على الإصدار)؛ D-P3 حذف القديم فقط بعد ملكية + بديل مُتحقَّق مُعاد فتحه + سلامة + قابلية استئناف؛ D-P4 غير المُثبت يبقى مخفياً بلا لمس؛ D-P5 Delete Account للملفات المُثبتة والمفاتيح والعمل والبقايا فقط؛ D-P6 الخروج يُبقي الملفات تحت قواعد الحساب/الجلسة؛ D-P7 التوليد في مجلد عمل مستثنى بالمحتوى نفسه.
**Git:** `a5b6ff9` = `origin` (0/0)؛ stashes الاثنان باقيان؛ `docs/ADD_DETAILS_*` **ما زالا مفقودين** (لم يُنشآ ولم يُلمسا)؛ ملفات plugin الثلاثة **أعادت أوامر Flutter توليدها** أثناء الاختبارات (الفخ المعروف في CLAUDE.md) — تُبلَّغ ولا تُستعاد ولا تُدرج.

**وحد الموافقة (STOP — D-P1/D-P1b لم يُنفَّذا):** فُحصت بدائيات D-3 (`EncryptedAccountListCache`): مفتاح لكل حساب في secure storage؛ `K_mac = HMAC-SHA256(boxKey, "broker_wallet/offline_lists/v2/mac")`؛ وسم HMAC على مدخل مُسبق الطول (label، version، listKey، uid، payload)؛ مقارنة ثابتة الزمن؛ التشفير = **تشفير صندوق Hive** (`HiveAesCipher`، `crashRecovery: false`، `guardedOpen` لخطأ Hive المكرر، إعادات rename على Windows، استبدال الاستعادة بعد قراءة خادم مُعتمدة فقط). **هذه المعمارية مبنية لقائمة JSON واحدة في صندوق، لا لملفات ثنائية** ⇒ تشفير ملفات PDF يتطلب إما **مخزن Hive جديداً للـ blobs يعيد تنفيذ كل فخاخ الفتح/الاستعادة**، أو **صيغة ملف مُصادَقة جديدة** — كلاهما «صيغة/معمارية جديدة» ⇒ **توقف حسب التعليمات**. التصميم الضيق المقترح للموافقة (Q-2c-1b):
- **E (موصى) — ملف لكل PDF، encrypt-then-MAC:** `quotation_pdfs/<account>/<qid>_<mediaId>.bwqp`؛ مفتاح رئيسي 32 بايت عشوائي لكل حساب في Keystore/Keychain (`SecureAccountCacheKeyStore`، بادئة `quotation_pdfs_key_v1_`)؛ `K_enc = HMAC-SHA256(master, "broker_wallet/quotation_pdfs/v1/enc")` و`K_mac = HMAC-SHA256(master, "broker_wallet/quotation_pdfs/v1/mac")` (الاشتقاق نفسه لـ D-3، نطاقان منفصلان)؛ التشفير `HiveAesCipher(K_enc)` (AES-256-CBC، IV عشوائي، PKCS7 — البدائية نفسها المستعملة في الصناديق، تُستدعى مباشرة)؛ الوسم `HMAC-SHA256(K_mac, lenprefixed("bw-quotation-pdf","1",uid,qid,mediaId,ciphertext))` **قبل** فك التشفير، مقارنة ثابتة الزمن؛ التخطيط `BWQP|1|tag(32)|ciphertext`؛ كتابة ذرية (`.tmp` + rename)؛ وسم/مفتاح غير صالح ⇒ «غير موجود» (تنزيل عند الاتصال)، الملف لا يُستبدل إلا بتنزيل مُصرَّح ناجح للحساب والجلسة نفسيهما؛ العرض/المشاركة: فك إلى `getTemporaryDirectory()/bw_quotation_view/<random>.pdf` يُحذف بعد الإغلاق + كنس عند الإقلاع. **ميزة:** كل ملف مستقل (لا فشل صندوق كامل، لا فخاخ إصلاح Hive)، EtM أقوى من MAC-داخل-التشفير.
- **H (بديل):** صندوق Hive LazyBox لكل حساب + مدخلات وسم على نمط D-3 — يعيد استعمال إطار Hive لكنه يكرر منطق الفتح/الاستعادة لنوع صندوق جديد، وفشل الصندوق يُسقط كل PDFs الحساب معاً.
- **ما يعتمد على هذا القرار (لم يُنفَّذ):** المخزن المشفّر، **ترحيل** الملفات الجذرية (D-P2/D-P3)، ملفات temp للعرض/المشاركة، حذف المفاتيح في Delete Account.

**ما نُفِّذ (مستقل عن خيار التشفير، بلا ترحيل مزدوج):**
1. **جديد `lib/src/views/Screens/home/quotation/services/quotation_pdf_files.dart`** — `<documents>/quotation_pdfs` (المجلد الذي تسمّيه قواعد النسخ)؛ `workDirectory(docs, uid)` = `quotation_pdfs/.work/<account>` (UUID حرفياً وإلا hex — كسابقة Toolkit؛ فارغ ⇒ `ArgumentError`)؛ `workFileFor(quotation)` ينشئ المجلد ويطلب من **الحارس القائم** (`PlatformScannerBackupGuard`) استثناء `quotation_pdfs` على iPhone؛ `forgetAccount(uid)`: يحذف `.work/<uid>` ثم **كل PDF جذري يسمّي عرض سعر في نسخة Q-2b المُتحقَّقة لهذا الحساب** (`quotation_<qid>_<uuid>.pdf` و`quotation_<qid>.pdf`، أنماط UUID صغيرة مُرسّاة؛ `qid` مفتاح أساسي لا ينتمي إلا لحساب واحد) — نسخة غير مقروءة/مفقودة ⇒ **لا حذف جذري**؛ أي اسم آخر ⇒ لا لمس.
2. **`pdf_generation_service.dart`** — مكان الكتابة فقط: `final file = await QuotationPdfFiles().workFileFor(quotation);` (بدل جذر المستندات)؛ `pdf.save()` و`writeAsBytes` والحذف عند الفشل **بلا تغيير**؛ أُزيل استيراد `path_provider` (لم يعد مستعملاً). `adopt` القائم ينقل الملف من مجلد العمل إلى نسخة `QuotationPdfCache` (rename على المجلد نفسه).
3. **`quotation_service.dart` — `resolvePdfFile`:** حساب غير مسجّل ⇒ `notSignedIn`؛ `userId` حساب آخر ⇒ `unauthorized` — **قبل أي ملف أو طلب**؛ الجلسة/الحساب يُلتقطان عند البدء ويُتحقق منهما **بعد جواب الخادم وبعد التنزيل** ⇒ جواب متأخر لحساب/جلسة أخرى لا يُحفظ ولا يُفتح (`notSignedIn`)؛ الخروج ثم دخول الحساب نفسه ⇒ النسخة المحلية تُفتح.
4. **`deleted_account_local_data_cleaner.dart`** — خطوة `forgetQuotationPdfs` (قابلة للحقن، افتراضها `QuotationPdfFiles().forgetAccount`) **قبل** `QuotationsLocalCache().forgetAccount` (النسخة هي دليل الملكية)؛ توثيق ما لا يُحذف (D-P4).
5. **`backup_rules.xml`** (`full-backup-content`) و**`data_extraction_rules.xml`** (`cloud-backup` + `device-transfer`) — `<exclude domain="root" path="app_flutter/quotation_pdfs" />` + تعليق؛ **كل الاستثناءات السابقة حرفياً كما هي**.
6. (اختبار) **`test/quotation/quotation_service_test.dart`** — harness يمرّر `currentUserId: () => 'u'` (حساب نماذج الاختبار؛ المحلّل صار يتطلب الحساب).
**جديد:** `test/quotation/quotation_pdf_protection_test.dart` (20).

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- **جديد 20/20:** قواعد Android الثلاث تحوي المجلد **وكل الاستثناءات القديمة** (offer_media/uploads، scanner، mlkit، combine_pdfs، image_to_pdf، signature_pdfs، offline_lists، cached_favorites)؛ iPhone: الحارس يُطلب على `quotation_pdfs` عند الإنشاء؛ ملف التوليد في `quotation_pdfs/.work/<A>/quotation_<qid>.pdf` ولا ملف في الجذر؛ معرّف حساب غير عادي لا يخرج من `.work`، فارغ مرفوض؛ مصدر المولّد: سطر الكتابة بالضبط، لا `getApplicationDocumentsDirectory`، `pdf.save()`/`writeAsBytes` كما هما، `File(` مرتان فقط (قراءتا الشعار)؛ المحلّل: نسخة الحساب offline بلا طلب، حساب آخر/بلا حساب مرفوض قبل أي ملف/طلب، تنزيل الحساب والجلسة نفسيهما يُحفظ، **تبديل الجلسة/الحساب/الخروج أثناء سؤال الخادم وأثناء تنزيل البايتات** ⇒ لا حفظ ولا فتح، تبديل الحساب ⇒ حتى النسخة الحالية الموجودة محلياً لا تُفتح، الخروج ثم الحساب نفسه ⇒ تُفتح؛ **Delete Account:** يحذف PDF المرتبط + الإصدار الأقدم + بقايا التوليد + `.work` للحساب فقط، ويُبقي: ملف Bob، ملف غير مُسند (UUID)، `quotation_<millis>.pdf`، أسماء غير مطابقة، `other.pdf`، `offer_media`، `combine_pdfs/<A>`، `scanner/<A>`، `.work/<Bob>`، صندوق Bob؛ نسخة غير مقروءة (مفتاح آخر) ⇒ الجذري باقٍ و`.work` يُحذف؛ بلا نسخة ⇒ لا لمس.
- **ملاحظة اختبار (Windows):** نظام الملفات غير حساس لحالة الأحرف ⇒ `QUOTATION_…` و`quotation_…` الملف نفسه؛ استُبدل المثال (Android حساس للحالة، والنمط حساس).
- **الطفرات 13/13 التُقطت** (SHA-256 مطابق): M1 الكتابة في الجذر (بعد تشديد فحص المصدر — **نجت أولاً**)؛ M2 اسم الحساب بلا ترميز؛ M3 بلا حارس iOS؛ M4 فتح عرض حساب آخر؛ M5 فتح بلا حساب؛ M6 حفظ تنزيل متأخر (**نجت أولاً** — أُضيف اختبار التبديل أثناء تنزيل البايتات)؛ M7 بلا فحص بعد جواب الخادم؛ M8 حذف PDF بعد نسيان النسخة (الترتيب)؛ M9 حذف أي PDF بلا ملكية؛ M10 إبقاء `.work`؛ M11 نمط الاسم بلا مرساة النهاية؛ M12 نقل الجهاز يُبقي المجلد (**تخطّت أولاً** — نمط خاطئ، صُحّح)؛ M13 Auto Backup يُبقيه.
- **انحدار مركّز — 1,766 نجاح / 2 إخفاق (خط الأساس المعروف):** `test/quotation` (الحسابات `add_quotation_viewmodel_test`، PDF/الوسائط، المشاركة عبر `share_quotation_test` في `test/share`، Q-1a/Q-1b/Q-2b) + `test/services` + `test/account` + `test/share` + `test/lists` + `test/favorites` + `r6b_quotations_responsive` + `perf/list_open_baseline`. الإخفاقان: `delete_account_test` setUpAll (اسم هجرة غير موجود) و`delete_account_ui_test` (**FU-ACCOUNT-UI-BASELINE-1**) — كما في Q-2b. بعد التنسيق: الملف الجديد ⇒ 20/20.
- **Analyzer** (6 ملفات) ⇒ No issues. **Format 3.5:** الموجودة 0/0/0 و`quotation_service_test` 42 سابقة = الـ HEAD؛ الجديدة مُنسّقة. **`git diff --check`** نظيف؛ CRLF.

**الضمانات الآن:** ملفات PDF **الجديدة المولَّدة** لا تمر بالجذر (مستثناة من النسخ قبل الـ adopt)؛ المحلّل لا يفتح لحساب آخر ولا يحفظ جواباً متأخراً؛ Delete Account يحذف ملفات الحساب المُثبتة وعمله فقط.
**ما لم يتغير (الخطر باقٍ حتى Q-2c-1b):** النسخ المرتبطة (`QuotationPdfCache`) **ما زالت في الجذر وغير مشفّرة وتُنسخ احتياطياً**؛ لا ترحيل؛ لا temp للعرض (العرض من النسخة الجذرية كما كان)؛ المجلد المستثنى يحوي الآن ملفات العمل فقط.
**الحدود الباقية:** R1 (الجذر، النص الصريح، النسخ الاحتياطي) **OPEN**؛ ملفات حسابات حُذفت قبل Q-2c-1 أو بلا نسخة Q-2b **تبقى**؛ النسخ الاحتياطية التاريخية لا تُمحى؛ iOS: الحارس best effort (فشله ⇒ يبقى قابلاً للنسخ)؛ **Samsung/iOS** (الاستثناء الفعلي، الحارس، الملفات) **DEFERRED**؛ لا خادم في هذه المرحلة؛ **P4.3-ACCEPT-NONEMPTY: OPEN**.

**الحالة (Q-2c-1):** CODE_PROVEN — تبعه Q-2c-1b أدناه.

### Q-2c-1b — مخزن PDF مشفّر ملفاً بملف (الخيار E، encrypt-then-MAC) — 2026-11-07 (CODE_PROVEN؛ غير مدمج)

**موافقة المالك:** **الخيار E** (H مرفوض)، بشرط التحقق من أن البدائيات والاشتقاق والصيغة آمنة ومتوافقة مع التبعيات القائمة، وإلا STOP. **Git:** `a5b6ff9` = `origin`؛ stashes الاثنان باقيان؛ عمل Q-2c-1 محفوظ؛ `docs/ADD_DETAILS_*` مفقودان (لم يُنشآ)؛ ملفات plugin الثلاثة أعادت أوامر Flutter توليدها (لا تُدرج).

**فحص البدائيات (قبل كتابة أي ملف مشفّر) — لا تبعية ولا بدائية جديدة:** `HiveAesCipher` (hive 2.2.3، تبعية مباشرة، المستعمل لكل صناديق القوائم) = **AES-256-CBC + PKCS7**، **IV عشوائي جديد لكل تشفير من `Random.secure()`**، يكتب الـ IV أولاً؛ **حدّة موثّقة:** `encrypt` يتجاهل `inpOff` و`decrypt` يتجاهل `outOff` ⇒ الاستدعاء دائماً بإزاحة 0 (مُختبر)؛ `decrypt` يرمي عند حشو تالف (يُلتقط، وبعد التحقق من الوسم أصلاً). المفاتيح `Hive.generateSecureKey()` (32 بايت `Random.secure`، كالقوائم). HMAC-SHA256 من `crypto` (تبعية مباشرة). التخزين `SecureAccountCacheKeyStore` (Keystore/Keychain). البناء = **CBC + HMAC-SHA256 encrypt-then-MAC بمفاتيح منفصلة** (بناء معياري معروف) ⇒ **مُتابَع بلا موافقة إضافية**.

**الصيغة الدقيقة (v1):**
- المسار `<documents>/quotation_pdfs/<account>/<qid>_<mediaId>.bwqp` (UUID صغيرة فقط، وإلا رفض)؛ اسم الحساب = `QuotationPdfFiles.folderNameFor` (UUID حرفياً وإلا hex — لا يساوي `.work` أبداً).
- البايتات: `"BWQP"` (4) | `0x01` (1) | **tag** (32) | **IV** (16) | **AES-256-CBC-PKCS7 ciphertext**.
- المفاتيح: master 32 بايت لكل حساب في secure storage تحت `quotation_pdfs_key_v1_<uid>`؛ `K_enc = HMAC-SHA256(master, "broker_wallet/quotation_pdfs/v1/enc")`، `K_mac = HMAC-SHA256(master, "broker_wallet/quotation_pdfs/v1/mac")` (اشتقاق D-3 نفسه، نطاقان منفصلان؛ لا يساوي أيٌّ منهما الآخر ولا الـ master).
- الوسم: `HMAC-SHA256(K_mac, lenprefixed("bw-quotation-pdf", "1", "BWQP"‖0x01, uid, qid, mediaId, IV‖ciphertext))`؛ **يُتحقق منه بمقارنة ثابتة الزمن قبل أي فك تشفير**؛ أي ملف مشوّه/مقطوع/معدّل/مُعاد تسميته/بمفتاح آخر/لحساب آخر ⇒ «لا نسخة» **بلا نص صريح**.
- الكتابة: `<target>.<random>.tmp` في المجلد نفسه ⇒ قراءة ⇒ تحقق الوسم ⇒ فك ⇒ **مقارنة بايت ببايت مع PDF** ⇒ **ثم** rename ذري؛ أي فشل ⇒ يبقى السابق ويُحذف الـ tmp. كتابة واحدة في كل مرة لكل حساب (لا مفتاحين لحساب). `replaceOthers` (للمصدر المُصرَّح فقط) يحذف الإصدارات الأخرى **بعد** نشر الجديد؛ الترحيل لا يحذف أبداً إصداراً آخر.
- **دورة المفتاح:** يُنشأ عند أول تخزين؛ يبقى بعد الخروج؛ يُحذف في Delete Account. مخزن مفاتيح يفشل ⇒ لا قراءة ولا تخزين (`QuotationPdfVaultUnavailable`). **مفتاح مفقود** ⇒ الملفات غير مقروءة **ولا تُحذف**؛ لا يُستبدل ملف إلا بنسخة جديدة من **تنزيل مُصرَّح** (أو نشر)، و**لا رجوع إلى نسخة صريحة قديمة** حين يوجد ملف مشفّر لذلك المعرّف.
- **نسخ العرض/المشاركة:** `<temporary>/bw_quotation_view/<account>/<qid>_<random>.pdf` (مجلد الكاش/temp — خارج النسخ على Android وiOS)؛ تُحذف عند إغلاق العارض (`releasePdf`)؛ وتُكنس نسخ كل الحسابات الأقدم من **ساعة** عند كل فتح جديد، وعند Delete Account للحساب. **حدّ:** المشاركة لا تُبلغ عن انتهائها ⇒ نسختها تبقى حتى الكنس؛ تعطّل التطبيق ⇒ تبقى حتى الكنس التالي أو Delete Account؛ أثناء العرض النص صريح على القرص (لا بديل مع `PdfViewerScreen(localFile)`/`ShareLive`).

**التنفيذ:**
1. **جديد `lib/src/services/quotation_pdf_vault.dart`** — `QuotationPdfVault` (store/read/versionsOf/purge/openForViewing/release/forgetAccount) + `SecureQuotationPdfKeyStore` (وُضع في `lib/src/services/` بجانب الكاشات المشفّرة؛ حارس `quotation_legacy_removal_test` يمنع `Hive.` داخل مجلد Quotation — **لم يُعدَّل الحارس**).
2. **`quotation_service.dart`** — `pdfVault` قابل للحقن؛ **المحلّل:** نسخة عرض من المخزن ⇒ وإلا (فقط إن لم يحمل المخزن أي ملف لذلك `mediaId`) النسخة الجذرية القديمة كما كانت (فتح offline قبل الترحيل) ⇒ وإلا الخادم: التنزيل المُصرَّح يُخزَّن مشفّراً (`replaceOthers`) ثم تُحذف النسخ الجذرية لهذا العرض ثم نسخة عرض؛ فحوص الحساب/الجلسة كما في Q-2c-1 + بعد فتح نسخة العرض. **النشر:** الحساب/الجلسة يُلتقطان قبل الرفع ⇒ بعد الربط وفقط للحساب والجلسة نفسيهما: تخزين مشفّر ثم حذف النسخ الجذرية لهذا العرض وبقايا التوليد؛ ملف العمل يُحذف دائماً. **الحذف:** + `vault.purge`. **`releasePdfFile`**. **الترحيل `migrateLegacyPdfs(serverRows)`** يُستدعى مع **كل قائمة خادم كاملة** في `watchUserQuotationsLocalFirst` (لا مع `getUserQuotations` الخاص بـ Home).
3. **`quotation_pdf_cache.dart`** — `removeGenerated(qid)` فقط (لا تُكتب نسخ جديدة في الجذر بعد الآن).
4. **`quotation_pdf_files.dart`** — `folderNameFor` + `accountDirectory` (استخراج صغير؛ `workDirectory` بالسلوك نفسه).
5. **`list_quotations_viewmodel.dart`** — `releasePdf(file)`؛ **`list_quotation_view.dart`** — `await` للعارض ثم `releasePdf` (سلوك لا واجهة).
6. **`deleted_account_local_data_cleaner.dart`** — الافتراض = `QuotationPdfFiles().forgetAccount` **+** `QuotationPdfVault().forgetAccount` (المجلد المشفّر، المفتاح، نسخ العرض).

**الترحيل (D-P2/D-P3):** لكل سطر **من قائمة خادم كاملة لهذا الحساب** (`userId` = الحساب، `qid` و`pdf_media_id` الحالي): إن لم يحمل المخزن نسخة صالحة لهذا المعرّف — النسخة الجذرية `quotation_<qid>_<mediaId>.pdf` موجودة، المخزن لا يحمل **أي** إصدار آخر لهذا العرض، الملف «PDF كامل» (`%PDF-` في البداية و`%%EOF` في آخر 1 KB) ⇒ تخزين (بلا حذف لغيره) ⇒ قراءة ومقارنة ⇒ ⇒ عندها فقط حذف النسخ الجذرية لهذا العرض (الحالية، الأقدم، بقايا التوليد). إن حمل المخزن النسخة نفسها ⇒ تُقارن: مطابقة ⇒ حذف الجذرية؛ مختلفة ⇒ **لا حذف**. يتوقف عند تغيّر الحساب/الجلسة؛ idempotent بعد الانقطاع. **لا يُلمس:** ملف تالف/مقطوع، عرض بإصدار آخر في المخزن، أسطر حساب آخر، أسطر بلا PDF، أي اسم لا يسمّيه سطر. **حدّ:** ملف قديم بمعرّف ليس الحالي على الخادم **لا يُرحَّل** (لا دليل على أنه الإصدار الحالي) — يُحذف فقط بعد أن يحمل المخزن الحالي مُتحقَّقاً.

**الأدلة (شغّلها الوكيل بتفويض هذه المهمة):**
- **جديد `test/quotation/quotation_pdf_vault_test.dart` — 34/34:** round trip (250 KB)؛ تخطيط الملف (رأس، وسم، IV، كتل AES، لا `%PDF` على القرص)؛ **200 تخزين للبايتات نفسها ⇒ 200 IV و200 وسم مختلفة**؛ master لكل حساب، `K_enc ≠ K_mac ≠ master`؛ مفتاح secure storage تحت البادئة؛ حارس iOS؛ **قلب بت** في magic/version/tag/IV/أول وآخر كتلة ⇒ لا شيء؛ **مقطوع** (بايت ناقص، رأس فقط، IV فقط، فارغ) ⇒ لا شيء؛ مفتاح آخر ⇒ لا شيء والملف كما هو؛ **حساب آخر بالمفتاح نفسه** ⇒ لا شيء؛ ملف مُعاد تسميته لعرض/وسائط أخرى ⇒ لا شيء؛ مخزن مفاتيح معطّل ⇒ لا قراءة ولا تخزين؛ **مفتاح مفقود** ⇒ لا فتح، تخزين جديد يحلّ ملفه فقط، الآخر يبقى غير مقروء وغير محذوف؛ معرّفات غير UUID مرفوضة؛ **قرص ممتلئ في منتصف الكتابة** ⇒ السابق سليم ولا tmp؛ كتابة لا تُقرأ مطابقة ⇒ لا نشر ولا tmp؛ الإصدار الجديد يحلّ القديم بعد النشر؛ `replaceOthers:false` يُبقي؛ PDF فارغ مرفوض؛ نسخة العرض في مجلد الحساب وتُحذف؛ نسخة غير أصلية ⇒ لا نسخة عرض؛ كنس النسخ القديمة لكل الحسابات؛ `release` لا يحذف خارج مجلد العرض؛ `purge` لعرض واحد؛ `forgetAccount` للحساب وحده؛ قياسات.
- **جديد `test/quotation/quotation_pdf_encrypted_flow_test.dart` — 13/13:** **بعد إعادة التشغيل offline** يُفتح بلا طلب ونسخة العرض تُحذف بعد الإغلاق؛ **ملف مشفّر تالف لا يرجع أبداً إلى نص صريح** (حتى مع نسخة جذرية للمعرّف نفسه) ⇒ تنزيل مُصرَّح يستبدله والجذرية تُحذف؛ مفتاح مفقود ⇒ من الخادم فقط؛ قبل الترحيل النسخة الجذرية تُفتح offline ولا تُحذف بـ `release`؛ PDF أحدث على الخادم يُخزَّن والقديم لا يُعرض حالياً؛ **ترحيل:** مُثبت ⇒ مخزّن ومُتحقَّق ثم حذف الحالية+الأقدم+البقايا وفتح offline؛ مقطوع/ليس PDF ⇒ لا لمس؛ **قرص ممتلئ ⇒ الأصل باقٍ ثم يكتمل في القائمة التالية**؛ إعادة تشغيل بعد الختم: مطابق ⇒ حذف، مختلف ⇒ كلاهما باقٍ؛ لا نسخة أقدم بجانب إصدار آخر؛ أسطر حساب آخر/بلا PDF/أسماء غير مسماة ⇒ لا لمس؛ **تغيّر الجلسة أثناء الترحيل ⇒ الأصل لا يُحذف**؛ قائمة خادم على شاشة Quotations تبدأ الترحيل؛ **Delete Account بإعداداته الحقيقية** (path_provider مُحاكى) ⇒ مجلد A المشفّر ومفتاحه ونسخ عرضه تُحذف، B سليم.
- **حُدِّثت عمداً (تغيير عقد D-P1):** `quotation_service_test` (النشر ⇒ مشفّر لا جذري، والنسخ الجذرية لهذا العرض تُحذف ولغيره تبقى؛ التنزيل ⇒ مشفّر + نسخة عرض؛ «PDF أحدث يفوز» ⇒ المخزن يحمل الحالي فقط؛ الفشل ⇒ المخزن فارغ؛ **جديد: تغيّر الجلسة أثناء الرفع ⇒ مرتبط على الخادم، لا يُحفظ لأحد، ملف العمل محذوف**)؛ `quotation_pdf_protection_test` (التنزيل ⇒ مشفّر + نسخة عرض)؛ `add_quotation_viewmodel_test` («المنشور وحده يبقى» ⇒ **مشفّراً** تحت `quotation_pdfs/user-1/`، لا PDF صريح في الجذر).
- **الطفرات 21/21 التُقطت** (SHA-256 مطابق): V1 بلا تحقق وسم (6)؛ V2 الوسم بلا الحساب؛ V3 بلا معرّف الوسائط؛ V4 مفتاح واحد للتشفير والـ MAC؛ V5 نشر بلا قراءة مطابقة؛ V6 tmp يبقى بعد فشل (**نجت أولاً** — أصبح القرص يمتلئ بعد نصف الكتابة + فحص tmp بعد فشل التحقق)؛ V7 الإصدارات القديمة لا تُستبدل؛ V8 بلا كنس؛ V9 `release` لا يحذف؛ V10 Delete Account يُبقي المفتاح؛ V11 نسخة عرض خارج مجلد الحساب؛ S1 رجوع إلى نص صريح رغم ملف مشفّر؛ S2 التنزيل يُبقي الجذرية؛ S3 ترحيل ملف مقطوع؛ S4 نسخة أقدم بجانب إصدار آخر؛ S5 أسطر حساب آخر؛ S6 حذف بعد تغيّر الجلسة؛ S7 حذف نسخة مختلفة؛ S8 النشر يخزّن لمن سجّل الآن (**نجت أولاً** — أُضيف اختبار تغيّر الجلسة أثناء الرفع)؛ S9 القائمة لا تبدأ الترحيل؛ D1 Delete Account لا يحذف المخزن المشفّر.
- **انحدار مركّز:** التشغيل الكامل (`test/quotation` + `test/services` + `test/account` + `test/share` + `test/lists` + `test/favorites` + `r6b_quotations_responsive` + `perf/list_open_baseline`) ⇒ **1,813 نجاح / 4 إخفاقات**: خطّا الأساس المعروفان (`delete_account_test` setUpAll، **FU-ACCOUNT-UI-BASELINE-1**) + اثنان سبّبهما Q-2c-1b وأُصلحا (حارس `Hive.` ⇒ نقل المخزن إلى `lib/src/services/`؛ `add_quotation_viewmodel_test` ⇒ توقع مشفّر). بعد الإصلاح: **`test/quotation` كاملاً 336/336**؛ `test/account` + `test/share` + `test/services` ⇒ **542 / 2 (خطّا الأساس فقط)**.
- **Analyzer** (كل الملفات المعنية) ⇒ No issues. **Format 3.5:** لا انحراف جديد (`list_quotation_view` 20 = HEAD، `quotation_service_test` 42 = HEAD، `add_quotation_viewmodel_test` 261 = HEAD)؛ الجديدة مُنسّقة. **`git diff --check`** نظيف؛ CRLF.

**الأداء (M — VM الاختبار JIT، تشغيلان؛ AES بلغة Dart الصرفة؛ ليس Samsung):**
| PDF | تخزين (ختم + كتابة + تحقق + نشر) | قراءة (تحقق + فك) |
|---|---|---|
| 100 KB | 48–83 ms | 12–17 ms |
| 1 MB | 162–308 ms | 94–125 ms |
| 5 MB | 733–1,193 ms | 345–443 ms |
| 20 MB | 2,989–3,920 ms | 1,318–1,795 ms |
- يعمل على الـ main isolate؛ PDF عرض سعر نموذجي ≤ 1 MB. **قياس الجهاز (AOT) مطلوب** قبل تقرير isolate لملفات كبيرة.

**الضمانات:** لا PDF صريح جديد في الجذر (توليد في `.work` المستثنى، النشر والتنزيل ⇒ مشفّر)؛ عزل تشفيري بين الحسابات (مفتاح لكل حساب + الحساب داخل الوسم)؛ لا فتح لملف غير أصلي ولا رجوع إلى نص صريح حين يوجد ملف مشفّر؛ لا استبدال للحالي بأقدم؛ ربط الحساب والجلسة للتنزيل والنشر والترحيل والعرض؛ Delete Account يحذف المخزن والمفتاح ونسخ العرض والعمل والملفات الجذرية المُثبتة فقط. الحسابات المالية، محتوى PDF، العملة، التقريب، معرّفات الوسائط، RLS، Auth، SAD، Q-1a/Q-1b/Q-2b **بلا تغيير**.

**الحدود الباقية:**
- **ملفات جذرية قديمة** تبقى صريحة ومنسوخة احتياطياً حتى ترحيلها (يتطلب قائمة خادم للحساب)؛ غير المُسندة (عرض محذوف، حساب لا يعود، معرّف ليس الحالي بلا نسخة مشفّرة حالية، ملف تالف) **تبقى بلا لمس** (D-P4).
- **النسخ الاحتياطية التاريخية** والأجهزة المنقول إليها لا تُمحى.
- **نسخ العرض الصريحة** أثناء العرض/المشاركة وحتى الكنس (ساعة) أو Delete Account؛ لا ضمان حذف بعد تعطّل حتى الفتح التالي.
- **CBC+HMAC** يُصادِق كل ملف لكن **لا يكشف إعادة نسخة قديمة صالحة** من الحساب نفسه بالمعرّف نفسه (كالقوائم — الكائن ثابت لكل `mediaId` فلا أثر عملي).
- **iOS:** حارس الاستثناء best effort؛ **Android/iOS:** سلوك Keystore بعد إعادة التثبيت/الاستعادة، الاستثناء الفعلي من النسخ، الأداء AOT — **REAL_DEVICE_UNVERIFIED (DEFERRED)**.
- لا تغيير خادم؛ **P4.3-ACCEPT-NONEMPTY: OPEN**.

**الحالة (Q-2c-1b):** CODE_PROVEN — صُحّح بالمراجعة الأمنية النهائية أدناه (تُلغي ما سبق عن «النسخة الجذرية تُفتح قبل الترحيل»).

### المراجعة الأمنية النهائية قبل الـ commit — 2026-11-07 (CODE_PROVEN؛ غير مدمج)

**Git:** `a5b6ff9` = `origin` (0/0)؛ stashes الاثنان باقيان؛ ملفات plugin الثلاثة لم تُلمس يدوياً (يعيد Flutter توليدها)؛ `docs/ADD_DETAILS_*` لم يُنشآ.

| المجال | النتيجة | الخلل والتصحيح |
|---|---|---|
| **R1 الرجوع إلى نص صريح قديم** | **FAIL ⇒ صُحّح** | (أ) المحلّل كان يفتح النسخة الجذرية `quotation_<qid>_<mediaId>.pdf` **قبل الخادم حتى online**، بما فيها ملفات **رفضها الترحيل** (مقطوعة، أو عرض بإصدار آخر في المخزن) — ملف **غير مُصادَق** يُعرض بدل نسخة مُصرَّحة؛ (ب) **فشل مفتوح**: إن رمى سرد الإصدارات المشفّرة صار `held = {}` فرجع إلى النص الصريح رغم احتمال وجود ملف مشفّر. **التصحيح الأصغر:** حُذف الرجوع كلياً — `_localPdf` = نسخة عرض من ملف مشفّر **أصلي** أو لا شيء؛ النسخ الجذرية لا تُبلغ إلا عبر **الترحيل بدليل الخادم**، وتبقى على القرص بلا لمس حتى ذلك. **أثر سلوكي:** قبل أول قائمة خادم بعد التحديث، PDF غير مُرحَّل **لا يُفتح offline** (رسالة «PDF غير متاح» القائمة)؛ online يُنزَّل مُصرَّحاً ويُخزَّن مشفّراً وتُحذف الجذرية. الملكية الآن: حساب النموذج = الحساب المسجّل (رفض قبل أي ملف) + ملف مشفّر مربوط بالحساب/`qid`/`mediaId` داخل الوسم ⇒ لا وصول عبر تصادم `qid`/اسم. |
| **R2 التشفير والترحيل** | **PASS** | IV عشوائي جديد لكل تشفير (`HiveAesCipher.generateIv` = `Random.secure`؛ 200/200 فريدة)؛ `K_enc`/`K_mac` منفصلان بتسميتين؛ فصل النطاقات: label + version + header + uid + qid + mediaId + IV‖ciphertext؛ مقارنة ثابتة الزمن **قبل** فك التشفير؛ لا نص صريح عند فشل المصادقة (يعيد null قبل أي فك)؛ لا نشر جزئي (tmp ⇒ تحقق كامل ⇒ rename)؛ تحقق الوجهة (قراءة + مقارنة بايت ببايت) قبل حذف الأصل؛ الاستئناف idempotent؛ الإصدار الحالي لا يُستبدل بأقدم (الترحيل `replaceOthers:false` ويتخطى عرضاً بإصدار آخر؛ الاستبدال فقط لتنزيل/نشر مُصرَّح). **دقة الادعاء:** فحص `%PDF-`/`%%EOF` **ليس** مصادقة ولا إثبات إصدار — هو رفض للمقطوع فقط؛ هوية الإصدار في الترحيل = **سطر خادم** (`qid` + `pdf_media_id` الحالي) + **اسم ملف كتبه التطبيق لذلك المعرّف**؛ **المحتوى نفسه غير مُصادَق** ⇒ ملف جذري عُدِّل محلياً (جهاز مخترق) قد يُختم كما هو — خطر موروث موثّق (الخادم يحمل `media_objects.size_bytes` لكن المطابقة بالحجم لم تُضف: ليست إثباتاً وتتطلب قراءة إضافية؛ قرار لاحق إن لزم). |
| **R3 النص الصريح المؤقت** | **FAIL ⇒ صُحّح** | عزل الحساب ✓ (`bw_quotation_view/<account>/`)؛ الاستثناء من النسخ ✓ (temp/cache على Android وiOS)؛ الحذف عند إغلاق العارض ✓. **الخلل:** نسخة تبقى بعد تعطّل أو مشاركة (لا callback إتمام) كانت تُكنس فقط عند **فتح PDF تالٍ** وبعد ساعة ⇒ قد تبقى أياماً. **التصحيح:** «أول كنس في التشغيل» يحذف **كل** نسخ التشغيلات السابقة مهما كانت حديثة (كل نسخة تُنشأ بعد كنس، فلا يحتاجها عارض في هذا التشغيل)، ويُطلق عند **فتح شاشة Quotations** وعند أول فتح PDF؛ بعده: الأقدم من ساعة. **حدود باقية:** نسخة المشاركة تبقى حتى الكنس (ساعة أو التشغيل التالي)؛ أثناء العرض/المشاركة النص صريح على القرص؛ تعطّل ثم عدم فتح Quotations ⇒ تبقى حتى ذلك أو Delete Account أو تنظيف النظام للـ cache. |
| **R4 Delete Account** | **PASS بعد تحسين** | يحذف فقط: `.work/<uid>`، الملفات الجذرية المُثبتة بنسخة Q-2b المُتحقَّقة، مجلد المخزن، **المفتاح**، نسخ العرض للحساب؛ يُبقي الحسابات الأخرى، الملفات غير المُثبتة الملكية، الكاشات الست، Favorites، Toolkit (مُختبر). **تحسين:** التنظيف يعمل **مرة واحدة بلا إعادة محاولة مُخزَّنة** (تصميم المنظِّف القائم لكل الكاشات) ⇒ كان ترتيب المخزن (الملفات ثم المفتاح) يترك عند الانقطاع ملفات **قابلة للفك مع مفتاحها**؛ صار **المفتاح أولاً** ⇒ أي ملف متبقٍ غير قابل للفتح أبداً. **حدّ:** ملفات جذرية مُثبتة لم تُحذف بسبب الانقطاع تبقى (لا إعادة محاولة). |

**الأدلة الإضافية (أحمر أولاً):** `quotation_service_test` «نسخة صريحة قديمة لا تُفتح مكانها» **فشلت على الكود قبل التصحيح** (فُتح الملف المزوّر) ثم نجحت. **مُضاف/مُحدَّث:** flow +2 (غير المُرحَّل لا يُفتح: online من الخادم والجذرية تُحذف؛ offline لا يُفتح ويبقى بلا لمس — يشمل ملفاً مقطوعاً؛ فتح شاشة Quotations يكنس نسخ التشغيل السابق) — **15/15**؛ vault +2 (أول كنس في التشغيل يحذف نسخ التشغيل السابق، ونسخ هذا التشغيل الحديثة تبقى؛ المفتاح يُحذف قبل الملفات) — **36/36**؛ اختبارات «نسخة الجهاز» في `quotation_pdf_protection_test` و`quotation_service_test` و`quotation_list_local_first_test` صارت تستعمل **النسخة المشفّرة** (لم تعد الجذرية تُفتح). **طفرات المراجعة 4/4 التُقطت** (SHA-256 مطابق): R1 إعادة الرجوع إلى الجذرية (4)؛ R3a بلا حذف شامل في أول كنس (2)؛ R3b الشاشة لا تكنس (1)؛ R4 الملفات قبل المفتاح (1). (طفرة S1 السابقة صارت بلا موضوع: الكود حُذف.) **الانحدار:** `test/quotation` + `test/account` + `test/share` ⇒ **820 نجاح / 2** (خطّا الأساس المعروفان فقط)؛ الأجنحة الخمسة المعنية بعد التنسيق ⇒ **122/122**. **Analyzer** ⇒ No issues؛ **Format 3.5** لا انحراف جديد (`quotation_service_test` 42 = HEAD)؛ **`git diff --check`** نظيف؛ CRLF.

**الحدود الأمنية والجهاز الباقية:** نسخ جذرية قديمة صريحة ومنسوخة احتياطياً حتى ترحيلها (وغير المُسندة/التالفة تبقى للأبد بلا لمس — D-P4)؛ الترحيل يختم محتوى غير مُصادَق (بدليل هوية الخادم فقط)؛ النسخ الاحتياطية التاريخية؛ نسخ العرض/المشاركة الصريحة حتى الكنس؛ لا إعادة محاولة لتنظيف Delete Account المنقطع؛ CBC+HMAC لا يكشف إعادة نسخة أصلية أقدم بالمعرّف نفسه؛ أداء AES بلغة Dart على الـ main isolate؛ **D-57 (Samsung/iOS)** و**P4.3-ACCEPT-NONEMPTY: OPEN**.

**الحالة:** **Q-2c (1 + 1b + المراجعة) = CODE_PROVEN — REAL_DEVICE_UNVERIFIED.** **NOW:** موافقة المالك النهائية على commit واحد لـ Q-2c. **NEXT:** D-57 على Samsung عند جلسة الأجهزة المؤجلة. **STOP:** لا commit/push؛ لا Offline Media/Smart Map/Toolkit/Offline Writes.

**تحديث Git:** Q-2c أُودع `45fa169` والمالك دفعه (= `origin`).

---

## 7AZ) M0 — تدقيق الوسائط والتفاصيل Offline — 2026-11-07 (AUDIT؛ SOURCE-READ؛ لا تغيير كود)

**Git (مُتحقَّق):** `perf/phase-1-startup-baseline` @ `45fa169` = `origin` (0/0)؛ stashes الاثنان باقيان؛ المعدّل فقط ملفات plugin الثلاثة (مُعاد توليدها، لم تُلمس)؛ `docs/ADD_DETAILS_*` **ما زالا مفقودين** (لم يُنشآ). **هذا القسم وحده تغيّر.**
**طبيعة الدليل:** قراءة المصدر الحي + مصدر الحزم في `C:/DevCaches` (flutter_cache_manager 3.4.2، hive 2.2.3) + الـ Worker (قراءة فقط). **لا اختبار ولا جهاز ولا طلب مستضاف**؛ كل زمن = **NOT MEASURED**. يحدّث §7AP (2026-11-04) بما تغيّر منذه: Favorites مشفّرة (§7AQ)، Search محلي أولاً (§7AR)، Quotations (§7AV–§7AY).

### 1) خط الوسائط الفعلي (S)
- **كاش واحد مشترك:** لا `Config` مخصص في أي مكان ⇒ كل الصور تمر بـ **`DefaultCacheManager`** (مفتاح `libCachedImageData`؛ **30 يوماً / 200 ملف لكل التطبيق**). **البايتات** في `getTemporaryDirectory()` (Android: cache dir؛ iOS: Caches) ⇒ **يمسحها النظام**، خارج النسخ الاحتياطي. **فهرسه** SQLite `libCachedImageData.db` في **`getApplicationSupportDirectory()`** (Android `files/`؛ iOS Application Support) ⇒ **يبقى بعد مسح الملفات ويُنسخ احتياطياً افتراضياً**، ويخزّن لكل مدخل `key` **و`url` الأصلي = الرابط الموقّع** (`CacheObject.columnUrl`).
- **الهوية الثابتة:** Offer/Owner = `offer-media:<owner>:<mediaId>` (`offerMediaCacheKey`، مربوط بالحساب)؛ ملصق الفيديو `<key>:poster`؛ Profile = `profile_media_id` وحده. خريطة «مفتاح ⇒ مسار ملف» في صندوق Hive **`url_mapping`** (`mediaId::<key>`)، وكتالوج وسائط كل عرض/مالك `offerMediaCatalog::<owner>::<offer>` في **`local_media`** — الصندوقان في `app_flutter/` **غير مشفّرين وغير مستثنيين من النسخ**.
- **`buildOfflineAwareImage`:** (1) ملف من `url_mapping` موجود ⇒ `Image.file` بلا شبكة؛ (2) مسار URL محلي قديم؛ (3) لا رابط ⇒ **placeholder حتى لو كان الكاش يحمل البايتات بالمفتاح نفسه** (الخريطة وحدها تقرّر)؛ (4) `CachedNetworkImage(url, cacheKey)`.
- **التخزين بالبايتات:** `ensureMediaIdCached` ⇒ `getSingleFile(signedUrl, key)` **بمهلة 5 ث** ثم الخريطة؛ الأصول التي رفعها هذا الجهاز ⇒ `app_flutter/offer_media` (**مستثنى**)؛ صور Profile التي رفعها هذا الجهاز ⇒ **`app_flutter/profile_media` (غير مستثنى ⇒ تُنسخ احتياطياً)**؛ الملصقات ⇒ `offer_media` (مستثنى).
- **الروابط الموقّعة:** GET TTL **900 ث** (`GET_URL_TTL_SECONDS`، worker.js)؛ في الذاكرة `OfferMediaUrlCache` بهامش 60 ث؛ تُجدَّد عند الطلب (`refreshSignedUrl` للفيديو).
- **مسارات تبقى مفتاحها الرابط (تدور مع كل توقيع ⇒ cache miss وتكرار):** `OfflineMediaService.getImageProvider` (`cacheKey: imageUrl`، يستعمله `views/Widgets/favorite_card.dart`)؛ precache بـ `imageUrl` في `favorites_card.dart`/`search_result_card.dart` (المسار البديل)؛ `universal_media_viewer.dart` و`unified_media_preview_grid.dart:476` و`map_view.dart:1159` (`CachedNetworkImage` بلا `cacheKey`).
- **الفيديو:** التشغيل `networkUrl` برابط موقّع؛ `getVideoFile` يعيد ملفاً محلياً **فقط لما رفعه هذا الجهاز** (خريطة URL/`local://`)؛ **لا تنزيل للفيديو الكامل أبداً** ⇒ لا تشغيل offline لفيديو لم يرفعه الجهاز (مطابق للسياسة).
- **حدّ أساسي:** الإقلاع البارد offline **يتوقف عند بوابة الجلسة (Retry)** (P1) ⇒ «offline بعد إعادة التشغيل» غير ممكن لأي شاشة؛ الـ offline الواقعي = تطبيق بدأ بشبكة ثم انقطعت، أو استئناف.

### 2) التوفر offline حسب الشاشة (داخل جلسة معتمدة)
| الشاشة | السجل | الصور | الفيديو | يحتاج شبكة |
|---|---|---|---|---|
| **Profile avatar** | لقطة `cached_profile_snapshot_v1` تحفظ `profileMediaId` (لا رابط) | نعم إن بقيت الخريطة والملف (`profile_media` أو cache)؛ `warmMediaIdMapping` يرمّم الخريطة من الكاش؛ انتهاء الرابط لا يهم | — | أول تنزيل؛ بعد مسح النظام للـ cache |
| **Offers/Owners (قوائم)** | الكاش المشفّر (P2/D-3) | البطاقات بلا صور (أيقونات) | — | التحديث |
| **Offer/Owner Details** | النموذج المُمرَّر يُعرض أولاً | الكتالوج المحلي يرسم ما رُئي سابقاً في الإطار الأول؛ ثم الصف الموثوق + روابط موقّعة **بالتوازي**؛ الجيل يرفض المتأخر؛ فشل ⇒ يبقى المعروض + إعادة محاولة | ملصق محفوظ إن وُلِّد؛ التشغيل يحتاج شبكة | وسائط لم تُفتح سابقاً، كل فيديو |
| **Favorites** | مشفّرة لكل حساب (§7AQ)؛ البطاقة تحفظ **المفتاح + isVideo** (لا رابط) | بالهوية إن وُجد مدخل في الخريطة؛ وإلا المسار البديل برابط ⇒ أيقونة offline (**FU-FAV-MEDIA-NO-IDENTITY**) | ملصق إن وُجد | ما لم يُرَ |
| **Search** | من الكاشات الست المشفّرة (P4.5a) | `SearchCardMediaResolver`: المحفوظ فوراً (الكتالوج)، وإلا توقيع عند الظهور (3 متوازية، صلاحية 5 د، فشل 30 ث) | ملصق إن وُجد | كل ما لم يُحفظ |
| **Map** | ذاكرة 5 د | بالهوية حيث تُعرف، وإلا رابط بلا مفتاح | — | بلاطات Google دائماً |
| **Plan files** | — | `temp/plan_attachments` بعد فحص النوع ⇒ يُفتح offline إن نُزِّل | — | أول فتح |
- **سبب جذري لغياب الوسائط offline في Search/Favorites/التفاصيل لما لم يُفتح:** الكاشات المشفّرة لـ Offers/Owners **لا تحفظ `mediaObjectIds`** (و`mediaUrls` يُفكّ فارغاً) ⇒ السجل المحفوظ **بلا هوية وسائط**؛ الهوية تأتي فقط من الكتالوج غير المشفّر الذي يُكتب عند فتح التفاصيل أو الرفع.

### 3) المخاطر الأمنية/الخصوصية (مرتبة؛ للقرار)
1. **FU-MEDIA-INDEX-BACKUP (جديد، متوسط):** `libCachedImageData.db` (Application Support، **يُنسخ احتياطياً** على Android وiOS) يحفظ **روابط R2 موقّعة** (صالحة 15 د بعد الإصدار) + مفاتيح بمعرّفات الحسابات والوسائط + أسماء الملفات. خطر الرابط قصير، لكن **الرابط الموقّع يُحفظ على القرص في مكان منسوخ** (يخالف روح قاعدة «الروابط الموقّعة عرض مؤقت»).
2. **FU-PROFILE-MEDIA-BACKUP (جديد، متوسط):** `app_flutter/profile_media/<mediaId>.<ext>` (صورة الملف الشخصي الأصلية لمن رفعها هذا الجهاز) **غير مستثنى** ⇒ بايتات خاصة في النسخ.
3. **FU-MEDIA-MAP-BACKUP (قائم §7AP):** `url_mapping`/`local_media` غير مشفّرة ومنسوخة: معرّفات حسابات/عروض/وسائط + كتالوجات + مسارات (لا بايتات ولا روابط).
4. **FU-PLAN-CLEANUP (قائم):** `temp/plan_attachments` لا يكنسه Delete Account (جزء Quotations من FU-PLAN-QUOTE-CLEANUP أُغلق بـ Q-2c).
5. **البايتات المنزّلة غير مشفّرة** في cache (مستثنى من النسخ، قابل للمسح) — مثل اليوم؛ عزل الحسابات **منطقي** بالمفتاح (`<owner>`) لا تشفيري؛ تبقى بعد الخروج (مقصود للفتح offline بعد عودة الحساب).
6. **Profile key غير مقرون بالحساب** (`mediaId` UUID فريد ⇒ تصادم غير واقعي)؛ Delete Account: الحساب المسجّل ⇒ كل خرائط/كاش Profile + `profile_media`؛ غيره ⇒ معرّفاته فقط ✓.
7. **Delete Account للوسائط:** Offer/Owner بالبادئة `<owner>` (كتالوج، أصول، كاش، ملصقات) ✓ مع تقرير جزئي؛ **لا يمسح** مدخلات فهرس `libCachedImageData.db` لمسارات الرابط-مفتاحاً، ولا Plan.

### 4) الأداء (S — أسباب قابلة للقياس؛ NOT MEASURED)
- **P-1 (أعلى أثر محتمل):** مسارات الرابط-مفتاحاً ⇒ **تنزيل جديد مع كل توقيع** + نسخ مكررة تستهلك **حصة 200 ملف المشتركة** فتطرد مدخلات الهوية الثابتة ⇒ صور «مخزّنة» تختفي.
- **P-2:** `getSingleFile` بمهلة **5 ث** ⇒ صورة كبيرة على شبكة بطيئة لا تُحفظ أبداً ⇒ إعادة تنزيل في كل فتح للتفاصيل.
- **P-3:** فتح تفاصيل بلا بايتات محلية = قراءة الصف + طلب توقيع (متوازيان) + N تنزيلات صور.
- **P-4:** `CurrentUserAvatar` يرسم `Image.file`/الصورة **بلا `cacheWidth`** ⇒ فك تشفير الصورة الأصلية بكامل دقتها لدائرة صغيرة في كل إقلاع وشاشة (البطاقات `cacheWidth: 600`، المصغّرات 120، رأس المعرض محسوب ✓).
- **P-5:** Search بعد إعادة التشغيل: ذاكرة الروابط فارغة ⇒ توقيع جديد لكل بطاقة غير محفوظة (3 متوازية).
- **P-6:** ملصق الفيديو يُولَّد بقراءة نطاقات بايت عبر الرابط حتى يُحفظ (ثم محلي)؛ إعادة المحاولة بعد دقيقتين.
- **قياس مقترح (اختباري فقط، في M1):** عدّاد طلبات `getSingleFile`/التوقيع وإصابات الخريطة لكل فتح تفاصيل، ونسبة hit/miss بعد «إعادة توقيع» محاكاة. Samsung: زمن أول صورة في التفاصيل والـ avatar (DEFERRED).

### 5) ترتيب التنفيذ المقترح (مرحلة واحدة في كل مرة)
- **M0.5 — إصلاح الخصوصية أولاً (صغير):** استثناء `app_flutter/profile_media` و`app_flutter/url_mapping.hive|.lock` و`app_flutter/local_media.hive|.lock` من النسخ (XML) + استثناء `libCachedImageData.db` (`domain="file"`) + iOS عبر الحارس القائم. **الملفات:** `backup_rules.xml`، `data_extraction_rules.xml`، نقطة إقلاع واحدة للحارس على iOS. **خطر:** استعادة بلا كتالوجات ⇒ يُعاد بناؤها من الخادم (لا فقد). **اختبارات:** نص XML حرفياً + القديمة كما هي. **أثر:** لا روابط/معرّفات/صور شخصية في النسخ الجديدة (لا يمحو القديمة).
- **M1 — هوية الصور والكاش:** CacheManager **مخصص للوسائط الخاصة** (مفتاح منفصل، حصة أكبر، مدة أطول) يُستعمل بالهوية فقط؛ **إزالة مسارات الرابط-مفتاحاً** للوسائط الخاصة (تبقى للروابط العامة القديمة فقط)؛ ترميم الخريطة من الكاش حين يغيب الرابط؛ مهلة تنزيل منفصلة عن مهلة العرض؛ `cacheWidth` للـ avatar؛ عدادات اختبار. **الملفات:** `offline_media_service.dart`، `current_user_avatar.dart`، `favorites_card.dart`، `search_result_card.dart`، `views/Widgets/favorite_card.dart`، `map_view.dart` (مسار البديل فقط). **خطر:** تغيير مكان الكاش ⇒ أول فتح يعيد التنزيل مرة. **قرار:** حصة/مدة الكاش؛ هل يُصفّى فهرس الروابط القديم.
- **M2 — تفاصيل Offers/Owners offline:** حفظ **`mediaObjectIds` + النوع** في الكاشات المشفّرة لـ Offers/Owners (يغيّر **محتوى** الحمولة v2، لا الغلاف/HMAC — **يحتاج موافقة صريحة**: «تنسيق القوائم المشفّرة» محمي) أو نقل الكتالوج إلى تخزين مشفّر؛ معرض التفاصيل يرسم المحفوظ بلا شبكة؛ لا تنزيل مسبق.
- **M3 — وسائط Favorites/Search:** إغلاق FU-FAV-MEDIA-NO-IDENTITY باشتقاق الوسائط من الهوية المحفوظة (بعد M2)؛ placeholder ثابت بلا تحميل لا ينتهي.
- **M4 — Avatar:** `cacheWidth`، عزل الحساب عند التبديل، اختبار «مسح النظام للـ cache» ⇒ ترميم.
- **M5 — سياسة الفيديو:** تشغيل الملفات المحلية الموجودة فقط (رفع هذا الجهاز)؛ أي تنزيل فيديو للعرض offline = قرار منتج/تخزين/تشفير منفصل (حجم، نسخ، Delete Account).
- **(مستقل) FU-PLAN-CLEANUP:** كنس `temp/plan_attachments` للحساب في Delete Account.

### 6) قرارات المالك المطلوبة
- **D-M1:** تنفيذ **M0.5** (استثناءات النسخ للخصوصية) قبل M1 — **موصى**.
- **D-M2:** إزالة الروابط الموقّعة من فهرس الكاش للوسائط الخاصة (CacheManager مخصص بـ `url` غير موقّع/مُطهَّر أو تنظيف الفهرس) — **موصى ضمن M1**.
- **D-M3:** حصة ومدة كاش الوسائط الخاصة (مثلاً 1,000 ملف / 90 يوماً، أو حد بالحجم) — قرار تخزين.
- **D-M4:** حفظ هوية الوسائط في الكاشات المشفّرة لـ Offers/Owners (تغيير محتوى الحمولة) **أو** تشفير الكتالوج — **مطلوب لـ M2/M3**.
- **D-M5:** هل تُشفَّر بايتات الصور المنزّلة (اليوم صريحة في cache مستثنى) — توصية: **لا الآن** (مستثناة، قابلة للمسح، إعادة تنزيل رخيصة)؛ إعادة تقييم بعد M1.
- **D-M6:** لا تنزيل فيديو للعرض offline (افتراض) — تأكيد.
- **D-M7:** إضافة كنس Plan إلى Delete Account.

**الحدود المفتوحة المحفوظة:** P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 (Samsung/iOS) **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية (FU-AUTH-BASELINE-7، `delete_account_test` setUpAll، FU-ACCOUNT-UI-BASELINE-1)؛ قيود PDF عروض الأسعار القديمة (§7AY)؛ فجوات Smart Map (ذاكرة 5 د، البلاطات) وToolkit (قبول جهاز) offline.

**الحالة (M0):** AUDIT مكتمل (SOURCE-READ). **D-M1 موافق ⇒ M0.5 أدناه.**

### M0.5 — حماية الوسائط الخاصة من النسخ الاحتياطي — 2026-11-07 (CODE_PROVEN؛ غير مدمج)

**الموافقة:** **D-M1** (M0.5 أولاً) — استثناء من النسخ فقط؛ لا تشفير ولا ترحيل ولا حذف. **Git:** `45fa169` = `origin` (0/0)؛ stashes الاثنان باقيان؛ تعديل M0 على هذا الملف محفوظ؛ ملفات plugin الثلاثة معدّلة (يعيد Flutter توليدها، لم تُلمس)؛ `docs/ADD_DETAILS_*` لم يُنشآ.

**المواقع المُتحقَّقة (S — من مصدر الحزم):**
- `Hive.initFlutter()` بلا مجلد فرعي (`main.dart`) ⇒ `getApplicationDocumentsDirectory` (Android: `getDir("flutter")` = **`app_flutter/`**، النطاق `root`؛ iOS: Documents). ملفات الصندوق في hive 2.2.3: **`<name>.hive`** و**`<name>.lock`** و**`<name>.hivec`** (أثناء الضغط). الصندوقان **مشتركان بين الحسابات** (المفاتيح تحمل الحساب): `url_mapping` (خريطة الهوية `mediaId::`) و`local_media` (كتالوجات `offerMediaCatalog::<owner>::<offer>`).
- `profile_media` = `adoptLocalFileForMediaId` الافتراضي تحت المستندات (`app_flutter/profile_media`)؛ `offer_media` (مستثنى على Android سابقاً).
- فهرس الصور: flutter_cache_manager **3.4.2**، `DefaultCacheManager.key = 'libCachedImageData'`؛ على Android/iOS `CacheObjectProvider` (sqflite) ⇒ **`getApplicationSupportDirectory()/libCachedImageData.db`** (Android `context.filesDir` = `files/`، النطاق **`file`**؛ iOS Library/Application Support). sqflite: **WAL معطّل افتراضياً** (`WAL_ENABLED_BY_DEFAULT = false`، ولا meta في الـ manifest) ⇒ الملف المرافق `-journal` المؤقت؛ أُدرج `-wal`/`-shm` احتياطاً (استثناء ملف غير موجود لا أثر له). **قواعد Android تقبل مسار ملف ⇒ استثناء ضيق ممكن، بلا استثناء `files/` ولا Application Support كاملاً.**

**التنفيذ (5 ملفات + اختبار):**
1. **`backup_rules.xml`** (`full-backup-content`) و**`data_extraction_rules.xml`** (`cloud-backup` **و** `device-transfer`): **11 استثناء** — `root`: `app_flutter/profile_media`، `app_flutter/url_mapping.hive|.hivec|.lock`، `app_flutter/local_media.hive|.hivec|.lock`؛ `file`: `libCachedImageData.db|.db-journal|.db-wal|.db-shm` + تعليقات. **لا سطر حُذف**؛ كل الاستثناءات السابقة (offer_media وطابورها، scanner، mlkit، combine_pdfs، image_to_pdf، signature_pdfs، offline_lists، quotation_pdfs، cached_favorites) كما هي.
2. **جديد `lib/src/services/private_media_backup_exclusions.dart`** — `excludeExisting()`: يطلب من **الحارس القائم** (`PlatformScannerBackupGuard`، قناة `AppDelegate.swift` — **بلا تغيير native**) وضع `isExcludedFromBackup` على كل عنصر **موجود** من القائمة نفسها (+ `offer_media` الذي لم يكن مُعلَّماً على iOS)؛ لا يُنشئ ولا يغيّر ولا يحذف شيئاً؛ لا يرمي. على Android الحارس لا يفعل شيئاً (القواعد تصريحية).
3. **`lib/main.dart`** — `unawaited(PrivateMediaBackupExclusions().excludeExisting())` بعد `OfflineMediaService.instance.initialize()` (الصناديق مفتوحة) ⇒ يُعلَّم **ما أنشأته نسخ سابقة** عند كل إقلاع.
4. **`offline_media_service.dart`** — `backupGuard` قابل للحقن، وسطر واحد بعد ضمان مجلد `adoptLocalFileForMediaId` (profile_media/offer_media) ⇒ المجلد الجديد يُعلَّم **عند إنشائه** لا عند الإقلاع التالي. النسخ والخريطة **بلا تغيير**.

**الأدلة:** **أحمر أولاً** (الواجهة غير موجودة، والقواعد بلا المسارات). **جديد `test/services/private_media_backup_test.dart` — 10/10:** القواعد الثلاث تحوي الـ 11 **وكل السابقة** وعددها بالضبط (لا توسيع)؛ لا استثناء لـ `app_flutter`/`.`/فارغ ولا `<include>`؛ الأسماء = ما يستعمله الكود (`DefaultCacheManager.key`، أسماء الصناديق، `profile_media`، `Hive.initFlutter()` بلا مجلد فرعي)؛ الإقلاع يعلّم بعد فتح الصناديق؛ iOS: العناصر الموجودة فقط تُعلَّم، **البايتات والأوقات بلا تغيير، لا شيء يُنشأ**؛ حارس فاشل/مجلد غير متاح ⇒ لا رمي؛ `adoptLocalFileForMediaId` لـ profile_media وoffer_media: نسخ وخريطة كما كانا، الأصل باقٍ، المجلد مُعلَّم. **الطفرات 9/9 التُقطت** (SHA-256 مطابق): Auto Backup يُبقي profile_media؛ cloud-backup يُبقي url_mapping؛ **device-transfer وحده** يُبقي الفهرس؛ استثناء واسع لـ `app_flutter`؛ تعليم العناصر غير الموجودة؛ اسم فهرس خاطئ؛ profile_media غير مُعلَّم؛ مجلد adopt غير مُعلَّم؛ الإقلاع لا يعلّم. **انحدار مركّز — 620 نجاح / 1:** حراس مصدر Scanner/Combine/Images-to-PDF/Signature، `favorites_encrypted_cache_test`، `offline_lists_storage_test`، `quotation_pdf_protection_test`، `test/services`، `test/offers` كاملاً، `owner_media_test`، `favorite_card_media_test`، `favorites_viewmodel_initial_load_test`، `search_card_media_test`، `last_known_good_profile_test`، `share_media_preview_test`، `single_active_session_source_test`، `plan_attachment_source_guards_test` — الإخفاق الوحيد **FU-COMBINE-GUARD-1** (OPEN، مستقل؛ لم يُلمس أي ملف Combine). **Analyzer** (4) ⇒ No issues؛ **Format 3.5:** `main.dart` و`offline_media_service.dart` 0 = HEAD، الجديدان مُنسّقان؛ **`git diff --check`** نظيف؛ CRLF.

**سلوك الوسائط بلا تغيير:** لا مسح للكاش ولا حذف للصناديق ولا ترحيل ولا تغيير معرّفات/روابط/واجهات/معارض/تشفير/حدود الكاش/تنزيل/تنقل/Auth/SAD/Delete Account/PDF؛ الصور المحفوظة متاحة بالشروط نفسها؛ عزل الحسابات A/B كما هو (لا تغيير مفاتيح).

**الحدود الأمنية (لا تُغلق مشكلة خصوصية الوسائط):** الاستثناء **لا يشفّر** — البيانات الوصفية والبايتات تبقى صريحة داخل حماية تخزين التطبيق؛ **النسخ الاحتياطية التاريخية لا تُمحى**؛ ما نُقل إلى جهاز آخر لا يُزال؛ **الروابط الموقّعة المنتهية في النسخ القديمة** تبقى بيانات تاريخية؛ iOS: التعليم best effort (فشل القناة ⇒ يبقى قابلاً للنسخ)، ويُفقد إن أعادت مكتبة إنشاء الملف — يُعاد عند الإقلاع التالي؛ `-journal` يُنشأ ويُحذف أثناء الكتابات (مستثنى على Android بالاسم، وعلى iOS فقط إن وُجد عند الإقلاع)؛ `offline_lists` على iOS ما زال بلا تعليم (موروث، مشفّر، خارج نطاق M0.5). **Android/iOS الفعلي REAL_DEVICE_UNVERIFIED** (يُضاف إلى D-57: نسخة `bmgr`/سحابية ونقل جهاز ونسخ iCloud لا تحوي هذه المسارات).

**القرارات الباقية:** **D-M2…D-M7 معلّقة** (لم يُنفَّذ منها شيء)؛ FU-PLAN-CLEANUP مفتوح. **المحفوظ:** P4.3-ACCEPT-NONEMPTY **OPEN**، D-57 DEFERRED، إخفاقات Auth/Delete Account التاريخية، قيود PDF عروض الأسعار، فجوات Smart Map وToolkit.

**الحالة (M0.5):** CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ أُودع `e8162a9` والمالك دفعه (= `origin`).

### M1a — هوية وسائط ثابتة وكاش صور موثوق — 2026-11-07 (DESIGN؛ SOURCE-READ؛ لا تغيير كود)

**Git (مُتحقَّق):** `e8162a9` = `origin` (0/0)؛ stashes الاثنان باقيان؛ ملفات plugin الثلاثة فقط معدّلة (مُعاد توليدها)؛ `docs/ADD_DETAILS_*` لم يُنشآ. **هذا القسم وحده تغيّر.** المصدر: flutter_cache_manager **3.4.2** (`C:/DevCaches`) + الكود الحي.

**1) سلوك الكاش الفعلي (S — من مصدر الحزمة):**
- **`cacheKey` يستبدل المفتاح فقط، لا الرابط:** كل تنزيل يكتب `CacheObject.copyWith(url: url)` (`web_helper.dart:105`) ⇒ عمود **`url` في `libCachedImageData.db` يحمل آخر رابط موقّع** لذلك المفتاح (إلى جانب `key`، `relativePath`، `eTag`، `validTill`، `touched`، `length`). **⇒ نعم، الروابط الموقّعة تبقى في بيانات وصفية دائمة** (مستثناة من النسخ منذ M0.5، لكنها على القرص؛ صالحة 900 ث بعد إصدارها).
- **البحث بالهوية بلا رابط ممكن:** `getFileFromCache(key)` لا يحتاج رابطاً ولا يفحص الصلاحية — يستعمله `ensureMediaIdCached`/`warmMediaIdMapping` اليوم (محلي أولاً صحيح).
- **الصلاحية:** بلا `Cache-Control` من الاستجابة ⇒ `validTill = الآن + 7 أيام` (`file_service.dart:91`). بعدها: `getSingleFile` **يعيد التنزيل** (ويفشل offline رغم وجود البايتات)؛ `getFileStream` (يستعمله `CachedNetworkImage`) يعرض المحفوظ أولاً ثم **يحاول التنزيل في كل عرض**، وعند **404 يحذف المدخل**.
- **الإخلاء:** `touched` يُحدَّث عند الوصول؛ ما زاد عن **200** يُخلى الأقدم لمساً، وما لم يُلمس **30 يوماً** يُحذف (`getObjectsOverCapacity`/`getOldObjects`)؛ تنظيف كل ≥10 ث بعد العمليات.
- **التكرار:** المدخل فريد **بالمفتاح**؛ المسارات التي مفتاحها الرابط تنشئ **مدخلاً جديداً لكل توقيع**. **بعد إعادة التشغيل:** الفهرس باقٍ (Application Support)، البايتات باقية ما لم يمسح النظام مجلد temp.
- **تصنيف مسارات الرابط-مفتاحاً (M0):** **ميتة** (بلا مستدعين): `views/Widgets/favorite_card.dart` ⇒ `OfflineMediaService.getImageProvider`، `UniversalMediaViewer`، `mapUrlToLocalFile`. **قديمة لروابط عادية (Firebase/تحرير)**: `MediaPreviewItem.fromUrl` (`media_upload_widget` ⇐ `uploadedFileUrls`)، بديل `map_view` (`locationInfo.mediaUrl`) — يُتحقق في M1c أنها لا تحمل روابط R2. **حيّة وقد تحمل رابطاً موقّعاً:** مسار `imageUrl` البديل في `favorites_card`/`search_result_card` (FU-FAV-MEDIA-NO-IDENTITY). المسارات الخاصة الرئيسية (`PrivateCardMedia`، المعرض، العارض الكامل، الشبكة لعناصر Offer) **تمرّر المفتاح الثابت**.
- **بايتات فعلية مقابل خريطة:** `buildOfflineAwareImage` يرسم بلا شبكة **فقط** عبر خريطة `url_mapping` المتزامنة؛ الكاش وحده (async) لا يُستشار في الإطار الأول.

**2) الهوية القانونية المقترحة:** `media_objects.id` = **UUID مفتاح أساسي** و`owner_id NOT NULL` ⇒ **فريد عالمياً ولكل معرّف مالك واحد**. لا إصدار في الخادم غير المعرّف نفسه (الاستبدال = معرّف جديد) ⇒ **البايتات لكل معرّف ثابتة**. الصيغة: **إبقاء `offer-media:<owner>:<mediaId>` كما هي** (Offers وOwners — مربوطة بالحساب، تعمل بها الكتالوجات والخرائط اليوم)، الملصق `<key>:poster` كما هو، و**جديد للملف الشخصي `profile-media:<uid>:<mediaId>`** (بدل `mediaId` العاري). لا متغيّرات حجم في الخادم ⇒ متغيّر الدقة يبقى قراراً **عند الفك** (`cacheWidth`) لا مفتاحاً.

**3) البحث المحلي أولاً:** (1) الشاشة تعرف `(uid الحالي، المفتاح)` من سجل حسابها؛ **رفض أي مفتاح مالكه ≠ uid الحالي**؛ (2) خريطة `url_mapping` المتزامنة ⇒ ملف موجود ⇒ يُرسم بلا رابط؛ (3) وإلا `getFileFromCache(key)` (async) ⇒ يرمّم الخريطة؛ (4) وإلا online: توقيع مُصرَّح ثم **تنزيل واحد** يُخزَّن بالمفتاح؛ (5) offline وغير موجود ⇒ placeholder القائم؛ (6) ملف مفقود/تالف (فك فاشل) ⇒ يُعامل كغائب، يُعاد عند الاتصال. **انتهاء الرابط لا يُبطل البايتات المُصرَّح بها سابقاً**؛ لا عرض لسجل حساب آخر لأن المفتاح يحمل المالك والسجلات تأتي من قوائم الحساب (RLS/الكاش المشفّر).

**4) خيارات التخزين:**
| | A. `DefaultCacheManager` بمفاتيح ثابتة | **B′. CacheManager خاص `bwPrivateMedia` + `FileService` مخصص** | C. هجين يدوي (ملفات `offer_media`/`profile_media` + خريطة) |
|---|---|---|---|
| روابط موقّعة في الفهرس | **نعم دائماً** (`copyWith(url)`) | **لا**: الكاش يرى رابطاً زائفاً ثابتاً `bw-private-media://v1/<key>`؛ الـ `FileService` يطلب رابطاً موقّعاً طازجاً **داخل** التنزيل ولا يعيده | لا (لا فهرس حزمة) |
| تكرار/7 أيام | التكرار يزول بالمفاتيح؛ إعادة المحاولة كل 7 أيام باقية | الاستجابة تعيد `validTill` بعيداً (المعرّف ثابت البايتات) ⇒ لا تنزيل دوري | يدوي |
| الإخلاء/الحصة | مشتركة مع كل شيء (200) | **منفصلة** (تبقى 200/30 الآن حسب التعليمات؛ قابلة للضبط لاحقاً) | يدوي بالكامل |
| عزل الحساب / Delete Account | منطقي بالمفتاح؛ لا كنس بالبادئة إلا عبر الكتالوج | منطقي بالمفتاح + `repo.getAllObjects()` لكنس بادئة الحساب | ممكن |
| النسخ الاحتياطي | M0.5 يغطي `libCachedImageData.db` | **يتطلب استثناءً جديداً** لـ `bwPrivateMedia.db` (+journal) في القواعد الثلاث + iOS (قرار) | المجلدات مستثناة |
| الفساد | الحزمة تتعامل | الحزمة تتعامل | يدوي |
| التعقيد/الخطر | أقل؛ لا يحل الروابط | **متوسط، ضمن نقاط امتداد الحزمة (Config/FileService) — لا تبعية ولا تشفير جديد** | الأعلى |
**التوصية: B′.** الوحيد الذي **يمنع كتابة الروابط الموقّعة** في بيانات دائمة ويُنهي إعادة التنزيل الدورية، مع إبقاء البايتات في temp (يمسحها النظام، خارج النسخ) و**بلا تشفير جديد** (D-M5 يبقى قراراً منفصلاً — B′ لا يجعل البايتات أكثر انكشافاً من اليوم).

**5) توافق الموجود (لا حذف تلقائي):** مدخلات `url_mapping` (`mediaId::<key>`) ⇒ تبقى ويُعاد توجيهها عند الترحيل؛ `local_media` (الكتالوجات) ⇒ بلا تغيير؛ **بايتات `DefaultCacheManager`** ⇒ تُنسخ إلى الكاش الجديد عبر `putFile(pseudoUrl, bytes, key)` **فقط** لمفاتيح **مُثبتة للحساب الحالي** (`offer-media:<uid>:` أو `profile_media_id` الحالي من الملف الشخصي)، ثم قراءة مطابقة، ثم تحديث الخريطة؛ المدخل القديم **يبقى** (يُخليه الكاش الافتراضي طبيعياً) ما لم يقرر المالك كنسه (D-M1a-3)؛ مفاتيح غير مُثبتة الملكية ⇒ لا تُلمس ولا تُنسب. أصول `profile_media`/`offer_media` والملصقات ⇒ تبقى ملفات محلية كما هي (الخريطة تشير إليها). فشل الترحيل ⇒ القديم سليم.

**6) الجودة والأداء (S؛ NOT MEASURED):** لا مصغّرات في الخادم ⇒ الأصل يُنزَّل دائماً؛ البطاقات `cacheWidth: 600`، المصغّرات 120، رأس المعرض محسوب؛ **الـ avatar بلا `cacheWidth`** (فك الأصل لدائرة صغيرة)؛ لا مشاركة لتنزيل متزامن للمفتاح نفسه خارج ما تفعله الحزمة داخلياً (`WebHelper` يجمع الطلبات المتزامنة لنفس المفتاح). **المكاسب المتوقعة (تقدير):** صفر تنزيل لتوقيع جديد لمعرّف محفوظ؛ لا محاولة شبكة كل عرض بعد 7 أيام؛ حصة غير مشتركة مع وسائط عامة؛ فك أصغر للـ avatar. **القياس (M1e، اختباري حتمي):** عدّاد استدعاءات `FileService.get` وإصابات `getFileFromCache` لسيناريو «3 توقيعات للمعرّف نفسه» (قبل: 3 تنزيلات في المسارات الرابط-مفتاحاً / بعد: 1) و«بعد 8 أيام» (قبل: محاولة لكل عرض / بعد: 0)؛ Samsung: زمن أول صورة (DEFERRED). **لا تغيير لحد 200/30 الآن** — يُقاس عدد الصور المميزة المعروضة لكل جلسة قبل اقتراح حد.

**7) الأمان ودورة الحياة:** تبديل الحساب/الخروج ⇒ البايتات تبقى، لا يُطلب مفتاح حساب آخر (والطبقة ترفض)؛ الحساب نفسه بعد العودة ⇒ يُرسم محلياً؛ جلسة مُزاحة ⇒ لا توقيع جديد (Worker يرفض)، المحفوظ يبقى معروضاً كبقية الكاشات (ليس سلطة)؛ **تنزيل متأخر بعد تغيّر الحساب/الجلسة ⇒ الـ FileService يرفضه قبل التخزين** (الربط بالجلسة عند البدء)؛ Delete Account ⇒ كنس بادئة `offer-media:<uid>:`/`profile-media:<uid>:` في الكاش الجديد + القائم اليوم؛ ملف مفقود/تالف ⇒ غائب؛ تصادم المعرّف مستحيل (UUID + المالك في المفتاح)؛ انتهاء الرابط لا أثر على المحفوظ؛ استبدال الوسائط = معرّف جديد ⇒ القديم يُخلى أو يُكنس بالكتالوج القائم؛ الإقلاع البارد offline ما زال يتوقف عند بوابة الجلسة (P1) — لا يتغير.

**8) خطة التنفيذ:**
- **M1b — الكاش الخاص والهوية:** جديد `private_media_cache.dart` (`CacheManager(Config('bwPrivateMedia', fileService: _ResolvingFileService))`، رابط زائف، ربط الحساب/الجلسة، `validTill` بعيد)؛ مفتاح `profile-media:<uid>:<id>`؛ `OfflineMediaService` يستعمله لـ `ensureMediaIdCached`/`warm`؛ استثناء `bwPrivateMedia.db*` من النسخ (XML + iOS). **اختبارات:** لا رابط موقّع في `repo` بعد تنزيل؛ رفض مفتاح حساب آخر؛ تنزيل متأخر بعد تبديل ⇒ لا تخزين؛ 3 توقيعات ⇒ تنزيل واحد؛ +8 أيام ⇒ لا شبكة؛ offline ⇒ المحفوظ. **طفرات:** إعادة الرابط الحقيقي للكاش، إزالة فحص المالك/الجلسة، `validTill` قصير. **قرار:** D-M1a-1/2/4.
- **M1c — استبدال المسارات:** `favorites_card`/`search_result_card` (البديل) و`CachedNetworkImage` الخاصة ⇒ الكاش الخاص بالمفتاح؛ إزالة الشيفرة الميتة (D-M1a-6)؛ `cacheWidth` للـ avatar. **ملفات:** `offline_media_service.dart`، `private_card_media.dart`، `current_user_avatar.dart`، `favorites_card.dart`، `search_result_card.dart`، `media_gallery_widget.dart`، `full_screen_media_viewer.dart`.
- **M1d — الترحيل:** نسخ مُثبت الملكية من `DefaultCacheManager` + إعادة توجيه الخريطة؛ اختياري كنس القديم (D-M1a-3). **اختبارات:** حسابان، مفاتيح غير مُثبتة لا تُلمس، انقطاع ⇒ القديم سليم وidempotent.
- **M1e — قياس وانحدار:** العدادات أعلاه + انحدار الوسائط/المفضلة/البحث.
- **التراجع:** الكاش الجديد إضافي؛ التراجع = العودة للكاش الافتراضي (بايتاته باقية ما لم يُكنس)؛ بعد كنس D-M1a-3 التراجع يعني إعادة تنزيل.

**9) قرارات المالك:**
- **D-M1a-1:** التخزين **B′** (كاش خاص + FileService يحل الرابط داخلياً، رابط زائف بلا توقيع في الفهرس) — **موصى**.
- **D-M1a-2:** `validTill` بعيد (مثلاً سنة) للمعرّفات الثابتة؛ الإخلاء يبقى 200/30 بـ `touched` حتى القياس — **موصى**.
- **D-M1a-3:** بعد نسخ مُتحقَّق: **كنس** مدخلات الوسائط الخاصة من `DefaultCacheManager` (يزيل الروابط الموقّعة والتكرار من الفهرس القديم) أو **إبقاؤها** (الافتراضي بلا موافقة).
- **D-M1a-4:** مفتاح Profile الجديد `profile-media:<uid>:<id>` — **موصى**.
- **D-M1a-5:** استثناء `bwPrivateMedia.db` + `-journal/-wal/-shm` من النسخ (Android + iOS) — **مطلوب مع B′**.
- **D-M1a-6:** حذف الشيفرة الميتة للمسارات الرابط-مفتاحاً (`views/Widgets/favorite_card.dart`، `UniversalMediaViewer`، `getImageProvider`، `mapUrlToLocalFile`) — ليست واجهة مستخدمة، لكن الحذف للمالك.
- **D-M2…D-M7 (§7AZ)** تبقى معلّقة؛ D-M2 (إزالة الروابط من الفهرس) **يتحقق بـ B′ + D-M1a-3**.

**المحفوظ:** P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 + قبول M0.5 على الأجهزة **DEFERRED**؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ إخفاقات Auth/Delete Account التاريخية وFU-COMBINE-GUARD-1؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit. **تحقق الأجهزة المؤجل لـ M1:** بقاء الكاش بعد مسح النظام لـ temp، زمن أول صورة، فك الـ avatar، النسخ الاحتياطي لـ `bwPrivateMedia.db`.

**الحالة:** **M1a = DESIGN مكتمل.** **NOW:** قرارات المالك D-M1a-1…6. **NEXT:** **M1b** بعد الموافقة. **STOP:** لا تنفيذ؛ لا commit/push؛ لا تغيير Auth/SAD/SQL/RLS/Cloudflare/PDF/تنسيق القوائم/سياسة الفيديو.

### M1b — أساس الكاش الخاص للصور — 2026-11-08 (CODE_PROVEN؛ غير مدمج)

**قرارات المالك (2026-11-08):** **D-M1a-1 APPROVED** (كاش خاص + FileService مخصص؛ لا رابط موقّع في البيانات الوصفية أبداً). **D-M1a-2 CONDITIONALLY APPROVED** (الهوية الثابتة لا انتهاء الرابط تقرر إعادة التنزيل؛ 200 مدخل / 30 يوماً بلا استعمال؛ الحداثة منفصلة عن الإخلاء؛ **شرط:** التحقق من ثبات المعرّف وإمكان الاستبدال/السحب في الخادم قبل سياسة «بلا تحديث»). **D-M1a-3 DEFER DELETION** (لا حذف/مسح/استبدال لمدخلات `DefaultCacheManager` في M1b). **D-M1a-4 APPROVED** (`profile-media:<uid>:<mediaId>`؛ Offer/Owner كما هي). **D-M1a-5 APPROVED** (استثناء فهرس الكاش الجديد وملفاته من النسخ/النقل في Android + آلية iOS القائمة، بأسماء ومواقع مُتحقَّقة). **D-M1a-6 DEFER** (لا حذف للشيفرة الميتة).

**Git (مُتحقَّق قبل البدء):** `e8162a9` = `origin` (0/0)؛ الـ stashes الاثنان باقيان؛ ملفات plugin الثلاثة معدّلة (مُعاد توليدها، لم تُلمس)؛ `docs/ADD_DETAILS_*` لم يُنشآ.

**1) بوابة D-M1a-2 — ثبات المعرّف والسحب (S — من المصدر؛ مُثبت ببنود اختبار):**
- **كل رفع = معرّف جديد:** `crypto.randomUUID()` في `handleAuthorize` (Profile) و`requestedId ?? crypto.randomUUID()` (Offer/Owner/Quotation/Plan)؛ `media_objects.id` مفتاح أساسي، `unique (bucket, object_key)`، والمفتاح يحمل المعرّف.
- **لا توقيع رفع لعنصر جاهز:** `resumeMediaUpload` يوقّع PUT **فقط** في `pending_upload`؛ `ready` يعود بلا توقيع، `failed` نهائي، `pending_delete`/`deleted` ⇒ 410. `confirm_*_media_upload` يشترط `pending_upload` ويفحص التوقيع (magic bytes) قبل `ready`. ⇒ **البايتات لكل معرّف ثابتة.** **متبقٍّ ضيق (S):** رابط PUT صدر قبل التأكيد صالح ≤ 300 ث (`SIGNED_PUT_TTL_SECONDS`)؛ حامله **هو المالك نفسه** فقط — لا يغيّر شيئاً لحساب آخر.
- **الاستبدال:** صورة جديدة = معرّف جديد = مدخل جديد؛ القديم يبقى حتى الإخلاء (30 يوماً/200) أو `forget`.
- **السحب:** الرؤية للمالك وحده (`media_objects_select_own`، و`assertOwnsParent` في كل مسار Worker) ⇒ لا مشاركة بين حسابات تُسحب. الإزالة فعل المالك (`pending_delete` ⇒ `deleted` + حذف R2). الإشارة الموثوقة الوحيدة لفقد الوصول تبقى `OfferMediaFailureKind.accessDenied` القائمة ⇒ المستدعي يستدعي `forget(key)` (التوصيل في M1c).
- **الخلاصة:** الشرط **مُثبت**؛ لا STOP. «بلا تحديث» = لا إعادة تنزيل لنسخة محفوظة سليمة؛ **ليست** دائمة: الإخلاء والإزالة الصريحة وDelete Account تنهيها.

**2) النطاق المنفَّذ بالضبط:**
- **جديد** `lib/src/services/private_media_cache.dart`: `PrivateMediaCache` (`storeKey = 'bwPrivateMedia'`، `CacheManager(Config(storeKey, stalePeriod: 30d, maxNrOfCacheObjects: 200, fileService: خاص))`)، `PrivateMediaScope(account, session)`، `profileMediaKey`، `accountOf`، `pseudoUrlFor`، `cached`، `get`، `forget`، `forgetAccount`، `dispose`، `applicationScope()`.
- `offer_media_session.dart`: getter للقراءة فقط `applicationAccount` (نفس `_owner`؛ لا تغيير سلوك).
- `deleted_account_local_data_cleaner.dart`: خطوة `forgetPrivateMedia` (افتراضياً `PrivateMediaCache.instance.forgetAccount`) بعد Offer media.
- النسخ الاحتياطي: `bwPrivateMedia.db` + `-journal/-wal/-shm` (domain `file`) في `full-backup-content` و`cloud-backup` و`device-transfer`؛ و`PrivateMediaBackupExclusions.cacheIndexFiles` (iOS) يضيفها.
- **لم يُغيَّر:** أي شاشة أو widget أو `OfflineMediaService` أو `CachedNetworkImage` أو القوائم أو التنقل أو الفيديو أو الحدود؛ لا مسار عرض يستعمل الكاش الجديد بعد (M1c). لا حذف لـ `DefaultCacheManager` ولا لشيفرة ميتة. لا تبعية جديدة (flutter_cache_manager/path_provider مباشرتان أصلاً).

**3) الهوية وصيغة البيانات الوصفية:**
- المفاتيح: `offer-media:<owner>:<mediaId>` (Offer وOwner، كما هي)، `offer-media:<owner>:<mediaId>:poster`، **`profile-media:<uid>:<mediaId>`**. `accountOf` يقرأ الحساب من البادئة؛ مفتاح بلا حساب ⇒ مرفوض.
- العنوان المخزَّن: **`bw-private-media://v1/<encodeComponent(key)>`** — ثابت، من المفتاح وحده.
- صف الفهرس (حقول `CacheObject`): `url` = العنوان الزائف، `key`، `relativePath` = `<uuid>.<jpg|png|webp|heic|''>`، `eTag` = **null دائماً**، `validTill` = الآن + 365 يوماً (`freshFor`؛ لا يُقرَّر به شيء)، `touched`، `length`.
- المواقع (S — مصدر الحزمة/path_provider): الفهرس `getApplicationSupportDirectory()/bwPrivateMedia.db` على Android (`files/`) وiOS (Application Support) عبر `CacheObjectProvider`؛ على مضيف سطح المكتب `bwPrivateMedia.json` (`JsonCacheInfoRepository`) بالحقول نفسها. البايتات `getTemporaryDirectory()/bwPrivateMedia/` = Android `cacheDir`، iOS `Library/Caches` (`NSCachesDirectory`) — **خارج النسخ أصلاً**.

**4) كيف يعمل:** `cached(key)` ⇒ نطاق حالي + حساب المفتاح = حساب النطاق ⇒ `getFileFromCache` ⇒ فحص سلامة (الملف موجود، طوله > 0 ويساوي `length` المسجل؛ وإلا يُزال ويُعامل كغائب) ⇒ إعادة فحص النطاق. `get(key, signedUrl:)` ⇒ المحفوظ أولاً (بلا طلب رابط)؛ وإلا رحلة واحدة لكل (جلسة، مفتاح)؛ تُسجَّل «تذكرة» (النطاق + دالة التوقيع) للعنوان الزائف ⇒ `downloadFile(pseudo, key, force: true)` ⇒ الـ FileService الخاص: بلا تذكرة ⇒ رفض بلا شبكة؛ فحص النطاق ⇒ طلب الرابط من المستدعي (المسار القائم: Worker يتحقق من التوكن و`is_current_app_session`) ⇒ فحص النطاق ⇒ GET بلا ترويسات، 200 فقط، ≤ 10 MiB، غير فارغ، مهلة 30 ث ⇒ فحص النطاق **قبل** أن تكتب الحزمة شيئاً. الرابط في الذاكرة لطلب واحد فقط. `force: true` يمنع الانضمام إلى تنزيل الحزمة الجاري لجلسة سابقة (طفرة M6 أثبتته).

**5) دليل أن الروابط الموقّعة لا تُحفظ (CODE_PROVEN):** اختبار يشغّل الإعداد الإنتاجي ويقرأ الفهرس الفعلي وكل ملف/اسم تحت مجلدَي support وtemp: لا `X-Amz` ولا مضيف R2 ولا `Signature` — بعد تنزيل، تنزيل ثانٍ، رفض 403، استثناء يحمل الرابط في رسالته (`HttpExceptionWithStatus` و`Exception`)، إعادة محاولة ناجحة، وإعادة تشغيل؛ و`FlutterError` و`debugPrint` بلا تقارير. الرابط استُعمل فعلاً في الذاكرة (مُثبت). إعادة التوجيه تحدث داخل عميل HTTP ولا تصل للفهرس (العنوان المخزَّن يُبنى من المفتاح، لا من الاستجابة). `PrivateMediaUnavailable` لا يحمل رابطاً ولا يخرج من الملف (المستدعي يرى null).

**6) عزل الحساب والجلسة:** حساب آخر لا يقرأ نسخة حساب (ولا يُطلب له رابط)؛ معرّف الوسائط نفسه تحت حساب آخر = مدخل منفصل؛ بعد الخروج لا عرض ولا جلب (البايتات وحدها ليست إذناً) والنسخة تبقى؛ الحساب نفسه بجلسة جديدة ⇒ عرض محلي بلا شبكة؛ استبدال الجلسة / تبديل الحساب / الخروج **أثناء** التنزيل ⇒ البايتات المتأخرة تُرمى ولا يُكتب شيء؛ تغيّر الجلسة أثناء التوقيع ⇒ R2 لا يُسأل؛ طالب جلسة مُستبدلة لا يشارك تنزيل الجلسة الجديدة. `applicationScope()` = حساب `OfferMediaSession` المصادَق تطبيقياً (لا recovery/quarantine) + جلسة يقبلها `AppSessionCoordinator.isAuthorized` (SAD) + `session.user.id` مطابق. Delete Account: `forgetAccount(uid)` يزيل مفاتيح `offer-media:<uid>:`/`profile-media:<uid>:` فقط (الفاصل `:` يمنع بادئة حساب آخر) ولا يحتاج جلسة؛ الخروج لا يحذف (كما اليوم).

**7) القياس (حتمي، عدّادات اختبار؛ زمن الجهاز NOT MEASURED):** 3 روابط موقّعة مختلفة للعنصر نفسه ⇒ **طلب شبكة 1، توقيع 1** (المسار الرابط-مفتاحاً اليوم: 3)؛ 3 طلبات متزامنة ⇒ **1/1** وملف واحد؛ إصابة محلية (حتى برابط منتهٍ وR2 يرفض) ⇒ **0 شبكة، 0 توقيع**؛ بعد إعادة التشغيل ⇒ **0 شبكة**؛ بعد +8 أيام: لا شيء يقرر بـ `validTill` (365 يوماً) ⇒ 0 (مقابل محاولة لكل عرض اليوم). لا تحويل لمسارات العرض بعد ⇒ لا تغيير زمن مرئي في M1b.

**8) الاختبارات:** جديد `test/services/private_media_cache_test.dart` (**34**) + `private_media_backup_test.dart` (**10**، مُحدَّث عمداً: `_m1b` 4 استثناءات، قائمة iOS، ووسم `bwPrivateMedia.db`) — **44/44 ✅ (أربع إعادات للملف: ثابت)**. يغطي: الهوية، الإعدادات (200/30، `storeKey` ≠ `DefaultCacheManager.key`)، 3 روابط ⇒ تنزيل واحد، التزامن، المحلي بلا شبكة مع رابط منتهٍ، الاستبدال = معرّف جديد، الفهرس بلا روابط (+ فشل/إعادة/إعادة تشغيل)، عزل الحساب، الخروج والعودة، تبديل الحساب أثناء قراءة نسخة محفوظة وأثناء كتابة البايتات، 3 سيناريوهات تغيّر أثناء التنزيل، تغيّر أثناء التوقيع، offline، بلا رابط/موقّع فاشل، فارغ/كبير، مبتور، ملف مختفٍ، الإخلاء، طلب غير مُصرَّح، إعادة التشغيل، `forgetAccount` بدقة، عدم لمس `libCachedImageData` (فهرساً وملفات ومصدراً)، توصيل Delete Account، وعقد Worker (معرّف جديد لكل رفع، لا توقيع لـ `ready`).

**9) الطفرات:** **19 طفرة، 18 مقتولة.** M1 رابط موقّع في العنوان المخزَّن، M2 بلا فحص حساب المفتاح، M3 بلا إعادة فحص بعد التوقيع، M4 بلا فحص قبل التخزين، M5 بلا مشاركة الرحلة، M6 الانضمام لتنزيل الحزمة الجاري (`force: false`)، M7 بلا فحص الطول، M8 بادئة حساب بلا فاصل، M9 `cached()` بلا إعادة فحص، M10 إبقاء ETag، M11 قبول طلب غير مُصرَّح، M12 بلا حدود حجم، M13 قبول استجابة فارغة، M14 بلا المحلي أولاً، M16 إعادة الملف بعد تغيّر النطاق، M17 غياب خطوة Delete Account، M18 قائمة iOS بلا الفهرس الخاص، M19 قاعدة device-transfer ناقصة ملفاً — **كلها قُتلت** (M9 وM16 نجتا أولاً ⇒ أُضيف اختباران بتبديل الحساب أثناء انتظار نظام الملفات فقُتلتا). **M15** (حذف فحص النطاق قبل بدء الرحلة) **نجت — مكافئة**: فحص الـ FileService عند الدخول يرفض قبل أي توقيع أو شبكة بالنتيجة نفسها؛ أُبقي كدفاع إضافي. كل ملف أُعيد وتطابق SHA-256.

**10) التحقق:** انحدار مركّز للملفات التي تستعمل منظّف Delete Account و`OfferMediaSession` واستثناءات النسخ (17 ملفاً: quarantine، المفضلة المشفّرة، قوائم local-first السبع، offline_lists الثلاثة، offer_media_session، Quotations الثلاثة، والملفان الجديدان) **362/362 ✅**. `delete_account_test` + `delete_account_ui_test`: **الإخفاقان المعروفان فقط** (setUpAll اسم ملف الترحيل؛ FU-ACCOUNT-UI-BASELINE-1). `flutter analyze` على الملفات الستة: **No issues found**. `dart format --set-exit-if-changed` على الستة: 0 تغيير (الجديدان مُنسَّقان؛ سطري في `private_media_backup_exclusions.dart` عُدّل يدوياً). `git diff --check` نظيف. لا بناء أصلي ولا Samsung.

**11) المخاطر الباقية:** لا مسار عرض يستعمل الكاش بعد (M1c)؛ الفهرس القديم `libCachedImageData.db` ما زال يحمل روابط موقّعة سابقة (D-M1a-3 مؤجل، مستثنى من النسخ منذ M0.5)؛ البايتات غير مشفّرة (كما اليوم؛ D-M5)؛ النسخ القديمة والمنقولة باقية (D-57)؛ PUT ≤ 300 ث للمالك نفسه (§1)؛ `applicationScope()` لا يُختبر هنا بلا عميل Supabase (منطق صغير؛ يُغطى بانحدار M1c)؛ سلوك الأجهزة (مسح النظام لـ temp، النسخ الفعلي لـ `bwPrivateMedia.db`) **REAL_DEVICE_UNVERIFIED**.

**12) نقاط تفتيش منفصلة (لم تبدأ):**
- **M1c — توصيل مسارات العرض:** `OfflineMediaService`/`PrivateCardMedia`/المعرض/العارض/الـ avatar (`cacheWidth`) ⇒ `PrivateMediaCache` بالمفتاح؛ `accessDenied` ⇒ `forget`؛ بديل `imageUrl` في `favorites_card`/`search_result_card` (FU-FAV-MEDIA-NO-IDENTITY)؛ مفتاح Profile الجديد في `CurrentUserAvatar`.
- **M1d — الترحيل:** نسخ مُثبت الملكية من `DefaultCacheManager` عبر `putFile(pseudo, bytes, key)` + إعادة توجيه `url_mapping`؛ القديم يبقى ما لم يقرر المالك D-M1a-3.

**المحفوظ:** P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 **DEFERRED**؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ إخفاقات Auth/Delete Account التاريخية (delete_account_test setUpAll، FU-ACCOUNT-UI-BASELINE-1) وFU-COMBINE-GUARD-1؛ قيود PDF عروض الأسعار التاريخية؛ Smart Map/Toolkit معلّقان.

**الحالة:** **M1b = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** مراجعة المالك النهائية. **STOP:** لا commit/push؛ لا بدء M1c/M1d.

**تحديث (2026-11-08):** M1b أُودع `2ee9585` والمالك دفعه (= `origin`).

### M1c — ربط صور تفاصيل Offers وOwners بالكاش الخاص — 2026-11-08 (CODE_PROVEN؛ غير مدمج)

**Git (مُتحقَّق قبل البدء):** `2ee9585` = `origin` (0/0)؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ ملفات plugin الثلاثة فقط معدّلة (لم تُلمس)؛ `docs/ADD_DETAILS_*` لم يُنشآ.

**1) تدقيق المسار الحي (S — كود الإنتاج):**
- **الودجات الفعلية:** `OptimizedMediaGalleryWidget` بـ `mediaRefs` في `offers_view_details.dart:637` و`owners_view_details.dart:445` (Owner بوضع Supabase عبر `PrivateMediaGalleryLoader`) ⇒ `_buildMediaItem` ⇒ `_buildOptimizedImageViewer` ⇒ (قبل) `OfflineMediaService.buildOfflineAwareImage`؛ والعارض الكامل `FullScreenMediaViewer` (يُفتح من المعرض نفسه) ⇒ `_imageProviderFor` (الصورة + شريط المصغّرات). **ليست جزءاً:** `owners_view_details._buildCachedMediaGallery` (`mediaUrls` فقط — مسار Firebase القديم، بلا هوية)، عارض صور خطط الملحقات (`plan_attachment_actions`، `cacheKey: null`)، بطاقات المفضلة/البحث (`PrivateCardMedia`)، الـ avatar، شبكة الإضافة/التعديل، الخريطة، الفيديو والملصقات.
- **الهوية:** `OfferMediaRef.cacheKey = offer-media:<owner>:<mediaId>` — من الحل (`_refFor` بحساب الجلسة) أو من كتالوج الحساب (`_cachedRecordMedia` بـ `currentOwnerId`) أو من نموذج بمعرّفات **متطابقة الطول فقط** (`_refsFromOffer`). Offer وOwner يتشاركان الصيغة.
- **الرابط:** كل فتح يطلب `/offer-media` أو `/owner-media` (القائمة المرجعية + روابط جديدة لكل العناصر)؛ يُحفظ في الذاكرة فقط (`OfferMediaUrlCache`، حتى 60 ث قبل الانتهاء)؛ `refreshSignedUrl` يعيد الحل (للفيديو).
- **المحلي قبل التوقيع:** البذرة المتزامنة تقرأ `url_mapping` + ذاكرة الروابط؛ **طلب الحل نفسه يجري في كل فتح بغض النظر** (هو مرجع المجموعة والسحب) — لم يتغير.
- **قبل M1c عند إعادة الفتح:** ملف مُخطَّط ⇒ بلا تنزيل؛ وإلا `CachedNetworkImage(signedUrl, cacheKey)` على `DefaultCacheManager` ⇒ إصابة بالمفتاح، لكن **كل تنزيل يكتب الرابط الموقّع في `libCachedImageData.db`**، وبعد 7 أيام (`validTill`) يعيد `getFileStream` التنزيل في كل عرض. الإحماء (`_warmStableIdentity` ⇒ `ensureMediaIdCached` ⇒ `getSingleFile(url)`) ينزّل في الكاش القديم ثم يكتب الخريطة — **وهذا ما يجعل الفتح offline يعمل اليوم**.
- **التكرار:** المعرض + الإحماء + العارض يتشاركون مفتاحاً واحداً ⇒ الحزمة تدمجها (`WebHelper` لكل مفتاح).
- **تبديل الحساب:** الحل يُرفض إن تغيّر الحساب؛ `OfferMediaSession` يمسح ذاكرة الروابط؛ **قراءة الخريطة لم تكن مقيّدة بالجلسة**.
- **إغلاق الشاشة أثناء التنزيل:** المنسّق يرفض بالجيل؛ تنزيل الحزمة يكمل.

**2) ما نُفِّذ (المسارات الموثوقة فقط):**
- **جديد** `lib/src/services/private_media_images.dart`: `PrivateMediaImages.heldNow(key)` (متزامن، للإطار الأول: ملف `url_mapping` **فقط** إن كان المفتاح لحساب الجلسة الحالية) و`load(key, signedUrl:)` بالترتيب: (1) ملف الخريطة؛ (2) نسخة الكاش الخاص؛ (3) **الكاش القديم قراءةً فقط بلا شبكة** (`OfflineMediaService.heldInSharedCache` ⇒ `getFileFromCache`)؛ (4) تنزيل واحد عبر `PrivateMediaCache.get` بالرابط الموجود فعلاً (صالح في `OfferMediaUrlCache` أولاً، ثم رابط الشاشة). ما وُجد يُسجَّل في `url_mapping` (**مسار ملف، لا رابط**) ⇒ الفتح التالي (بارد/offline) يرسم فوراً. فحص الجلسة/الحساب قبل كل خطوة وبعد كل انتظار. **لا طلب توقيع من مسار الصورة إطلاقاً**؛ بلا رابط ⇒ ينتظر حل الشاشة. لا يرمي ولا يحذف. و`PrivateMediaImageProvider` للعارض الكامل (هوية = المفتاح + الرابط، في الذاكرة).
- **جديد** `lib/src/views/Widgets/private_media_image.dart`: ملف مُخطَّط ⇒ `Image.file` في الإطار الأول (نفس `cacheWidth`/`fit`/`gaplessPlayback`/frameBuilder)؛ وإلا placeholder القائم أثناء البحث؛ رابط في اليد وفشل ⇒ errorWidget القائم (مع Retry)؛ بلا رابط وبلا نسخة ⇒ placeholder؛ رابط جديد ⇒ محاولة جديدة؛ الإغلاق ⇒ الجواب المتأخر يُهمل والتنزيل يكمل ويُحفظ.
- `media_gallery_widget.dart`: لعناصر `mediaRefs` ذات `cacheKey` ⇒ `PrivateMediaImage` (نفس placeholder/errorWidget بلا تغيير نص)؛ الإحماء لعناصر `mediaRefs` ⇒ `PrivateMediaImages.load` (نفس العناصر: الحالي +2؛ لا جلب مسبق جديد). عناصر بلا هوية ومسار `mediaUrls`/`mediaIds` ⇒ كما كانت.
- `full_screen_media_viewer.dart`: `_imageProviderFor` لعناصر `cacheKey` ⇒ `heldNow` ⇒ `FileImage`، وإلا `PrivateMediaImageProvider` (بدل `CachedNetworkImageProvider`)؛ بلا مفتاح ⇒ `NetworkImage` كما كان.
- `offline_media_service.dart`: `_removeArtifactsFor` يزيل أيضاً نسخة الكاش الخاص (`removePrivateBytes` ⇒ `PrivateMediaCache.instance.forget`) ⇒ العنصر المُسقط من رد مرجعي، أو المسحوب (`accessDenied`)، أو مفاتيح كتالوج Delete Account تُزال من الكاش الخاص أيضاً؛ و`heldInSharedCache` (قراءة فقط).
- `private_media_cache.dart`: `canRead(key)` (فحص متزامن بلا تخزين).

**3) أعداد الطلبات (حتمية من الاختبارات؛ «قبل» من مصدر الحزمة):**
| السيناريو | قبل | بعد |
|---|---|---|
| إعادة فتح وصورة محفوظة (Offer أو Owner) | 0 تنزيل (عبر الخريطة، **بلا فحص جلسة**) | **0 تنزيل، 0 رابط مستعمل** (بفحص الجلسة) |
| 3 روابط موقّعة للمعرّف نفسه | 1 تنزيل + **الرابط يُكتب في الفهرس القديم** | **1 تنزيل، لا رابط محفوظ** |
| بعد 7 أيام | إعادة تنزيل لكل عرض | **0** |
| ودجتان معاً | 1 (دمج الحزمة) | **1** (دمج M1b) |
| صورة في الكاش القديم فقط | 0 (CachedNetworkImage بالمفتاح) | **0** (قراءة فقط، بلا ترحيل) |
| إعادة التشغيل / offline بنفس الجلسة | من الخريطة | **0 طلب** (الخريطة، أو الكاش الخاص إن ضاعت) |
| طلبات الحل من Worker لكل فتح | 1 | **1 (بلا تغيير)** |
زمن أول صورة على الجهاز: **NOT MEASURED** (VM الاختبار لا يمثل Samsung/iOS).

**4) العزل والأمان:** حساب آخر لا يقرأ نسخة/خريطة حساب ولا يجلبها (حتى بنفس معرّف الوسائط)؛ الخروج ⇒ لا عرض ولا جلب، والعودة بنفس الحساب ⇒ عرض محلي بلا شبكة؛ تبديل الحساب / إزاحة الجلسة / استبدالها أثناء التنزيل ⇒ يُرمى ولا يُخطَّط؛ تبديل الحساب أثناء قراءة الكاش القديم ⇒ لا يُسلَّم ولا يُخطَّط؛ مفتاح بلا حساب ⇒ لا يُستعمل؛ فشل شبكة/توقيع لا يحذف نسخة سليمة؛ مبتور ⇒ يُعاد جلبه بتصريح؛ غير قابل للفك ⇒ errorWidget؛ لا رابط موقّع في `bwPrivateMedia.json` ولا في `url_mapping` ولا في أي ملف (مُثبت بعد 3 روابط + فشل يحمل الرابط + إعادة تشغيل). Delete Account يبقى بالحساب (`forgetAccount`)؛ السحب/الإسقاط يصل للكاش الخاص.

**5) توافق الموجود:** `DefaultCacheManager` لا يُحذف ولا يُرحَّل ولا يُكتب إليه من هذه المسارات (يُقرأ فقط؛ `getFileFromCache` يحدّث `touched` كما يفعل الاستعمال اليوم)؛ `url_mapping`/`local_media` باقيان، والخريطة تُكتب كما كانت تُكتب (مسار ملف)؛ الأصول المتبناة على هذا الجهاز تبقى الأولى.

**6) الاختبارات:** جديد `test/offers/offer_media_private_cache_test.dart` (**40**): Offer وOwner محلي، 3 روابط، تزامن، رابط منتهٍ، تفضيل رابط الذاكرة، المستدعي يرحل والتنزيل يكمل، offline، إعادة التشغيل، بلا رابط، عزل الحساب، الخروج/العودة، 3 تغييرات أثناء التنزيل، مفتاح بلا هوية، الكاش القديم (+ تبديل أثناء قراءته)، الأصل المتبنى، مختفٍ/مُخلى/مبتور، فشل لا يحذف، السحب بالحساب، Delete Account، لا روابط في التخزين، المعرض (PrivateMediaImage، بلا هوية ⇒ القديم، الترتيب، placeholder، خطأ مع Retry، رسم من الملف، الإغلاق، غير قابل للفك، الإحماء لا يعطي الكاش القديم رابطاً، رابط يصل)، العارض الكامل (FileImage/PrivateMediaImageProvider، الهوية، الفك). **تحديثات مقصودة:** `offer_media_local_first_test.dart` (نطاق جلسة owner-1؛ اختباران كانا يتوقعان `CachedNetworkImage` صارا يتوقعان `PrivateMediaImage`؛ حساب آخر ⇒ لا Image) و`offer_media_loading_ui_test.dart` (نطاق الجلسة؛ العارض ⇒ `PrivateMediaImageProvider`) + `removePrivateBytes` بلا عمل في الملفين (كنمط `removeCachedBytes` القائم: لا مخزن منصة تحت `flutter test`). الملفات الثلاثة **64/64 ✅** (ثلاث إعادات ثابتة). انحدار: offers/owners/share/lists/Quotations الثلاثة/quarantine/المفضلة المشفّرة/r5c owners/plan guards/M1b **1654/1654 ✅**؛ وبعد التنسيق offers/owners/share/M1b/r5c **927/927 ✅**. **فخ اختبار:** عمل الكاش الخاص الحقيقي على القرص لا يكتمل داخل منطقة fake-async لـ `testWidgets` (وانتظار `dispose` يعلّق)؛ اختبارات الودجات بلا I/O تعمل بلا جلسة، وذات I/O داخل `runAsync`، والإغلاق عبر `PrivateMediaImages.debugLoad`.

**7) الطفرات: 14/14 مقتولة** — C1 قراءة الخريطة بلا فحص جلسة، C2 عدم تسجيل الخريطة، C3 بلا فحص بعد البحث (نجت أولاً ⇒ اختبار تبديل الحساب أثناء قراءة الكاش القديم فقُتلت)، C4 تفضيل رابط اليد على الصالح في الذاكرة، C5 عدم استشارة الكاش القديم، C6 إعطاء الكاش القديم رابطاً، C7 المعرض يبقى على الصورة الشبكية القديمة، C8 الإحماء ينزّل في الكاش القديم، C9 العارض بـ `NetworkImage`، C10 السحب يتخطى الكاش الخاص، C11 setState بعد الإغلاق، C12 الفشل لا يُظهر الخطأ، C13 الرابط الجديد لا يُستعمل، C14 هوية الـ provider بلا الرابط. استعادة كل ملف بتطابق SHA-256.

**8) التحقق:** `flutter analyze` على الملفات التسعة: ملاحظة info واحدة **سابقة** (`offer_media_loading_ui_test.dart:5` استيراد زائد — موجودة في نسخة HEAD، لم تُلمس)؛ `dart format --set-exit-if-changed`: 0 تغيير (الجديدة مُنسَّقة؛ في الملفات القائمة أسطري فقط)؛ `git diff --check` نظيف. لا بناء أصلي ولا Samsung.

**9) الباقي غير مدعوم/المخاطر:** طلب الحل لكل فتح باقٍ (مرجع المجموعة والسحب)؛ الخريطة تشير الآن أيضاً لملفات الكاش الخاص ⇒ بطاقات المفضلة/البحث (`buildOfflineAwareImage`، غير مقيّدة بالجلسة كما اليوم) قد ترسم تلك الملفات — نفس التعرض الذي تعطيه الخريطة اليوم لملفات الكاش القديم، والمفضلة/البحث ما زالت تنزّل في الكاش القديم (FU-FAV-MEDIA-NO-IDENTITY)؛ ملف مُخطَّط تالف قابل للقراءة لا يُصلَح تلقائياً (errorWidget؛ كما كان)؛ Owners بوضع Firebase وصور خطط الملحقات بلا هوية ⇒ بلا تغيير؛ الفيديو والملصقات والـ avatar والمفضلة/البحث خارج النطاق؛ البايتات غير مشفّرة؛ الفهرس القديم ما زال يحمل روابط سابقة (D-M1a-3)؛ الأجهزة **REAL_DEVICE_UNVERIFIED**.

**10) نقاط تفتيش لاحقة (لم تبدأ):** **M1d** — ترحيل آمن مُثبت الملكية من الكاش القديم (+ قرار كنسه D-M1a-3)؛ **M1e** — قياسات الجهاز (زمن أول صورة، فتح offline بعد إعادة تشغيل، النسخ الاحتياطي لـ `bwPrivateMedia.db`) وانحدار المفضلة/البحث/الملف الشخصي عند ربطها.

**المحفوظ:** FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية (delete_account_test setUpAll، FU-ACCOUNT-UI-BASELINE-1) وFU-COMBINE-GUARD-1؛ قيود PDF عروض الأسعار القديمة؛ Smart Map/Toolkit معلّقان.

**الحالة:** **M1c = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** مراجعة المالك النهائية. **STOP:** لا commit/push؛ لا بدء M1d أو المفضلة/البحث أو الملف الشخصي أو الفيديو.

### M1c — المراجعة النهائية: عزل الخريطة المشتركة والفتح offline — 2026-11-08 (CODE_PROVEN؛ لا تغيير كود إنتاجي؛ غير مدمج)

**Git (مُتحقَّق):** `2ee9585` = `origin`؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ تنفيذ M1c غير المودع محفوظ؛ ملفات plugin الثلاثة لم تُلمس.

**A) `url_mapping` المشتركة ومستهلكوها — PASS (بلا عيب؛ لا تصحيح):**
- **القرّاء الحيّون لمفاتيح `offer-media:`:** (1) معرض التفاصيل والعارض الكامل ⇒ `PrivateMediaImages.heldNow` (**مقيّد بالجلسة والحساب**)؛ (2) بطاقات المفضلة والبحث ⇒ `PrivateCardMedia` ⇒ `buildOfflineAwareImage` (قراءة الخريطة **بلا فحص جلسة**، كما قبل M1c)؛ (3) نموذج الإضافة/التعديل (`private_media_form.dart`، `add_offers_viewmodel.dart`)؛ (4) المشاركة (`share_live.dart` ⇒ `ensureMediaIdCached(url: null)`)؛ (5) ملصقات الفيديو (`offer_video_poster_service`، مفتاح `:poster` — لا يكتبه M1c)؛ (6) بذرة التفاصيل (`_localPathFor`). **الملف الشخصي:** مفاتيح `profile_media_id` عارية — نطاق آخر لا يتقاطع.
- **(1) حساب آخر:** كل مفتاح يُبنى من سجل الحساب نفسه: المفضلات بـ RLS `owner_id = auth.uid() and owns_offer/owns_owner_record(target)` (لا مفضلة لسجل حساب آخر)، القوائم والبحث من كاشات مشفّرة لكل حساب، `FavoritesMemory` بمفتاح الـ uid؛ ومسار التفاصيل يرفض مفتاحاً لغير حساب الجلسة. ⇒ ملف خاص لحساب A لا يُعنوَن من واجهة B.
- **(2) جلسة خارجة/مُزاحة:** `supersede()` ⇒ الخروج والعودة لشاشة الدخول؛ الشاشات التي تقرأ الخريطة غير قابلة للوصول؛ ومسار M1c نفسه يرفض بلا نطاق (`applicationScope` = حساب مصادَق تطبيقياً + `isAuthorized`).
- **(3) بحث متأخر بعد التبديل:** M1c يرمي الناتج ولا يكتب الخريطة (اختبارات M1c)؛ القرّاء القدامى قراءة متزامنة.
- **(4) التوافق القديم لا يتخطى العزل:** قراءة الكاش القديم مقيّدة بالجلسة قبلها وبعدها (طفرة C3).
- **(5) Delete Account:** `forgetOfferMedia(ownerId)` يزيل خريطة مفاتيح كتالوج الحساب + نسخها الخاصة (`removePrivateBytes`) ثم `forgetAccount` يزيل باقي ملفاته الخاصة؛ خريطة/ملف/كتالوج الحساب الآخر سليمة (**اختبار جديد**). خريطة لمفتاح خارج الكتالوج (نادر: فشل كتابة الكتالوج) تبقى مساراً لملف محذوف ⇒ تفشل بأمان.
- **(6) مُخلى/مفقود:** `existsSync` false ⇒ غائب؛ offline ⇒ لا شيء ولا خطأ (**اختبار جديد**).
- **(7) لا رابط جديد محفوظ:** مسارات M1c لا تكتب روابط (اختبارات M1c). **تنبيه:** مدخلات `DefaultCacheManager` التاريخية (`libCachedImageData.db`) **ما زالت تحمل روابط موقّعة سابقة**، والمفضلة/البحث ما زالت تنزّل فيه — لا يُدّعى غياب الروابط من القرص.
- **المتبقي (ليس تجاوزاً، بلا تغيير عن قبل M1c):** قرّاء المفضلة/البحث/النموذج/المشاركة يعتمدون على بوابة التنقل ومصادر السجلات المقيّدة بالحساب، لا على فحص جلسة خاص بهم؛ الخريطة تشير الآن أيضاً لملفات الكاش الخاص ⇒ تلك البطاقات قد ترسمها (نفس التعرض لملفات الكاش القديم). ربطها بالكاش الخاص = نقطة تفتيش منفصلة (FU-FAV-MEDIA-NO-IDENTITY).

**B) الفتح offline والـ Worker غير متاح — PASS (مشروط):**
- **السلسلة المُثبتة (اختبار عبر `SupabaseCoreEntitiesService` حقيقي + عميل مُسجَّل + Worker غير قابل للوصول):** فتح سابق online كتب كتالوج الحساب (`local_media`) وخريطة الملف ⇒ offline: البذرة **المتزامنة** (`cachedOfferMedia`/`cachedOwnerMedia` ⇒ `_localPathFor` ⇒ `url_mapping`) تعطي العنصر بـ `localFilePath` **قبل أي رد شبكة** ⇒ `hasRenderableMedia` ⇒ رأس الشاشة يعرض المعرض (`_buildHeaderBackground` يفضّله على التحميل/الخطأ) ⇒ `heldNow` يرسم الملف. فشل القراءة (من القائمة/البحث/المفضلة: `initialMetadataResolved: false` ⇒ `metadataLoadFailed`) أو فشل الـ Worker (`OfferMediaException(transient)` ⇒ `mediaLoadFailed`) **لا يمسح ما على الشاشة ولا يحذف بايتات**؛ لا طلب صورة. Owner: نفس الكتالوج والفشل العابر.
- **التمييز:** بايتات محفوظة ✔ (الكاش الخاص/القديم/الأصل)؛ هوية الوسائط ✔ **فقط إن** كُتب كتالوج الحساب لذلك السجل (فُتحت التفاصيل online على هذا الجهاز أو رُفعت منه) — الكاشات المشفّرة للقوائم لا تحمل `mediaObjectIds` (M0)؛ كتالوج الوسائط من الـ Worker غير متاح ✔ (لا يحجب)؛ نص التفاصيل ✔ من السجل المحفوظ (لا يُخفى عند `metadataLoadFailed`)؛ الإقلاع البارد offline ✘ يتوقف عند بوابة الجلسة (P1) قبل أي شاشة.
- **الحدود (لم تُغيَّر):** (أ) بلا خريطة للعنصر لا ترى البذرة النسخة الخاصة (البذرة متزامنة والفهرس الخاص غير متزامن — **اختبار توصيفي**)؛ (ب) بلا كتالوج للسجل لا هوية offline؛ (ج) لا عرض من غير جلسة مُصرَّحة. **أصغر متابعة آمنة:** في M2 — تخزين المعرّفات (لا الروابط) مع السجلات المشفّرة **بموافقة منفصلة** (تغيير صيغة)، أو بذرة تنتظر `PrivateMediaCache.cached` لعناصر الكتالوج بلا خريطة؛ لا تجاوز للسحب ولا لـ SAD.

**الاختبارات:** `offer_media_private_cache_test.dart` **46** (+6: Delete Account يزيل خريطة/نسخة حساب واحد فقط؛ ملف مُخلى يفشل بأمان؛ offline Offer من القائمة ومن سجل محلول؛ offline Owner؛ توصيف «بلا خريطة») + الملفان المحدّثان ⇒ **70/70 ✅** (ثابت). **طفرات المراجعة 4/4 مقتولة:** R1 Delete Account يُبقي الخريطة، R2 البذرة تتجاهل الملفات المُخطَّطة، R3 فشل الـ Worker يمسح الشاشة، R4 فشل القراءة يمسح الشاشة (استعادة SHA-256). `flutter analyze` على ملف الاختبار: لا مشاكل؛ التنسيق 0 تغيير؛ `git diff --check` نظيف. لم يُعَد انحدار الـ 1654 (لا تغيير إنتاجي).

**مخاطر الترحيل القديم الباقية (M1d):** روابط موقّعة تاريخية في `libCachedImageData.db`؛ نسخ مكررة بين الكاشين؛ مفضلة/بحث تكتب في القديم؛ قرار الكنس D-M1a-3. **الأجهزة:** Samsung/iOS **REAL_DEVICE_UNVERIFIED** (مسح النظام لـ temp، النسخ الاحتياطي، زمن أول صورة، offline الفعلي).

**المحفوظ:** FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وفحوص الأجهزة **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية وFU-COMBINE-GUARD-1؛ قيود PDF عروض الأسعار القديمة؛ Smart Map/Toolkit معلّقان.

**الحالة:** **M1c (+ المراجعة) = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** موافقة المالك على الـ commit. **STOP:** لا commit/push؛ لا بدء M1d/M2/M3/الملف الشخصي/الفيديو.

**تحديث (2026-11-08):** M1c أُودع `7edee16` والمالك دفعه (= `origin`).

### M1d — تصميم ترحيل آمن من كاش الصور القديم وتقاعده — 2026-11-08 (AUDIT + DESIGN؛ SOURCE-READ؛ لا تغيير كود)

**Git (مُتحقَّق):** `7edee16` = `origin` (0/0)؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ ملفات plugin الثلاثة فقط معدّلة (لم تُلمس)؛ `docs/ADD_DETAILS_*` لم يُنشآ. **هذا القسم وحده تغيّر.**

**1) جرد مستهلكي `DefaultCacheManager` (`libCachedImageData`) — S:**
| المستهلك | الحالة | المفتاح المخزَّن | يحتاج المدخلات القديمة؟ |
|---|---|---|---|
| بطاقات المفضلة/البحث/الخريطة ⇒ `PrivateCardMedia` ⇒ `ensureMediaIdCached` (`getSingleFile(signedUrl, key)`) + `buildOfflineAwareImage` (الخريطة ثم `CachedNetworkImage(signedUrl, cacheKey)`) | **حي** | `offer-media:<owner>:<id>` (أصل) + **الرابط الموقّع في عمود `url`** | **نعم** حين لا خريطة للعنصر |
| بديل `imageUrl` في `favorites_card:1015`/`search_result_card:1059` (`CachedNetworkImageProvider(imageUrl, cacheKey: imageUrl)`) + جلب المفضلة المسبق `favorites_view:368/419` ⇒ `ImageCacheManager.prefetchImages` (`cacheKey: url`, 400×300) | **حي** | **الرابط نفسه مفتاحاً** (+ نسخ `resized_w400_h300_<url>`) — **بلا هوية** (FU-FAV-MEDIA-NO-IDENTITY) | نعم (لا بديل لها) |
| `map_view:1159` `CachedNetworkImage(locationInfo.mediaUrl)` | حي (احتياطي) | الرابط | نعم |
| شبكة الإضافة/التعديل `unified_media_preview_grid` (`:476` + `buildOfflineAwareImage`)، منتقي المشاركة `share_media_picker`، المشاركة `share_live` (`ensureMediaIdCached(url: null)` ⇒ خريطة أو قراءة قديمة) | حي | `offer-media:` أو الرابط | نعم (قراءة) |
| معرض بلا `mediaRefs` (`mediaUrls`/`mediaIds` ⇒ `ensureMediaIdCached`، `MediaCacheManager.getOptimizedImage` ⇒ `resized_w800_h600_<key>`) | Owners بوضع Firebase فقط | URL أو `offer-media:` + نسخ مصغّرة | لا (خارج Supabase) |
| الـ avatar `CurrentUserAvatar` ⇒ `warmMediaIdMapping(mediaId)` (`getFileFromCache(mediaId)`) + `buildOfflineAwareImage(cacheKey: mediaId)`؛ `forgetProfileMedia` (`removeFile(mediaId)`) | حي | **معرّف عارٍ بلا حساب** | نعم (M4) |
| M1c `PrivateMediaImages.load` الخطوة 3 (`heldInSharedCache` ⇒ `getFileFromCache(key)`) | حي (قراءة فقط) | `offer-media:` | نعم حتى الترحيل |
| `removeCachedBytes` (السحب/الإسقاط/Delete Account لمفاتيح الكتالوج) | حي | `offer-media:` | — (يحذف فقط) |
| `views/Widgets/favorite_card.dart` + `getImageProvider`، `UniversalMediaViewer`، `HeicAwareImage` (`utils/heic_image_handler.dart`)، `mapUrlToLocalFile` | **ميت** (بلا مستوردين/مستدعين) | — | لا (D-M1a-6 مؤجل) |
**حقيقة الحزمة (S):** `CachedNetworkImageProvider` بـ `maxWidth/maxHeight` يخزّن **الأصل تحت `key`** ونسخة مصغّرة تحت `resized_w…_h…_<key>` ⇒ المفتاح الدقيق = الأصل دائماً. `DefaultCacheManager` لا يكشف مستودعه ⇒ **لا تعداد آمن للمدخلات القديمة** (فتح `CacheObjectProvider('libCachedImageData')` ثانٍ = اتصال SQLite موازٍ — مرفوض) ⇒ الترحيل **بالمفتاح فقط، عند الطلب**.

**2) ما يمكن ترحيله بأمان (وحده):** مدخل بالمفتاح **الدقيق** `offer-media:<A>:<mediaId>` حيث: (1) `A` = حساب الجلسة الحالية المصادَق (`canRead`)؛ (2) المعرّف جاء من مرجع مرجعي للجلسة نفسها (عنصر معرض Offer/Owner من حل الـ Worker أو كتالوج الحساب `offerMediaCatalog::<A>::<record>`) — **دليل الملكية = المفتاح الذي بنته الجلسة + المرجع، لا الرابط ولا اسم الملف ولا المعرّف وحده**؛ (3) صورة (ليست فيديو/ملصقاً/PDF) — يُتحقق بـ **التوقيع السحري** للبايتات (JPEG `FFD8FF`، PNG `89504E47`، WEBP `RIFF…WEBP`، HEIC/HEIF `ftyp` بعلامات `heic/heix/mif1/msf1/hevc`؛ يُرفض `ftyp isom/mp42/qt`)، غير فارغ، ≤ 10 MiB؛ (4) الملف القديم موجود ومقروء؛ (5) لا نسخة خاصة سليمة أصلاً. **مفاتيح الحالات (S):** بطاقات المفضلة تبني `offer.userId` لسجلات الحساب (RLS `owns_offer`)، والمعرض يبني من `sessionOwnerId`.

**3) ما يبقى دون مساس:** مدخلات مفتاحها الرابط (بلا هوية؛ لا مالك مُثبت)؛ `resized_*`؛ مفاتيح profile العارية (M4)؛ `:poster` والفيديو (M5؛ لا تُخزَّن صور الفيديو في الكاش القديم كأصل)؛ مفاتيح حساب غير حساب الجلسة؛ أي مفتاح بلا مرجع من الجلسة؛ أصول `offer_media`/`profile_media` المتبناة (تبقى الأولى عبر الخريطة).

**4) التصميم الموصى (M1d-1/2):**
- **الآلية:** ترحيل **عند العرض فقط** داخل `PrivateMediaImages.load` حين تكون الإصابة في الكاش القديم (الخطوة 3): يُعرض الملف القديم فوراً (لا تأخير)، ثم يُرحَّل في الخلفية. **لا مسح جماعي**، لا شبكة.
- **الكتابة عبر مسار M1b نفسه:** `PrivateMediaCache.adopt(key, readLocal)` يسجّل «تذكرة» مصدرها بايتات محلية بدل الموقِّع+النقل، ثم `downloadFile(pseudo, key, force: true)` ⇒ نفس فحوص النطاق (قبل/بعد القراءة، قبل الكتابة)، نفس حد الحجم والفراغ، `length` يُسجَّل (فحص البتر)، `eTag` null، العنوان الزائف فقط، **نفس `_inFlight` لكل (جلسة، مفتاح)** ⇒ لا سباق مع تنزيل موازٍ ولا ترحيل مزدوج. **لا `putFile`:** لا يسجّل `length`، ويكتب فوق الملف القائم في مكانه.
- **التحقق بعد الكتابة:** `cached(key)` + الطول + SHA-256 للمصدر = للنسخة.
- **الخريطة (M1d-2):** «قارن-واستبدل»: تُوجَّه `url_mapping[key]` إلى الملف الخاص **فقط** إن كانت ما زالت تشير إلى الملف القديم نفسه أو مفقودة/ميتة؛ لا تُمس إن أشارت لأصل متبنى أو لملف آخر (`OfflineMediaService.replaceMediaIdMapping(key, expected, replacement)` جديدة؛ الفحص والكتابة في مقطع متزامن واحد). إعادة فحص الجلسة قبل النشر.
- **الفشل/الانقطاع/الإلغاء:** لا حذف لأي شيء؛ القديم سليم؛ المحاولة التالية idempotent (نسخة خاصة سليمة ⇒ تخطٍّ).
- **التقاعد:** لا شيء في M1d-1/2.

**5) أمان التقاعد (D-M1a-3، M1d-3):**
- **ممكن لكل عنصر:** `DefaultCacheManager().removeFile(key)` للمفتاح الدقيق `offer-media:<A>:<id>` الذي رُحِّل وتُحقِّق منه ووُجِّهت خريطته — يمس صفاً واحداً وملفه؛ المفاتيح مربوطة بالحساب ⇒ لا يمس حساباً آخر ولا أصولاً عامة؛ **لا `emptyCache` أبداً**. الترتيب: تحقق ⇒ إعادة توجيه الخريطة ⇒ ثم الحذف (فشل التوجيه ⇒ لا حذف ⇒ لا خريطة ميتة).
- **لماذا بعد M3:** بطاقات المفضلة/البحث/الخريطة تقرأ الخريطة بلا فحص جلسة، وعند غيابها (إخلاء النسخة الخاصة) **تعيد التنزيل إلى الكاش القديم** (`getSingleFile`/`CachedNetworkImage` ⇒ صف جديد برابط موقّع جديد) ⇒ التقاعد قبل M3 آمن لكنه **غير دائم**؛ ومدخلات المفضلة بمفتاح الرابط لا تُقاعَد بالعنصر إطلاقاً (لا هوية) ⇒ تبقى حتى الإخلاء الطبيعي (200/30) أو قرار منفصل على مستوى الحساب.
- **الروابط في الفهرس:** حذف صف SQLite **لا يمحو بياناته فوراً** (تبقى في صفحات حرة حتى إعادة الكتابة؛ لا `secure_delete`/`VACUUM`) ⇒ لا يُدّعى محو الروابط التاريخية بالتقاعد. المخفِّف القائم: الروابط **منتهية** (GET 900 ث) والفهرس مستثنى من النسخ (M0.5)؛ ما يبقى = بيانات وصفية (مسارات الكائنات تحمل المعرّفات). `VACUUM` قرار منفصل غير موصى به بلا قياس.
- **ترحيل نجح وتنظيف فشل:** نسختان (ازدواج قرص مؤقت)؛ الخريطة على الخاص؛ يعاد التنظيف لاحقاً idempotent.
- **Delete Account:** القائم يزيل مدخلات القديم لمفاتيح الكتالوج فقط؛ مدخلات قديمة لمفاتيح خارج الكتالوج (مثل بطاقات المفضلة لسجلات لم تُفتح تفاصيلها) **تبقى** (قائم قبل M1d) — يُعالج في M1d-3/M3 بكنس بالمفتاح لكل عنصر مملوك معروف.

**6) السلوك المرئي المحفوظ:** صور Offers/Owners offline (الخريطة تبقى صالحة؛ تصبح أدوم لأن الكاش الخاص لا يتشارك حد الـ 200 مع مدخلات المفضلة بالروابط)، الترتيب، العارض الكامل، المفضلة/البحث (لا تُمس؛ الخريطة تبقى تشير لملف موجود)، الـ avatar (لا يُمس)، الـ placeholders، البايتات (لا تنزيل من R2 للترحيل)، العزل.

**7) القياس (حتمي في الاختبارات؛ زمن الجهاز NOT MEASURED):** عدّادات في الاختبار: قراءات القديم (`fetchCachedBytes` override)، إصابات الخاص (`cached`)، الترحيلات (`adopt`)، التنزيلات وطلبات الروابط (`FileService` وهمي)، القرص قبل/بعد (مجموع أحجام `libCachedImageData/` و`bwPrivateMedia/`)، النسخ المكررة (تطابق SHA-256 بين المجلدين)، إعادة التشغيل (dispose/open)، زمن العرض (Stopwatch على VM فقط). **المتوقع:** 0 تنزيل و0 رابط لصورة قديمة؛ ترحيل واحد لكل صورة؛ ازدواج حتى M1d-3. **لا تغيير لسياسة 200/30.**

**8) الأمان المحفوظ:** ربط الحساب/الجلسة، SAD، تصريح R2 الموقّع، استثناءات M0.5، العنوان الزائف، عزل Delete Account، حماية القوائم المشفّرة والمفضلة؛ لا تشفير جديد؛ **الملف القديم ليس مصدر تصريح** (يُقرأ فقط بعد `canRead` ولمفتاح من مرجع الجلسة)؛ لا روابط/JWT في بيانات جديدة.

**9) خطة نقاط التفتيش (لم تبدأ):**
- **M1d-1 — ترحيل مُتحقَّق لكل صورة بلا حذف.** الملفات: `private_media_cache.dart` (`adopt` عبر تذكرة محلية)، `private_media_images.dart` (جدولة بعد إصابة قديمة)، اختبار جديد `test/offers/offer_media_legacy_migration_test.dart`. **قرارات:** D-M1d-1، D-M1d-2، D-M1d-5. **اختبار أولاً:** صورة قديمة ⇒ 0 تنزيل/0 رابط، ترحيل واحد، تطابق SHA-256، طول مسجّل؛ حساب آخر/خروج/تبديل أثناء الترحيل ⇒ لا كتابة؛ فيديو/PDF/مفتاح رابط/`resized_*`/profile ⇒ لا ترحيل؛ مبتور/غير صورة ⇒ رفض والقديم سليم؛ تزامن ترحيل+تنزيل ⇒ عملية واحدة؛ إعادة تشغيل ⇒ إصابة خاصة؛ لا رابط في الفهرس الخاص. **طفرات:** حذف فحص النطاق، قبول بلا توقيع سحري، `putFile` بدل المسار، ترحيل المفتاح المصغّر، كتابة بعد تبديل، حذف القديم. **التراجع:** الإضافي فقط؛ النسخ الخاصة تبقى (تُخلى طبيعياً). **الفائدة:** الصور القديمة تنجو من إخلاء الكاش المشترك؛ offline أدوم؛ صفر تنزيل.
- **M1d-2 — انتقال الخريطة (قارن-واستبدل).** الملفات: `offline_media_service.dart` (`replaceMediaIdMapping`)، `private_media_images.dart`. **قرار:** D-M1d-3. **اختبارات:** يُوجَّه فقط من القديم/الميت؛ لا يمس الأصل المتبنى؛ فشل ⇒ القديم كما هو؛ المفضلة/المشاركة تقرأ الملف الخاص. **طفرات:** كتابة بلا مقارنة، كتابة بعد تبديل. **التراجع:** الخريطة مسار — العودة لا تحتاج شيئاً (القديم باقٍ).
- **M1d-3 — تقاعد انتقائي (بعد M3).** الملفات: `offline_media_service.dart`/`private_media_images.dart` (`removeFile(key)` بعد التحقق والتوجيه). **قرارات:** D-M1d-4، D-M1d-6. **اختبارات:** صف واحد فقط يُحذف؛ حساب آخر/مفاتيح الروابط/`resized_*`/profile لا تُمس؛ فشل الحذف ⇒ ازدواج فقط؛ لا خريطة ميتة. **طفرات:** حذف قبل التوجيه، حذف بلا تحقق، `emptyCache`. **التراجع:** المحذوف يعاد تنزيله عند الحاجة (برابط). **الفائدة:** قرص أقل، فهرس قديم أصغر.

**10) قرارات المالك:**
- **D-M1d-1:** ترحيل عند العرض فقط (بعد إصابة قديمة في معرض Offer/Owner) — **موصى**؛ لا مسح خلفي.
- **D-M1d-2:** دليل الملكية = مفتاح بنته الجلسة الحالية (`canRead`) + مرجع جلسة (عنصر معرض/كتالوج الحساب) + توقيع صورة — **موصى**؛ أي غموض ⇒ لا ترحيل.
- **D-M1d-3:** إعادة توجيه `url_mapping` بقارن-واستبدل بعد التحقق — **موصى**.
- **D-M1d-4:** التقاعد لكل عنصر بعد M3 فقط، `removeFile(key)` للمفتاح الدقيق، بلا `emptyCache` ولا `VACUUM` — **موصى**.
- **D-M1d-5:** قبول ازدواج القرص حتى M1d-3 (كلاهما ≤ 200) — **موصى**.
- **D-M1d-6:** مدخلات المفضلة/البحث بمفتاح الرابط: تبقى حتى M3 والإخلاء الطبيعي؛ أي كنس لها قرار منفصل.

**المحفوظ:** FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ **M2** (هويات وسائط Offers/Owners في القوائم المشفّرة) و**M3** (المفضلة/البحث) و**M4** (الـ avatar) و**M5** (فيديو offline) معلّقة؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وتحقق Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit.

**الحالة:** **M1d = AUDIT + DESIGN مكتمل.** **NOW:** قرارات المالك D-M1d-1…6. **NEXT:** M1d-1 بعد الموافقة. **STOP:** لا تنفيذ؛ لا commit/push؛ لا M2/M3/الملف الشخصي/الفيديو.

### M1d-1 — ترحيل آمن عند العرض من كاش الصور القديم — 2026-11-08 (CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج)

**موافقة المالك:** D-M1d-1…D-M1d-6 **مُعتمدة كما أُوصي** بتنفيذ مرحلي صارم؛ هذه النقطة تخوّل **M1d-1 فقط** (ترحيل مُتحقَّق لكل صورة، بلا حذف وبلا تحويل خريطة).

**Git (مُتحقَّق قبل البدء):** الفرع `perf/phase-1-startup-baseline`؛ HEAD `7edee16` = `origin`؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ تصميم M1d غير المودع في §7AZ محفوظ؛ ملفات plugin الثلاثة لم تُلمس.

**1) ملفات الإنتاج (3):**
- `lib/src/services/private_media_cache.dart`: `PrivateMediaAdoption` (adopted/alreadyHeld/inProgress/notAllowed/unusableSource/failed)؛ `scopeFor(key)`؛ `adopt(key, source, origin:)` = تذكرة **محلية** عبر خدمة الملفات نفسها (`downloadFile(pseudoUrl, key, force: true)`) — نفس حد 10 MiB، نفس فحوص الجلسة، نفس الفهرس بعنوان وهمي فقط؛ + فحص توقيع `ImageSignatureDetector` (JPEG/PNG/WebP، صيغ الـ Worker)؛ قراءة الملف الناتج ومقارنته (SHA-256 + الحجم، `package:crypto` القائم)؛ `cached()` ينتظر أي `adopt` جارٍ لنفس الجلسة والمفتاح (لا تُسلَّم نسخة غير مُتحقَّقة)؛ إعادة هيكلة `_held` إلى `_valid`/`_holdsValid` بلا تغيير سلوك؛ `debugOnAdoptStep` (@visibleForTesting).
- `lib/src/services/private_media_images.dart`: بعد عرض ملف من الكاش القديم (إصابة قديمة، أو خريطة تشير إلى مدخل الكاش القديم نفسه) ⇒ `_copyLater` في الخلفية (لا ينتظره العرض)؛ نطاق الأصل يُلتقط عند بداية `load`؛ إزالة التكرار بالجلسة+المفتاح (`_copies`) وتسوية دائمة لهذه الدورة (`_settled`: adopted/alreadyHeld/notPrevious/unusableSource)؛ `_trusted`؛ خطافات اختبار `debugOnMigration`/`debugMigrationsSettled`/`debugForgetMigrations`.
- `lib/src/services/offline_media_service.dart`: `catalogueNamesMedia(ownerId, mediaObjectId)` — قراءة متزامنة فقط لقوائم وسائط الحساب.
- **اختبار جديد:** `test/offers/offer_media_legacy_migration_test.dart` (36). لا تغيير في أي اختبار قائم.

**2) قواعد الهوية الموثوقة (كلها مطلوبة؛ أي غموض ⇒ لا ترحيل):**
1. جلسة تطبيق حالية (`applicationScope`: حساب مُصادَق تطبيقياً + `isAuthorized` من SAD) — تُلتقط عند العرض وتُقارن **بالمساواة الكاملة (الحساب + session_id)** بعد كل انتظار.
2. المفتاح **حرفياً** `offer-media:<حساب الجلسة>:<mediaId>` ويساوي `offerMediaCacheKey(account, mediaId)`؛ `mediaId` بلا `:` (يُرفض `:poster`)؛ مفاتيح الروابط و`resized_*` والمعرّفات العارية (الملف الشخصي) لا حساب لها ⇒ لا تُقرأ أصلاً.
3. مصدر موثوق مقيّد بالحساب يسمّي `mediaId`: (أ) كتالوج وسائط **هذا الحساب** (`offerMediaCatalog::<account>::<record>`، يُكتب فقط من رد الـ Worker لهذا الحساب أو من رفع قبله الخادم)، أو (ب) رد الـ Worker في هذه الدورة (`OfferMediaUrlCache`، ذاكرة فقط، يُمسح عند تبديل الحساب) **وليس فيديو** — إن قال الـ Worker فيديو ⇒ مرفوض مهما قال الكتالوج.
4. المصدر هو مدخل الكاش القديم **للمفتاح الدقيق** (عند الخريطة: مسار الخريطة == مسار مدخل الكاش القديم، وإلا `notPrevious` — الأصل المتبنى/النسخة الخاصة لا تُنسخ).
5. الملف موجود ومقروء وغير فارغ و≤ 10 MiB، وبايتاته JPEG/PNG/WebP. **التوقيع يثبت الصيغة فقط، لا الملكية ولا الأصالة.** HEIC/فيديو/PDF ⇒ `unusableSource` (التطبيق يحوّل HEIC إلى JPEG قبل الرفع).
6. لا نسخة صالحة في الوجهة (فحص قبل البدء **وفحص ثانٍ داخل خدمة الملفات قبل تسليم البايتات مباشرة**).
- **لا يُستنتج شيء** من اسم ملف أو رابط موقّع أو `mediaId` وحده.

**3) العرض أثناء الترحيل:** `load` يعيد الملف القديم فوراً (كما في M1c) ثم يبدأ النسخ؛ إعادة الفتح أثناء النسخ ترسم الملف نفسه فوراً. `url_mapping` يبقى مسار الملف القديم (يسجّله M1c كما كان)؛ الكتالوج لا يتغير. المعرض والعارض الكامل يرسمان الملف القديم قبل النسخ وبعده (`FileImage`). النسخة الخاصة تُستخدم فقط إن اختفى الملف القديم (إخلاء) — عندها مسار M1c القائم يجدها بلا شبكة. التحويل = M1d-2.

**4) صفر شبكة (اختبار):** لا تذكرة رابط في مسار النسخ أصلاً (`_Ticket.local` بلا `signedUrl`)؛ `transport.urls` = 0 في كل اختبارات الترحيل؛ `get` بعد الترحيل لا يستدعي مُوقِّع الرابط (0)؛ قراءات الكاش القديم كلها `url=null` (مُتحقَّق في tearDown كل اختبار) ولا `removeCachedBytes` (0).

| (VM، 5 صور × 200 KiB) | قبل M1d-1 (معرّفات غير موثوقة) | بعد M1d-1 |
|---|---|---|
| إصابات الكاش القديم عند أول عرض | 5 | 5 |
| ترحيلات ناجحة | 0 | 5 (مرة واحدة لكل صورة) |
| إصابات الخاص بعد إخلاء القديم | 0 | 5 |
| تنزيلات بعد إخلاء القديم | **5** | **0** |
| طلبات توقيع رابط من مسار الصورة | 0 (مسار M1c لا يطلب روابط) | 0 |
| نمو القرص المؤقت | 0 | 1 024 000 بايت (= حجم الصور المنسوخة بالضبط) + صفوف الفهرس |
| الزمن (VM) | — | عرض الخمس: ~33–67 ms؛ اكتمال كل النسخ: ~140–167 ms |

**الأجهزة:** كل الأزمنة VM فقط — **NOT MEASURED على Samsung/iOS**.

**5) الفشل والانقطاع (كلها: القديم يبقى معروضاً وسليماً):**
- خروج/تبديل حساب/استبدال جلسة **أثناء قراءة المصدر** ⇒ `notAllowed`، لا كتابة. **بعد الكتابة وقبل التحقق** ⇒ النسخة تُزال (`notAllowed`) — لا نسخة تعيش بعد جلستها. الجلسة الجديدة تعيد المحاولة عند العرض التالي.
- انقطاع أثناء الكتابة (خطأ ملفات) ⇒ `failed`، لا نسخة جزئية؛ العرض التالي يعيد المحاولة وينجح.
- قراءة راجعة مختلفة (أقصر، أو نفس الحجم وبايت واحد مختلف) ⇒ `failed`، النسخة تُحذف، القديم يبقى معروضاً.
- تعذّر فتح الكاش الخاص (`path_provider`) ⇒ `failed`؛ القديم معروض.
- إغلاق الشاشة أثناء النسخ ⇒ يكتمل في الخلفية بلا أخطاء.
- عرض متزامن متعدد ⇒ نسخة واحدة وقراءة واحدة للمصدر؛ `adopt` بجانب تنزيل جارٍ ⇒ `inProgress` (التنزيل لا يُكتب فوقه)؛ نسخة صالحة ظهرت أثناء النسخ ⇒ `alreadyHeld` بلا كتابة.
- نسخة غير مُتحقَّقة لا تُسلَّم أبداً (`cached` ينتظر النسخ الجاري لنفس الجلسة).
- **إعادة التشغيل:** النسخة تُوجد (`alreadyHeld`، 0 قراءة، 0 شبكة)؛ نسخة تالفة من كتابة مقطوعة ⇒ فحص الطول القائم يزيلها ⇒ تُنسخ من جديد.
- الحذف عند الفشل يزيل **الملف الذي كتبه هذا النسخ فقط** (اسم UUID فريد) وصفه إن كان ما زال يشير إليه — لا يلمس أي مدخل أحدث.

**6) الاختبارات:** `offer_media_legacy_migration_test.dart` **36/36 ✅** (Offer، Owner، ثقة الـ Worker، عرض فوري أثناء النسخ، صفر رابط/تنزيل، نسخة خاصة موجودة، تنزيل جارٍ، نسخة ظهرت أثناء النسخ، أصل متبنى، نفس `mediaId` عبر حسابين، معرّف غير موثوق/حساب آخر/فيديو/`:poster`، مفاتيح روابط و`resized_*` وعارية، مفقود/مُخلى/تالف/فيديو/فارغ، > 10 MiB و= 10 MiB، خروج/تبديل/استبدال قبل الكتابة وبعدها، إعادة المحاولة في الجلسة الجديدة، انقطاع الكتابة، فشل التحقق ×2، فشل الكاش الخاص، إغلاق الشاشة، تزامن، نسخة غير مُتحقَّقة، إعادة تشغيل ×2، القديم/الخريطة/الكتالوج دون تغيير، لا روابط على القرص، المعرض والعارض الكامل، Delete Account، القياسات). **انحدار مركّز:** M1b/M1c/local-first/loading-UI/backup **147/147 ✅**؛ التشغيل الأخير بعد كل التعديلات (10 ملفات: الجديد + M1b/M1c + local-first/loading-UI/backup/security-cleanup/owner-media/search-card/favorites) **236/236 ✅**؛ `flutter analyze` على الملفات الأربعة: لا مشاكل؛ `dart format --set-exit-if-changed`: 0 تغيير (الملف الجديد فقط نُسّق آلياً؛ سطر واحد من الكود الجديد عُدّل يدوياً)؛ `git diff --check` نظيف؛ CRLF محفوظ؛ 34 ملف اختبار يستورد الخدمات المعدّلة **776 ✅ / 2 ✘ قائمان قبل M1d-1** (`delete_account_test` setUpAll: ملف الترحيل `20260913000100_account_deletion_jobs.sql` غير موجود بهذا المسار — إعادة تسمية سابقة؛ `delete_account_ui_test` «a completed deletion…» = FU-ACCOUNT-UI-BASELINE-1).

**الطفرات:** **18/20 مقتولة** (استعادة SHA-256 بعد كل طفرة): T1 كل معرّف موثوق، T2 فيديو من الـ Worker موثوق، T3 كتالوج أي حساب يشهد، S1 `adopt` يتجاهل الأصل، S2 لا فحص جلسة بعد قراءة المصدر، S3 النسخة تبقى بعد انتهاء جلستها، V1 بلا فحص توقيع، V2 بلا حد 10 MiB، V3 مقارنة بالحجم فقط، V5 بلا قراءة راجعة، C1 الكتابة فوق نسخة ظهرت، C2 `cached` يسلّم نسخة غير مُتحقَّقة (قُتلت بعد تشديد الاختبار)، C3 `adopt` بجانب تنزيل، C4 بلا إزالة تكرار، C5 بلا تسوية، H1 نسخ القديم عند خريطة لأصل، H2 بلا إعادة محاولة عبر الخريطة، H3 بلا نسخ عند إصابة قديمة. **ناجيتان مكافئتان:** V4 (فحص الحجم السريع مكرر مع SHA-256)، D1 (حذف الملف مباشرة؛ على VM يحذفه `removeFile` أيضاً لأن فهرس JSON يُكتب فوراً — يهم على SQLite حيث قد لا يكون للصف معرّف بعد). **لم يُطفَّر (دفاع إضافي بلا مدخل قابل للوصول):** رفض `:` في `mediaId` و`offerMediaCacheKey(...) == key` — الكتالوج لا يحمل معرّفاً بـ `:`.

**7) تكلفة القرص والذاكرة:** ازدواج مؤقت = حجم كل صورة منسوخة (≤ 10 MiB لكل صورة، والكاش الخاص ≤ 200 مدخل/30 يوماً — بلا تغيير) حتى M1d-3؛ الذاكرة: بايتات المصدر مرة واحدة (≤ 10 MiB، كمسار التنزيل في M1b) والقراءة الراجعة **متدفقة** (SHA-256 على `openRead`)؛ مجموعة `_settled` نصوص صغيرة لكل صورة معروضة في الدورة.

**8) القيود الأمنية الباقية:**
- مدخلات `DefaultCacheManager` التاريخية (`libCachedImageData.db`) **ما زالت تحمل روابط موقّعة سابقة** — M1d-1 لا يحذف شيئاً؛ لا يُدّعى غياب الروابط من القرص. حذف صف SQLite لاحقاً لا يمحو صفحاته الحرة.
- نسختان من كل صورة مرحَّلة (القديم + الخاص) حتى M1d-3.
- مرور ثانٍ ضيق جداً عبر جلستين لنفس الحساب (بين آخر فحص للجلسة وكتابة المكتبة) قد يكتب بايتات نفس `mediaId` — نفس البايتات (المعرّف غير قابل للتغيير) ويُقارَن بالقراءة الراجعة.
- إعادة المحاولة بعد انقطاع تحدث عند العرض التالي عبر `load` (المعرض يستدعيه عند وجود رابط أو غياب الخريطة)؛ فتح offline بخريطة تشير للقديم لا يعيد المحاولة حتى فتح online — آمن، فقط مؤجَّل.
- قرّاء المفضلة/البحث/النموذج/المشاركة بلا تغيير (FU-FAV-MEDIA-NO-IDENTITY).
- **الأجهزة:** REAL_DEVICE_UNVERIFIED (SQLite بدل JSON، مسح النظام لـ temp، الأزمنة).

**نقاط لاحقة:** **M1d-2** — تحويل `url_mapping` (قارن-واستبدل) = **نقطة تفتيش منفصلة تحتاج موافقة**؛ **M1d-3** — التقاعد الانتقائي **مؤجَّل إلى ما بعد M3 وبموافقة إضافية**.

**المحفوظ:** FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ M2/M3/M4/M5 معلّقة؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وتحقق Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية (FU-ACCOUNT-UI-BASELINE-1، ملف الترحيل المُعاد تسميته)؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit معلّقان؛ مستندات ADD_DETAILS المفقودة لم تُنشأ ولم تُحذف.

**الحالة:** **M1d-1 = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** ← حُدّثت بالمراجعة الأمنية النهائية أدناه.

#### M1d-1 — المراجعة الأمنية النهائية قبل الـ commit — 2026-11-09 (عيب واحد صُحّح؛ CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج)

**Git (مُتحقَّق):** HEAD `7edee16` = `origin`؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ ملفات plugin الثلاثة لم تُلمس.

**المراجعة 1 — تنظيف النسخ الفاشل: PASS (والطفرة D1 ليست مكافئة):**
- **حقيقة المكتبة:** `WebHelper` يكتب صف الفهرس **بلا انتظار** (`_store.putFile(...).then`) ثم يعيد الملف. على Windows/VM (فهرس JSON في الذاكرة) يكون للصف معرّف قبل التنظيف، فيحذف `removeFile` الملف أيضاً — لذلك نجت D1 سابقاً. على Android/iOS (SQLite عبر قناة المنصة) قد يصل الإدراج **بعد** التنظيف: `removeFile` يرى كائناً بلا معرّف فلا يفعل شيئاً.
- **محاكاة محمولة لترتيب SQLite** (فهرس JSON بإدراج مؤجَّل عبر معامل اختبار `debugRepository`): بعد فشل القراءة الراجعة (نفس الحجم، بايت مختلف) والإدراج المتأخر ⇒ **لا بايتات يتيمة** (الحذف المباشر لملف UUID الذي كتبه النسخ)، **لا مدخل مقروء**، والصف الشارد يُسقطه المكتبة عند أول بحث (الملف مفقود). **D1 الآن مقتولة** بهذا الاختبار وباختبار Delete Account بالإدراج المتأخر ⇒ D1 **خاصة بالجهاز لا مكافئة**؛ الحذف المباشر ضروري.
- **ملف تالف مقروء:** لا — يُحذف قبل أن يشير إليه أي صف؛ بدونه (D1) كان سيُقرأ على SQLite (طول الصف = الطول الصحيح).
- **تراكم القرص بعد فشل متكرر:** 5 محاولات فاشلة متتالية ⇒ 0 ملفات و0 صفوف (اختبار).
- **REAL_DEVICE_UNVERIFIED:** توقيت SQLite الفعلي على Samsung/iOS؛ **وحالة قائمة في المكتبة لا تخص M1d-1:** خطأ كتابة أثناء `_saveFile` (قرص ممتلئ/خطأ I/O) يترك ملف UUID جزئياً **بلا صف** — غير مقروء، لكن الإخلاء القائم على الصفوف لا يراه؛ ينطبق على تنزيلات M1b أيضاً؛ بالنسبة لـ M1d-1 لا يحدث إلا بخطأ تخزين (البايتات في الذاكرة)، ومحاولة واحدة لكل عرض. فشل الحذف المباشر نفسه (قفل ملف) يترك ملفاً واحداً حتى الإخلاء — موثّق.

**المراجعة 2 — الجلسة والتزامن: كان FAIL في نقطتين ⇒ صُحّح ⇒ PASS:**
- **العيب (أُعيد إنتاجه باختبارين فاشلين قبل التصحيح):** انتظار «النسخ الجاري» في `cached()` كان **لكل جلسة**؛ فإن استُبدلت الجلسة (نفس الحساب) بعد كتابة النسخة وقبل التحقق: (أ) الجلسة الجديدة **تُعطى النسخة غير المُتحقَّقة** للجلسة القديمة؛ (ب) ثم يحذفها تنظيف الجلسة القديمة ⇒ ملف الجلسة الجديدة يختفي (وتُسوّى `alreadyHeld` خطأً لتلك الدورة).
- **التصحيح (الأدنى، `private_media_cache.dart` فقط):** `_adopting` بالمفتاح لا بالجلسة+المفتاح — `cached()` (ومن ثم `get()`) ينتظر أي نسخ جارٍ لنفس العنصر مهما كانت جلسته، و`adopt` لا يبدأ إن كان نسخ آخر للعنصر جارياً (`inProgress`). لا تغيير آخر في السلوك.
- (1) كل نسخ مقيّد بحساب وجلسة الأصل (يُلتقط عند العرض، مساواة كاملة بعد كل انتظار) ✔. (2) جلسة مُزاحة لا تنشر بايتات: قبل الكتابة لا كتابة، بعدها حذف، والجلسة الجديدة لا ترى النسخة قبل الحسم ✔ (اختبار جديد). (3) تنظيف الجلسة القديمة لا يحذف نسخة صالحة للجلسة الأحدث: تنزيل الجلسة الأحدث ينتظر الحسم ثم يكتب نسخته؛ والتنظيف يحذف ملف UUID الخاص به فقط ✔ (اختبار جديد). (4) نسخ وتنزيل متزامنان: نفس الجلسة ⇒ `inProgress` أو التنزيل ينتظر ويعيد استخدام النسخة (0 تنزيل)؛ جلستان ⇒ الأقدم يفشل فحص الجلسة ✔. (5) فشل/إلغاء ⇒ الصورة القديمة متاحة ✔. (6) Delete Account: `completeAccountDeletion` يُخرج الجلسة **قبل** المنظّف ⇒ النطاق null ⇒ أي نسخ جارٍ يُرفض أو يُحذف بعد الكتابة؛ مُختبر بالترتيبين (صف فوري ومتأخر): لا ملف، لا مدخل حتى لجلسة لاحقة للمعرّف نفسه، والقديم سليم ✔.

**المراجعة 3 — الصيغ: PASS (HEIC غير مدعوم عمداً):** الإنتاج يقبل للنسخ **JPEG وPNG وWebP فقط** (`ImageSignatureDetector`، نظير فحص الـ Worker؛ التطبيق يحوّل HEIC إلى JPEG قبل الرفع، فلا صورة Worker بصيغة HEIC). بايتات HEIC ⇒ `unusableSource` (تُسوّى، لا إعادة محاولة في الدورة)، الصورة القديمة معروضة كما هي، **0 تنزيل** (اختبار جديد). قائمة امتدادات M1b (`.heic`) لمسار التنزيل لم تتغير. لا مفكك ولا تبعية جديدة. **قيد موثّق:** صورة HEIC قديمة (إن وُجدت) تبقى في الكاش القديم فقط.

**المراجعة 4 — لا تعديلات غير متوقعة: PASS:** مراجعة الـ diff: لا كتابة/حذف لـ `DefaultCacheManager` ولا `url_mapping` ولا `local_media` في الكود الجديد (الأسطر المحذوفة إعادة تشكيل فقط)؛ المعرض والعارض الكامل كما في M1c (اختبار)؛ الفهرس الخاص بالعنوان الوهمي فقط (اختبار)؛ لا تنزيل تلقائي ولا ترحيل جماعي؛ 200 مدخل / 30 يوماً / 10 MiB دون تغيير؛ فحوص M1b (`get`/`_fetch`/خدمة الملفات الشبكية/`canRead`) وM1c (`heldNow`/`load`) سليمة — `debugRepository` معامل اختبار فقط (الإنتاج يبني `Config` كما كان).

**الاختبارات:** `offer_media_legacy_migration_test.dart` **43/43 ✅** (+7: صف متأخر بعد التنظيف، فشل متكرر، الجلسة الجديدة لا ترى نسخة غير مُتحقَّقة، تنظيف القديم لا يحذف نسخة الأحدث، Delete Account أثناء النسخ ×2، HEIC؛ واستُبدل اختبار «نسخة ظهرت أثناء النسخ» بـ «تنزيل أثناء النسخ ينتظر ويعيد استخدامه» لأن ذلك الترتيب صار مستحيلاً بالتصحيح). **الانحدار المركّز (10 ملفات):** **243/243 ✅**. `flutter analyze` (4 ملفات): لا مشاكل؛ التنسيق 0 تغيير (الملف الجديد فقط نُسّق)؛ `git diff --check` نظيف؛ CRLF محفوظ. لم يُعَد الانحدار الواسع (34 ملفاً) — التغيير محصور في `cached`/`adopt` ومعامل اختبار.

**الطفرات (إعادة تشغيل كاملة، استعادة SHA-256):** **19/21 مقتولة** — الـ 18 السابقة + **D1** (مقتولة الآن) + **C6** جديدة (`cached` ينتظر جلسته فقط = العيب) مقتولة. **الناجيتان:** **V4** مكافئة فعلاً (فحص الحجم السريع قبل SHA-256)؛ **C1** (`destinationFree`) صارت **غير قابلة للوصول** بعد التصحيح — كل كاتب (`get`/`adopt`) ينتظر النسخ الجاري أو يُستبعد؛ تبقى دفاعاً إضافياً بلا كلفة.

**المحفوظ:** **M1d-2** بانتظار موافقة منفصلة؛ **M1d-3** مؤجَّل إلى ما بعد M3؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول الأجهزة **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit معلّقان؛ مستندات ADD_DETAILS المفقودة لم تُنشأ ولم تُحذف.

**الحالة:** **M1d-1 (+ المراجعة النهائية) = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** موافقة المالك على الـ commit. **STOP:** لا commit/push؛ لا بدء M1d-2/M1d-3/M2.

### M1d-2 — تحويل آمن لـ `url_mapping` إلى النسخة الخاصة المُتحقَّقة — 2026-11-09 (CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج)

**Git (مُتحقَّق بعد fetch):** الفرع `perf/phase-1-startup-baseline`؛ HEAD `a665814` = `origin` (دفع المالك مؤكَّد)؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ ملفات plugin الثلاثة لم تُلمس.

**1) مراجعة المسار الحالي (Phase 1):**
- **أين يُعلن اكتمال النسخ:** `PrivateMediaImages._copy` بعد `adoptCopy` (جديدة: تعيد النتيجة + الملف المُتحقَّق؛ `adopt` يفوّض إليها بلا تغيير سلوك). **التحقق كامل:** القراءة الراجعة SHA-256 + الحجم داخل `_adopt` (M1d-1).
- **ثبات المسار:** ملف الكاش الخاص `<temp>/bwPrivateMedia/<uuid>.<ext>` ثابت عبر إعادة التشغيل ما لم يُخلَ (200/30) أو يمسح النظام المجلد المؤقت.
- **بعد الإخلاء (قبل M1d-2):** `load` يتعافى (الخاص ⇒ القديم بالمفتاح الدقيق ⇒ يعيد تسجيل الخريطة)؛ المفضلة/البحث تتعافى (`CachedNetworkImage` بالمفتاح، `ensureMediaIdCached` ⇒ القديم). **لكن** البذرة المتزامنة للتفاصيل (`_cachedRecordMedia` ⇒ `_localPathFor`) و`heldNow` تقرآن الخريطة فقط ⇒ خريطة تشير لنسخة خاصة مُخلاة ⇒ **العنصر يُسقط من الإطار الأول وفتح offline لا يعرضه** رغم أن الملف القديم ما زال موجوداً. ⇒ تحويل بسيط كان سيخفي صورة كانت مرئية. **⇒ أصغر احتياط آمن داخل M1d-2 (لا تغيير معماري):** التحويل يحفظ المسار القديم كـ **احتياط** للمفتاح نفسه، ويقرأه القارئان المتزامنان فقط حين يكون الملف الأساسي مفقوداً.
- **كشف الخريطة القديمة:** `existsSync` (قائم)؛ الآن: أساسي مفقود ⇒ الاحتياط إن وُجد.
- **الملف القديم بمفتاحه الأصلي:** نعم — `DefaultCacheManager.getFileFromCache(<exact key>)` (M1d-1 لا يحذف شيئاً).
- **القرّاء الحيّون لـ `url_mapping`:** `heldNow` (المعرض/العارض)، `_localPathFor` (بذرة التفاصيل + `_refFor` + بطاقات البحث عبر `cachedOfferMedia`)، `buildOfflineAwareImage` و`ensureMediaIdCached` (المفضلة/البحث/المشاركة)، نموذج التعديل، ملصقات الفيديو (مفاتيح `:poster` — لا تُحوَّل).
- **التسلسل والعزل:** كتابات Hive في عزلة واحدة؛ `box.get` و`putAll` يحدّثان الذاكرة **متزامناً** قبل أول انتظار ⇒ «قارن-واستبدل» ذري بالنسبة لحلقة الأحداث. المفتاح يحمل الحساب.

**2) عقد التحويل (compare-and-set):** `OfflineMediaService.replaceMediaIdMapping(key, expected, replacement, previous)`: يكتب فقط إن كانت الخريطة **ما زالت حرفياً `expected`** (القيمة الملتقطة عند عرض الصورة)؛ يكتب الاحتياط **أولاً** ثم الأساسي في `putAll` واحد (كتابة مقطوعة تترك الاحتياط فقط، لا خريطة محوّلة بلا احتياط). الشروط كلها في `_switch`:
1. الهوية موثوقة ومقيّدة بالحساب (قاعدة M1d-1 نفسها).
2. القيمة الملتقطة = **ملف الكاش القديم المعروض** أو **نسخة لم تعد موجودة** (إصلاح بعد إخلاء)؛ أي ملف آخر موجود (أصل متبنى، نسخة أخرى) ⇒ لا تحويل.
3. النسخة الخاصة مُتحقَّقة (القراءة الراجعة) **و**بايتاتها = بايتات الملف القديم الآن (SHA-256 + الحجم، قراءة متدفقة).
4. النسخة موجودة لحظة التحويل.
5. الجلسة الأصلية (حساب + session_id) حالية — **يُفحص بلا أي انتظار قبل المقارنة والكتابة**.
6. الخريطة لم تتغير (المقارنة نفسها) ⇒ لا تكتب نتيجة أقدم فوق خريطة أحدث.
- **صورة نسخها M1d-1 سابقاً** (الخريطة ما زالت قديمة): تُحوَّل عند أول عرض (`alreadyHeld` + `switched`) بلا نسخة ثانية.

**3) الإخلاء وإعادة التشغيل:** `usableLocalPathForMediaId` = الأساسي إن وُجد، وإلا الاحتياط إن وُجد (قراءة Hive واحدة؛ الثانية فقط عند فقد الأساسي). إخلاء النسخة الخاصة ⇒ الإطار الأول والبذرة offline يعرضان الملف القديم ⇒ العرض يعيد النسخ والتحويل **في الدورة نفسها** (`again`: عرض من الاحتياط يتجاوز التسوية). إعادة التشغيل بخريطة صالحة ⇒ عرض فوري بلا عمل ولا شبكة؛ بخريطة ميتة ⇒ الاحتياط ثم إصلاح. نسخة تالفة (طول خاطئ) ⇒ تُعرض مرة كما هي، يكتشفها فحص الطول في الدورة التالية ويزيلها ⇒ تُنسخ من القديم وتُحوَّل في العرض نفسه.

**4) الفشل والتعافي:** فشل النسخ ⇒ الخريطة كما هي، لا احتياط. خريطة غيّرها كاتب آخر ⇒ `changed`، تبقى الأحدث. حساب آخر/خروج/جلسة مُزاحة قبل التحويل ⇒ `notAllowed`؛ الجلسة الجديدة تحوّل عند عرضها. نسخة اختفت ⇒ `missing`. بايتات مختلفة ⇒ `differs`. فشل كتابة الخريطة ⇒ `failed`، **لا حذف** لأي ملف (Hive يُرجع الذاكرة عند فشل الكتابة). Delete Account أثناء النسخ أو قبيل التحويل ⇒ لا شيء يعود (الخروج يسبق المنظّف ⇒ النطاق null)؛ `_removeArtifactsFor` يزيل الآن **الاحتياط** مع الخريطة؛ مسح `forgetProfileMedia` الشامل يلتقطه (بادئة `mediaId::`). خريطة حساب آخر لا تُمس. لا تنزيل جديد: الملفان مفقودان + لا رابط ⇒ لا شيء ولا طلب.

**5) العدّ (VM حتمي؛ الجهاز NOT MEASURED):** 5 صور: **5 تحويلات**، 5 نسخ (قراءة مصدر واحدة لكل صورة)، **0 تنزيل، 0 طلب توقيع**، 5 قراءات للكاش القديم عند أول عرض ثم **0** عند إعادة الفتح؛ إعادة الفتح ⇒ **5/5 إصابات خاصة متزامنة** (heldNow للخمس ≈ 0.7–1.0 ms)؛ بعد إخلاء الخاص ⇒ **5/5 من الاحتياط**؛ عمل متزامن مكرر = 0 (5 عروض متزامنة ⇒ نسخة واحدة وتحويل واحد)؛ زمن أول عرض (الملف القديم، لا ينتظر التحويل) ≈ 3.6–6.2 ms على VM. قراءات الخريطة: واحدة لكل عرض، +1 فقط حين يكون الأساسي مفقوداً.

**6) الملفات الإنتاجية (4):** `offline_media_service.dart` (`previousCopyPathForMediaId`، `usableLocalPathForMediaId`، `replaceMediaIdMapping`، إزالة الاحتياط في `_removeArtifactsFor`)؛ `private_media_images.dart` (`heldNow` بالاحتياط، التقاط الخريطة عند العرض، `_switch`، `again` بعد الإخلاء، مصدر قديم حين اختفى المعروض التالف، خطافات اختبار)؛ `private_media_cache.dart` (`adoptCopy`)؛ `supabase_core_entities_service.dart` (`_localPathFor` = `usableLocalPathForMediaId`؛ حُذف استيراد `dart:io` غير المستخدم). **اختبار جديد:** `test/offers/offer_media_mapping_switch_test.dart`؛ **تحديث مقصود** لـ 5 اختبارات M1d-1 كانت تثبت «الخريطة دون تغيير» (العقد السابق).

**7) الاختبارات والطفرات:** `offer_media_mapping_switch_test.dart` **29/29 ✅** (Offer وOwner يُحوَّلان مع الاحتياط؛ **التحويل يحدث بلا أي خطاف اختبار**؛ العرض لا ينتظر التحويل؛ صورة نسخها M1d-1 سابقاً تُحوَّل؛ فشل النسخ؛ كاتب آخر غيّر الخريطة؛ تبديل حساب/خروج/استبدال جلسة قبيل التحويل؛ الجلسة الجديدة تحوّل عند عرضها؛ نسخة اختفت؛ بايتات مختلفة؛ فشل كتابة الخريطة دون حذف؛ خريطة حساب آخر؛ 5 عروض متزامنة ⇒ نسخة وتحويل واحد؛ Delete Account أثناء النسخ وقبيل التحويل وبعده (يزيل الاحتياط)؛ إخلاء ⇒ القديم ثم إصلاح في الدورة نفسها؛ **بذرة offline الحقيقية (`SupabaseCoreEntitiesService.cachedOfferMedia`/`cachedOwnerMedia`) تبقي العنصر بالملف القديم بعد الإخلاء**؛ الملفان مفقودان ⇒ لا شيء ولا طلب؛ نسخة تالفة ⇒ إصلاح في الدورة التالية؛ إعادة تشغيل بخريطة صالحة/ميتة؛ لا رابط ولا تنزيل عند الإصابة؛ قرّاء المفضلة/البحث نفس البايتات ويتعافون؛ لا روابط محفوظة والقديم سليم؛ القياسات). **M1d-1** `offer_media_legacy_migration_test.dart` **43/43 ✅** بعد **5 تحديثات مقصودة** (كانت تثبت «الخريطة دون تغيير»/«يرسم الملف القديم»: الآن الخريطة = النسخة المُتحقَّقة والاحتياط = القديم، والمعرض/العارض يرسمان النسخة بنفس البايتات). **التركيز الأخير (11 ملفاً):** **272/272 ✅**. **الانحدار المتأثر (41 ملفاً: الـ 34 التي تستورد الخدمات المعدّلة + M1b/M1c/M1d):** **961 ✅ / 3 ✘** — اثنان قائمان (`delete_account_test` setUpAll: ملف الترحيل المُعاد تسميته؛ FU-ACCOUNT-UI-BASELINE-1) وثالث **متقلب بالتوقيت تحت الحمل** (`offline_lists_unchanged_save_test` «the saved list is shown before its fingerprint…»: يعتمد على Stopwatch، لا يستخدم أي مسار معدّل، ينجح 3/3 منفرداً). `flutter analyze` (6 ملفات): لا مشاكل؛ التنسيق 0 تغيير (الجديد فقط نُسّق آلياً، سطر واحد يدوياً)؛ `git diff --check` نظيف؛ CRLF محفوظ في ملفات lib.

**عيب اكتُشف أثناء التنفيذ وصُحّح قبل التسليم:** `debugOnMapping?.call(key, await _switch(...))` — النداء الآمن-للفراغ **لا يقيّم وسائطه** حين يكون الخطاف null ⇒ في الإنتاج لم يكن التحويل سيحدث أبداً (اختبارات الملف الجديد كانت تضبط الخطاف دائماً فأخفته؛ كشفه تناقض نتائج ملف M1d-1). التصحيح: حساب النتيجة أولاً؛ اختبار «بلا خطافات» + الطفرة W13 تحرسه.

**الطفرات (استعادة SHA-256 بعد كل طفرة):** **13/14 مقتولة** — W1 بلا compare-and-set، W2 بلا احتياط، W3 القرّاء يتجاهلون الاحتياط، W4 البذرة تقرأ الخريطة الخام، W5 `heldNow` يقرأ الخام، W6 بلا فحص جلسة قبل التحويل، W7 بلا مقارنة بايتات، W8 تحويل إلى نسخة مفقودة، W10 بلا إعادة نسخ بعد إخلاء في الدورة نفسها، W11 التنظيف يبقي الاحتياط، W12 الاحتياط يسجّل النسخة لا القديم، W13 التحويل لا يحدث إلا بخطاف، W14 النسخة التالفة لا تُنسخ من القديم. **ناجية واحدة:** **W9** (رفض التحويل من ملف موجود غير قديم) — غير قابلة للوصول بترتيب النداء الحالي (الخريطة تُلتقط متزامنة بعد العرض/كتابة الخريطة)؛ تبقى حارساً إن تغيّر الترتيب.

**8) القيود الباقية:** الملفات القديمة وروابطها التاريخية في `libCachedImageData.db` باقية (M1d-3 بعد M3)؛ ازدواج القرص حتى M1d-3؛ ملف خاص تالف بنفس الحجم لا يُكتشف (لا تجزئة عند العرض) — يُعرض كخطأ صورة؛ نسخة تالفة في الدورة نفسها بعد تسويتها لا يعاد فحصها حتى الدورة التالية؛ قرّاء المفضلة/البحث يقرؤون الخريطة الأساسية مباشرة (بلا احتياط) ويتعافون عبر الكاش القديم كما قبل M1d-2 — قد يعيد `ensureMediaIdCached` الخريطة إلى الملف القديم بعد إخلاء، ثم يُعاد التحويل عند عرض التفاصيل (FU-FAV-MEDIA-NO-IDENTITY)؛ نموذج التعديل يقرأ الخريطة الخام (مسار online). مسارات مطلقة في الخريطة: انتقال حاوية التطبيق على iOS يجعلها ميتة (قائم لكل الخرائط). **الأجهزة:** REAL_DEVICE_UNVERIFIED — توقيت SQLite، مسح النظام لـ temp، أزمنة العرض.

**المحفوظ:** **M1d-3** التقاعد مؤجَّل إلى ما بعد M3؛ **M1e** قياسات الأداء على الجهاز؛ **M2** هويات وسائط Offers/Owners المشفّرة؛ **M3** وسائط المفضلة/البحث؛ **M4** الـ avatar؛ **M5** فيديو offline؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit معلّقان؛ مستندات ADD_DETAILS لم تُنشأ ولم تُحذف.

**الحالة:** **M1d-2 = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** ← حُدّثت بالمراجعة النهائية أدناه.

#### M1d-2 — المراجعة الأمنية النهائية قبل الـ commit — 2026-11-09 (لا عيب في الإنتاج؛ تقوية اختبار واحد؛ غير مدمج)

**Git (مُتحقَّق بعد fetch):** HEAD `a665814` = `origin`؛ الفهرس فارغ؛ الـ stashes الاثنان باقيان؛ الملفات المعدّلة = السبعة المتوقعة بالضبط (+ ملفات plugin الثلاثة غير الملموسة).

**A) ذرية compare-and-set: PASS.** من مصدر Hive 2.2.3: `putAll` ⇒ `_writeFrames` يستدعي `keystore.beginTransaction` (تحديث الذاكرة) **قبل أول `await`**، و`box.get` يقرأ الذاكرة. في `_switch`: فحص الجلسة ⇒ `copy.existsSync()` ⇒ `defaultSwitchMapping` (غير async) ⇒ `replaceMediaIdMapping`: المقارنة ⇒ التحديث — **كلها تشغيل متزامن واحد** في العزلة الوحيدة التي تستخدم Hive، فلا يمكن لأي كاتب آخر (`mapMediaIdToLocalFile`، `ensureMediaIdCached`، الحذف) أن يتداخل بينها. كاتب أحدث قبل المقارنة ⇒ رفض (`changed`، اختبار حتمي)؛ بعدها ⇒ يكتب فوقها (الأحدث يفوز). فشل كتابة القرص ⇒ `cancelTransaction` ينقل القيمة السابقة إلى أي معاملة أحدث للمفتاح نفسه بدل استعادتها ⇒ فشلنا لا يُرجع كتابة أحدث. ABA (تغيّر ثم عاد للمسار القديم نفسه) ⇒ التحويل آمن: البايتات قورنت بذلك الملف بعينه.

**B) عزل الاحتياط: PASS.** الكاتب الوحيد: `replaceMediaIdMapping` من `_switch` (جلسة الأصل حالية + هوية موثوقة + بايتات متطابقة)؛ القيمة = مسار ملف الكاش القديم **للمفتاح الدقيق نفسه** (مسار فقط، لا رابط ولا رمز). القارئان الوحيدان: `heldNow` (بعد `canRead`: نطاق حالي وحساب المفتاح) و`_localPathFor` (مفاتيح مبنية من حساب العميل الحالي) ⇒ حساب آخر لا يبني مفتاح الحساب الأول أبداً؛ خروج ⇒ `canRead` false / البذرة فارغة؛ جلسة مُزاحة لا تنشر (`notAllowed`، اختبار). الاحتياط **ليس إذناً مستقلاً**: نفس بوابات الخريطة الأساسية قبل M1d-2 (كان المسار القديم نفسه هو الأساسي). مفقود/مُخلى ⇒ `existsSync` false ⇒ غائب (اختبار). المفضلة/البحث: تقرأ الأساسي الخام دون تغيير الكود — بعد التحويل نفس البايتات من النسخة الخاصة، وبعد الإخلاء تتعافى عبر الكاش القديم كما قبل (اختبار)؛ بطاقات البحث عبر `cachedOfferMedia` تعود إلى سلوك ما قبل M1d-2 (المسار القديم) عند الإخلاء.

**C) Delete Account والكتابات المتأخرة: PASS (مع فجوة قائمة موثّقة).** `_forgetOfferMedia(deletedUid)` ⇒ لكل مفتاح في كتالوج الحساب `_removeArtifactsFor`: الأساسي **و**الاحتياط والنسخة الخاصة ومدخل الكاش القديم (طلب المنظّف القائم)؛ ثم `forgetAccount` يزيل كل ملفات الحساب الخاصة فقط؛ وإن كان الحساب المحذوف هو المسجَّل: `forgetProfileMedia()` يمسح كل مدخلات `mediaId::` (الاحتياطات ضمنها). الخروج يسبق المنظّف ⇒ `_switch` يرفض بعده؛ كتابة الخريطة في `load` تحدث في الذاكرة في نفس التشغيل المتزامن لفحص `canRead` ⇒ لا تُنشأ بعد الخروج؛ اختبارات: أثناء النسخ، قبيل التحويل، بعده. خرائط الحسابات الأخرى لا تُمس (اختبار). الملف القديم لا يحذفه M1d-2 أبداً (فشل/انقطاع/حذف). **فجوة قائمة قبل M1d-2، تشمل الآن الاحتياط أيضاً:** مفتاح موثوق برد الـ Worker فقط ولم يُكتب كتالوجه (فشل Hive نادر) **و**حساب آخر مسجَّل وقت الحذف ⇒ تبقى مسارات (لا بايتات خاصة) بمفتاح الحساب المحذوف — لا يمكن عنونتها من أي حساب آخر. متابعة مقترحة: كنس مدخلات `mediaId::offer-media:<uid>:` بالبادئة في `forgetOfferMedia(ownerId)` (نقطة منفصلة).

**D) إعادة التشغيل والإخلاء: PASS مع قيود.** خريطة خاصة صالحة ⇒ فوري بلا عمل/شبكة ✔؛ خاص مفقود + احتياط صالح ⇒ القديم ثم إصلاح ✔؛ إخلاء ثم فتح offline ⇒ البذرة الحقيقية تبقي العنصر بالملف القديم ✔؛ الاثنان مفقودان ⇒ لا شيء ولا طلب ✔ (اختبارات). **نسخة تالفة بالحجم نفسه:** **لا تُكتشف** — فحص الطول لا يضمن سلامة الصورة؛ تُعرض كخطأ صورة (أو بكسلات خاطئة إن فُكّت)؛ المقارنة SHA-256 تحدث عند النسخ والتحويل فقط. **مسار مطلق صار غير صالح** (نقل حاوية تطبيق iOS عند تحديث/استعادة): الأساسي والاحتياط ميتان ⇒ `heldNow` null ⇒ `load` يجد النسخة الخاصة عبر فهرسها (مسار نسبي إلى مجلد temp الحالي) ويعيد تسجيل الخريطة (سلوك M1c، اختبار `/gone`)؛ **لكن البذرة offline تُسقط العنصر حتى فتح online** — قائم لكل الخرائط. **إصلاح لاحق لازم:** تخزين المسارات نسبيةً إلى مجلدها (temp/support/documents) وحلّها عند القراءة — نقطة منفصلة (M1e/M2).

**E) التحويل يعمل في الإنتاج: PASS.** كل نداءات الخطافات الآمنة-للفراغ (5) تمرّر قيماً جاهزة فقط (لا `await` ولا آثار جانبية في الوسائط). **تقوية اختبار:** «the switch happens with no test hooks installed» صار يُلغي **كل** الخطافات (`debugOnMapping`، `debugOnMigration`، `debugBeforeMappingSwitch`، `cache.debugOnAdoptStep`، `switchMapping` الافتراضي، `debugLoad` null) ويتحقق من التحويل والبايتات والاحتياط و0 تنزيل ⇒ **1/1 ✅**؛ الطفرة **W13** (إعادة العيب) **مقتولة** به. لا سلوك إنتاجي يعتمد على أدوات الاختبار.

**F) السلوك المحمي: PASS.** فحص الـ diff الإنتاجي: الإضافات الوحيدة التي تمس التخزين = حذف الاحتياط في `_removeArtifactsFor` و`putAll` في compare-and-set؛ لا حذف لمدخلات `DefaultCacheManager`، لا ترحيل جماعي، لا ترحيل لمفاتيح الروابط، لا تنزيل جديد، لا كتابة لـ `local_media`، حدود 200/30 و10 MiB كما هي، لا صيغ قوائم مشفّرة، لا Auth/SAD/Supabase/Cloudflare، لا PDF/فيديو/Smart Map/Toolkit؛ الأسطر المحذوفة إعادة تشكيل فقط (فحص النطاق انتقل إلى `adoptCopy`).

**التغييرات في هذه المراجعة:** لا تغيير إنتاجي. اختبار واحد قُوّي (`offer_media_mapping_switch_test.dart`) + تنسيق الملف الجديد؛ شُغّل ذلك الاختبار وحده + W13 فقط (لا إعادة للمجموعات).

**الملفات السبعة الجاهزة:** `lib/src/services/offline_media_service.dart`، `lib/src/services/private_media_images.dart`، `lib/src/services/private_media_cache.dart`، `lib/src/services/supabase_core_entities_service.dart`، `test/offers/offer_media_mapping_switch_test.dart` (جديد)، `test/offers/offer_media_legacy_migration_test.dart` (محدّث)، `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md`.

**المحفوظ:** **M1d-3** مؤجَّل إلى ما بعد M3؛ **M1e**؛ **M2**؛ **M3**؛ **M4**؛ **M5**؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit معلّقان. **جديد للمتابعة (غير مبدوء):** كنس خرائط الحساب المحذوف بالبادئة؛ مسارات خرائط نسبية (حاوية iOS)؛ كشف التلف بنفس الحجم.

**الحالة:** **M1d-2 (+ المراجعة النهائية) = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** موافقة المالك على الـ commit. **STOP:** لا commit/push؛ لا بدء M1d-3/M1e/M2/M3.

### DA-MAP — فجوة تنظيف خرائط الوسائط عند Delete Account — 2026-11-09 (AUDIT + DESIGN؛ SOURCE-READ؛ لا تغيير كود)

**Git (مُتحقَّق بعد fetch):** الفرع `perf/phase-1-startup-baseline`؛ HEAD `45b275e` = `origin` (دفع M1d-2 مؤكَّد)؛ الفهرس فارغ؛ شجرة العمل **نظيفة**. **تغيّر منذ النقطة السابقة (من المالك، لم يُلمس):** صارت هناك **ثلاثة** stashes — جديد `stash@{0}` «On iOS-branch: !!GitHub_Desktop<iOS-branch>» (2026-11-09 13:23، فرع `iOS-branch` = `45b275e`، بلا فرق محتوى ظاهر — على الأرجح تعديلات نهايات الأسطر لملفات plugin الثلاثة التي لم تعد معدّلة)؛ الاثنان السابقان باقيان كـ `stash@{1}` و`stash@{2}`.

**1) ما يُزال اليوم (`DeletedAccountLocalDataCleaner.clear` بعد الخروج):** `completeAccountDeletion` يُخرج الجلسة **أولاً** ثم يستدعي المنظّف بـ `deletedUid` (معامل من مسار الحذف). خطوات الوسائط: (أ) `_purgeOfferMediaUploads`؛ (ب) `forgetOfferMedia(ownerId: deletedUid)`: يقرأ كتالوجات `local_media` بمطابقة **مالك حرفية** (`offerMediaCatalog::<uid>::<record>`) ويحذفها، ولكل معرّف فيها `_removeArtifactsFor(offer-media:<uid>:<id>)` = الخريطة الأساسية + احتياط M1d-2 + خريطة/أصل `:poster` + النسخة الخاصة + مدخل الكاش القديم **بالمفتاح الدقيق** + الأصل المتبنى داخل `offer_media/` فقط + إشعار الذاكرة؛ ثم `_sweepOfferOriginals(uid)` يحذف أصول `offer_media/` ببادئة اسم الملف (حتى بلا كتالوج)؛ (ج) `PrivateMediaCache.forgetAccount(uid)` يعدّد فهرس الكاش الخاص ويزيل كل `offer-media:<uid>:`/`profile-media:<uid>:` (حتى بلا كتالوج)؛ (د) إن كان الحساب المحذوف هو المسجَّل (`wasSignedInAccount`): `forgetProfileMedia()` بلا قائمة ⇒ يمسح **كل** مدخلات `mediaId::` في `url_mapping` لكل الحسابات (+ `DefaultCacheManager.removeFile` لكل منها) — تصميم قائم مقبول («caches غير مقسّمة، كلفتها تنزيل إضافي»)؛ وإلا `forgetProfileMedia(mediaIds: [معرّف الصورة الحالي])` فقط.

**2) الفجوة المؤكَّدة (بالكود، لا بالملاحظة على جهاز):** `url_mapping` **لا يُعدَّد أبداً بحسب الحساب**. فحين `wasSignedInAccount == false` — حساب آخر مسجَّل وقت المنظّف (حالة المصالحة/الحجر حين يكون الحساب الحي غير المحذوف، أو تسجيل حساب آخر أثناء الخروج) — تبقى كل مدخلات `mediaId::offer-media:<deletedUid>:…` لمعرّفات **لا يسمّيها كتالوج**: الأساسي، `:poster`، `::previous-copy`. **مصادر معرّفات خارج الكتالوج (من الكود):** فشل كتابة كتالوج (`_rememberOfferMediaCatalog` غير منتظَر؛ `appendToOfferMediaCatalog` يبتلع الخطأ)، توقف العملية بين كتابة الخريطة وكتابة الكتالوج، تنظيف جزئي سابق لمعرّف أسقطه رد لاحق. ومعها تبقى **مدخلات الكاش القديم** لتلك المفاتيح (بايتات صور الحساب المحذوف) لأن `removeCachedBytes` لا يُستدعى لها. **فرضي لا مؤكَّد:** حجمها الفعلي على الأجهزة (لم يُقَس).
**ثانياً — كتابات متأخرة (مؤكَّدة بنيوياً، نافذة توقيت):** `ensureMediaIdCached` (بطاقات المفضلة/البحث/الخريطة عبر `PrivateCardMedia`، المشاركة، معرض غير-refs) **بلا فحص جلسة**: تنزيل جارٍ عبر `getSingleFile(url, key)` يكمل بعد المنظّف ⇒ يعيد إنشاء مدخل الكاش القديم **و**`mapMediaIdToLocalFile` للمفتاح المحذوف. كذلك `_rememberOfferMediaCatalog` المتأخر (رد Worker في الطريق) ⇒ يعيد إنشاء `offerMediaCatalog::<deletedUid>::…`؛ و`adoptLocalFileForMediaId` المتأخر (ملصق فيديو/رفع) ⇒ أصل جديد في `offer_media/` + خريطة. **محمية بالفعل:** `PrivateMediaImages.load` (كتابة الخريطة في نفس التشغيل المتزامن لفحص `canRead`) و`_switch` في M1d-2 (فحص الأصل قبل CAS)؛ قائمة الرفع (المنظّف يطهّرها أولاً والمهمة تتحقق من `cancelling`).

**3) صيغ المفاتيح وملكيتها (مُتحقَّقة من الكود):**
| المخزن | الصيغة | ملكية مثبتة؟ |
|---|---|---|
| `url_mapping` | `mediaId::offer-media:<uid>:<mediaId>` (أساسي Offer/Owner) | ✔ `uid` = معرّف Supabase المصادَق (UUID، بلا `:`) |
| `url_mapping` | `mediaId::offer-media:<uid>:<mediaId>:poster` | ✔ |
| `url_mapping` | `mediaId::offer-media:<uid>:<mediaId>::previous-copy` (M1d-2) | ✔ نفس المعرّف القانوني |
| `url_mapping` | `mediaId::<profile_media_id>` (avatar، معرّف عارٍ) | ✘ لا حساب في المفتاح (M4) |
| `url_mapping` | `<رابط Firebase>` ⇒ مسار (`mapUrlToLocalFile`، **بلا مستدعين حاليين** — بيانات قديمة فقط) | ✘ |
| `local_media` | `offerMediaCatalog::<uid>::<recordId>` | ✔ (يُحذف اليوم) |
| `local_media` | `<documentId>` (`storeLocalMediaData`، **بلا مستدعين حاليين**) | ✘ |
| الكاش القديم | `offer-media:<uid>:<id>` / مفاتيح روابط / `resized_*` / معرّفات عارية | ✔ للأولى فقط؛ الفهرس **غير قابل للتعداد** (M1d) |
- **لا مشاركة بين حسابين** لأي مفتاح `offer-media:` (الحساب جزء من المفتاح). المعرّفات العارية ومفاتيح الروابط غير مقسّمة ⇒ **لا تُلمس** (لا يمكن إثبات ملكيتها).

**4) هل البيانات الباقية قابلة للوصول؟** **لا عبر التطبيق:** كل القرّاء يبنون المفاتيح من الحساب الحالي فقط (`heldNow` بعد `canRead`، البذرة من `currentOwnerId`، البطاقات من سجلات الحساب المقيّدة بـ RLS) ⇒ مفاتيح الحساب المحذوف لا تُعنوَن من أي حساب آخر؛ القيم **مسارات فقط** (لا روابط ولا رموز)؛ `url_mapping`/`local_media`/`libCachedImageData.db` **مستثناة من النسخ الاحتياطي** (M0.5). **لكن** تبقى على القرص داخل حاوية التطبيق: بيانات وصفية بلا انتهاء (Hive) + بايتات صور في الكاش القديم حتى إخلائه الطبيعي (30 يوماً بلا استخدام / 200 مدخل). التصنيف: **بقايا بيانات للحساب المحذوف (data-remanence)، لا تجاوز وصول.**

**5) التصحيح الأصغر الموصى (لم يُنفَّذ):** كله في `lib/src/services/offline_media_service.dart`:
- **(أ) كنس خرائط بالبادئة الصارمة داخل `forgetOfferMedia(ownerId)` المقيّد فقط:** شرط المالك: غير فارغ بعد trim و**بلا `:`** (يرفض `'::::'` كما يفعل كنس الأصول) — وإلا لا كنس. البادئة الحرفية `mediaId::offer-media:<owner>:` (المحدِّد `:` يمنع `abc` من مطابقة `abcd`). لكل مفتاح مطابق (من **لقطة** `keys.toList()`): اشتقاق مفتاح العنصر بنزع لاحقة `::previous-copy` أو `:poster` فقط؛ إن كان `mediaId` الناتج غير فارغ وبلا `:` و`offerMediaCacheKey(owner, id)` يطابقه ⇒ يُضاف إلى مجموعة المفاتيح نفسها التي يمرّ عليها `_removeArtifactsFor` اليوم (اتحاد مع مفاتيح الكتالوج، بلا تكرار)؛ وإلا (صيغة تالفة تحت البادئة) ⇒ **حذف مدخل الخريطة نفسه فقط**، بلا لمس أي ملف. لا مطابقة جزئية (substring) ولا تعابير عامة.
- **(ب) حارس الكتابات المتأخرة (ذاكرة العملية فقط):** `forgetOfferMedia(ownerId)` يسجّل المالك في `_forgottenOwners` **قبل** الكنس؛ أي كتابة لمفتاح `offer-media:<owner>:` تُرفض ما دام المالك مسجَّلاً **و**ليس `OfferMediaSession.applicationAccount` الحالي: `mapMediaIdToLocalFile`، `replaceMediaIdMapping`، `adoptLocalFileForMediaId` (قبل النسخ إلى `offer_media/`)، `writeOfferMediaCatalog` (ومن ثم append/reconcile)؛ و`ensureMediaIdCached` بعد تنزيل متأخر لمالك محذوف ⇒ لا خريطة + `removeCachedBytes(key)` للمفتاح الدقيق فقط. **لماذا مشروط بـ applicationAccount:** المصالحة قد تستدعي `completeAccountDeletion` حين تكون نتيجة الحذف **غير معروفة** (`sessionEnded`)؛ إن عاد الحساب نفسه حساباً تطبيقياً، يرتفع الحارس تلقائياً بلا خطاف جديد ولا حالة دائمة. لا يحتاج حارساً دائماً: بعد إعادة التشغيل لا كتابات جارية، والحساب المحذوف فعلاً لا يعود.
- **لا تغيير** للمنظّف، Auth، SAD، `AccountDeletionStateStore`، الكاش الخاص، حدود 200/30، سياسة التنزيل (لا تنزيل جديد؛ حذف ما وصل متأخراً لحساب محذوف فقط).

**6) التزامن والانقطاع:** تبديل حساب أثناء الحذف ⇒ الكنس بالمالك المحذوف فقط والحارس لا يمس الحساب الحالي. خروج قبل المنظّف ⇒ هو الترتيب القائم. تنزيل/ترحيل متأخر ⇒ (ب). فشل حذف Hive ⇒ يُحسب في التقرير (`failures`) والباقي يبقى (كاليوم). تكرار ⇒ idempotent (حذف غير الموجود لا يضر). **انقطاع العملية أثناء المنظّف:** علامة `AccountDeletionStateStore` تُمسح **قبل** المنظّف ⇒ لا إعادة محاولة بعد إعادة التشغيل (قائم لكل خطوات التنظيف، Auth-adjacent) — **قرار مالك منفصل** إن أراد سجلاً دائماً «تنظيف معلّق». معرّفات متشابهة ⇒ المحدِّد `:` + رفض `:` في المالك. وسائط الحساب الآخر ⇒ لا تُمس (بادئة مختلفة؛ الحارس للمالك المحذوف فقط).

**7) خطة الاختبار أولاً (ملف جديد `test/offers/offer_media_account_mapping_cleanup_test.dart`):** (1) كتالوج كامل ⇒ كما اليوم؛ (2) كتالوج ناقص ⇒ خرائط المعرّفات غير المذكورة تُزال؛ (3) معرّف معروف برد Worker فقط (خريطة + `OfferMediaUrlCache`) ⇒ يُزال؛ (4) الأساسي + `::previous-copy` + `:poster` معاً؛ (5) خرائط حساب آخر (+ كتالوجه وكاشه الخاص) سليمة بايت-بايت؛ (6) `abc` مقابل `abcd`/`abc-1`، ومالك `'::::'`/فارغ ⇒ لا كنس؛ (7) خروج واستبدال جلسة: الحارس لا يمنع الحساب الحالي، ويرتفع إن عاد الحساب نفسه؛ (8) `ensureMediaIdCached`/`mapMediaIdToLocalFile`/`replaceMediaIdMapping`/`adoptLocalFileForMediaId`/`writeOfferMediaCatalog` المتأخرة بعد الحذف ⇒ مرفوضة، والتنزيل المتأخر يُزال من الكاش القديم بالمفتاح الدقيق؛ (9) التكرار ⇒ نفس الحالة؛ (10) فشل حذف Hive (box مغلق/خطاف) ⇒ تقرير `failures`>0 بلا استثناء؛ (11) مفتاح تالف تحت البادئة ⇒ يُحذف المدخل فقط بلا ملفات؛ (12) معرّفات عارية/مفاتيح روابط/`resized_*`/مدخلات `local_media` القديمة ⇒ لا تُمس؛ (13) بيانات الملف الشخصي والمفضلة والبحث وToolkit وعروض الأسعار ⇒ لا تُمس (عبر `DeletedAccountLocalDataCleaner` الحقيقي مع خدمات وهمية للبقية)؛ (14) لا حذف لبايتات قديمة غير مرتبطة (ملفات `libCachedImageData` لمفاتيح أخرى سليمة). **الطفرات المخططة:** حذف شرط `:` في المالك؛ مطابقة بلا المحدِّد الأخير؛ `contains` بدل `startsWith`؛ عدم نزع اللواحق؛ تجاهل الحارس؛ الحارس بلا شرط applicationAccount؛ حذف ملفات للمفاتيح التالفة؛ تسجيل المالك بعد الكنس. **انحدار مركّز:** `offer_media_security_cleanup_test`، `offer_media_mapping_switch_test`، `offer_media_legacy_migration_test`، `offer_media_private_cache_test`، `offer_media_local_first_test`، `delete_account_test`، `account_deletion_quarantine_test`، `search_card_media_test`، `share_*`.

**8) قرارات للمالك:** **D-DAM-1** الكنس بالبادئة الصارمة للأساسي/الاحتياط/الملصق — **موصى**. **D-DAM-2** حذف مدخل الكاش القديم **بالمفتاح الدقيق** لتلك المعرّفات (نفس دليل الملكية الذي يُستخدم لمفاتيح الكتالوج اليوم) — **موصى**؛ البديل: الخرائط فقط وترك البايتات للإخلاء الطبيعي. **D-DAM-3** حارس الكتابات المتأخرة في الذاكرة مشروطاً بـ applicationAccount — **موصى**. **D-DAM-4** سجل دائم «تنظيف معلّق» لإعادة المحاولة بعد انقطاع العملية — **غير موصى الآن** (Auth-adjacent؛ يمس ترتيب `AccountDeletionStateStore`). **D-DAM-5** نافذة الكتابة المتأخرة في الكاش الخاص (M1b `_fetch` بين آخر فحص جلسة وكتابة المكتبة) — توثيق فقط، أو نفس الحارس في `PrivateMediaCache` بقرار منفصل.

**9) القيود الباقية (حتى بعد التصحيح):** مدخلات الكاش القديم بمفاتيح الحساب **بلا خريطة ولا كتالوج** لا يمكن إيجادها (الفهرس غير قابل للتعداد) ⇒ تبقى حتى الإخلاء الطبيعي؛ المعرّفات العارية للـ avatar السابقة ومفاتيح الروابط ومدخلات `local_media` القديمة غير مقسّمة ⇒ لا تُلمس؛ المسح الشامل الحالي في `forgetProfileMedia()` حين يكون الحساب المحذوف هو المسجَّل يمسح خرائط **كل** الحسابات (قائم، أوسع من اللازم — ملاحظة منفصلة)؛ لا إعادة محاولة بعد انقطاع العملية.

**الملفات المعدّلة في هذه النقطة:** هذا المتتبّع فقط. **لا تغيير كود.**

**المحفوظ (منفصل، لم يُدمج):** قابلية نقل المسارات المطلقة على iOS؛ كشف التلف بنفس الحجم؛ **M1d-3** بعد M3؛ **M1e**؛ **M2**؛ **M3**؛ **M4**؛ **M5**؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار التاريخية؛ Smart Map/Toolkit معلّقان.

**الحالة:** **DA-MAP = AUDIT + DESIGN مكتمل.** **NOW:** قرارات المالك D-DAM-1…5. **STOP:** لا تنفيذ؛ لا commit/push؛ لا M1e/M2/M3.

#### DA-MAP-1 — تنفيذ تنظيف وسائط Delete Account المقيّد بالحساب — 2026-11-09 (CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج)

**قرارات المالك:** **D-DAM-1** ✅ معتمد (كنس البادئة الصارمة)؛ **D-DAM-2** ✅ معتمد (مدخل الكاش القديم بالمفتاح الدقيق)؛ **D-DAM-3** ✅ معتمد (حارس الكتابات المتأخرة)؛ **D-DAM-4** ❌ **غير معتمد** (إعادة محاولة دائمة بعد انقطاع) — **OPEN**؛ **D-DAM-5** متابعة أمنية منفصلة (نافذة الكتابة المتأخرة في `PrivateMediaCache`) — **OPEN**، لا يحلّها هذا التغيير.

**Git (مُتحقَّق بعد fetch):** HEAD `45b275e` = `origin`؛ الفهرس فارغ؛ **ثلاثة** stashes محفوظة كما وُجدت (`stash@{0}` iOS-branch، `stash@{1}`، `stash@{2}`)؛ تصميم DA-MAP غير المودع محفوظ أعلاه.

**ملف الإنتاج الوحيد:** `lib/src/services/offline_media_service.dart`. **الاختبارات:** جديد `test/offers/offer_media_account_mapping_cleanup_test.dart` (19)؛ **تحديث مقصود لمجموعة الاختبار فقط** في `offer_media_security_cleanup_test.dart` و`offer_media_private_cache_test.dart`: سطر `OfflineMediaService.debugForgetDeletedAccounts()` في `setUp` (كل اختبار = تشغيل جديد؛ كانت اختبارات لاحقة تعيد استخدام معرّف حساب «حذفه» اختبار سابق في العملية نفسها — 12 إخفاقاً متوقعاً بدونه، 0 معه).

**التنفيذ:**
- **D-DAM-1/2 — داخل `forgetOfferMedia(ownerId)` المقيّد فقط:** المعرّف يجب أن يكون **UUID قانونياً بأحرف صغيرة** (`^[0-9a-f]{8}-…-[0-9a-f]{12}$`، بلا trim)، وإلا لا كنس إضافي ولا حارس (السلوك السابق كما هو). النطاق الحرفي `mediaId::offer-media:<uid>:` بـ `startsWith` على **لقطة** `keys.toList()`. اشتقاق مفتاح العنصر بنزع لاحقة `::previous-copy` أو `:poster` فقط، ثم `mediaId` غير فارغ، بلا `:`، بلا مسافات طرفية، و`offerMediaCacheKey(uid, id)` يطابقه حرفياً ⇒ يُضاف إلى مجموعة المفاتيح نفسها (اتحاد مع الكتالوج) ⇒ `_removeArtifactsFor` القائم: الأساسي + الاحتياط + خريطة/أصل الملصق (داخل `offer_media/` فقط) + النسخة الخاصة + **مدخل الكاش القديم بالمفتاح الدقيق** + إشعار الذاكرة. مدخل تحت النطاق لا يسمّي عنصراً بدقة ⇒ **يُحذف المدخل وحده**، ولا يُحذف أي ملف بمساره أبداً.
- **D-DAM-3 — حارس في ذاكرة العملية:** يُسجَّل الحساب **قبل أي قراءة** في `forgetOfferMedia` مع معرّف جلسة التطبيق الحالية له (أو null). يُرفض لمفاتيح `offer-media:<uid>:` وكتالوج `<uid>`: `mapMediaIdToLocalFile` (بعد كل انتظار، قبل الكتابة مباشرة)، `replaceMediaIdMapping` (قبل المقارنة)، `writeOfferMediaCatalog` (ومن ثم append/reconcile)، `adoptLocalFileForMediaId` (قبل البدء، قبل النسخ، وبعد النسخ ⇒ يحذف النسخة التي صنعها للتو فقط ويُبقي الملف المختار)، `ensureMediaIdCached` (قبل البحث/التنزيل ⇒ لا شبكة؛ وبعد تنزيل وصل متأخراً ⇒ لا خريطة + `removeCachedBytes` للمفتاح الدقيق). **رفع الحارس:** فقط حين يكون `PrivateMediaCache.applicationScope()` — حساب تطبيقي مُصادَق **وجلسة أجازها فحص Single Active Device** — للحساب نفسه **بمعرّف جلسة مختلف** عن المسجَّل وقت الحذف (تسجيل دخول جديد بعد حذف غير معروف النتيجة). تطابق خاصية الحساب وحدها، أو الجلسة نفسها التي كانت قائمة وقت الحذف، أو حساب آخر، أو حالة خروج ⇒ **لا ترفعه**. لا نظام Auth جديد؛ لا تغيير لـ Auth/SAD/`OfferMediaSession`/المنظّف.

**قبل/بعد:**
| الحالة | قبل | بعد |
|---|---|---|
| خرائط معرّفات خارج الكتالوج (حساب آخر مسجَّل وقت الحذف) | تبقى (أساسي/`:poster`/`::previous-copy`) + مدخل الكاش القديم | **تُزال** + مدخل الكاش القديم بالمفتاح الدقيق |
| مدخل تالف تحت نطاق الحساب | يبقى | يُحذف المدخل فقط، الملف يبقى |
| تنزيل بطاقة/مشاركة جارٍ يكتمل بعد التنظيف | يعيد إنشاء الخريطة ومدخل الكاش القديم | لا خريطة، والمدخل يُزال بالمفتاح الدقيق |
| كتالوج/تبنٍّ/تحويل متأخر | يعيد إنشاء البيانات/الأصل | مرفوض (والنسخة المصنوعة أثناء التنظيف تُحذف) |
| حسابات أخرى، معرّفات قريبة، مفاتيح روابط، معرّفات عارية، `resized_*`، سجلات `local_media` القديمة | لا تُمس | **لا تُمس** (لقطة بايت-بايت) |
| الحذف حين يكون الحساب المحذوف هو المسجَّل | المسح الشامل القائم | كما هو + الكنس الدقيق (بلا تغيير للمسح الشامل) |

**الاختبارات:** الملف الجديد **19/19 ✅**: كتالوج كامل؛ كتالوج ناقص/معرّف من رد Worker فقط؛ الأساسي + `:poster` + `::previous-copy` بلا كتالوج؛ مدخلات تالفة (المدخل فقط، لا ملفات، لا حذف كاش)؛ حساب آخر + معرّف يختلف بحرف أخير + `<uid>0` + UUID بأحرف كبيرة + مفتاح يحوي النطاق في وسطه + معرّف عارٍ + رابط + `resized_*` + `local_media` قديم ⇒ لقطات متطابقة؛ معرّفات غير قانونية (`UPPER`، مسافة، `::::`، فارغ، `owner-x`) ⇒ لا كنس إضافي ولا حارس؛ التكرار؛ فشل إزالة الكاش القديم ⇒ `failures` والخرائط تُزال؛ **خطأ Hive** (box مغلق) ⇒ مُبلَّغ بلا استثناء وإعادة المحاولة تكمل؛ كتابات خريطة/تحويل/كتالوج متأخرة؛ بطاقة بعد الحذف ⇒ 0 تنزيل؛ تنزيل جارٍ أثناء التنظيف؛ كتابة أثناء الكنس؛ تبنٍّ متأخر وجارٍ؛ حساب آخر يكتب طبيعياً والحساب المحذوف يبقى مرفوضاً؛ CAS مرفوض حتى لخريطة دخلت بطريق آخر؛ جلسة جديدة ترفع الحارس، الجلسة القديمة لا، الخروج لا. **انحدار مركّز:** الملف الجديد + security-cleanup + M1c + M1d-1 + M1d-2 **153/153 ✅**؛ **المتأثر الأوسع (42 ملفاً):** **981 ✅ / 2 ✘** = القائمان فقط (`delete_account_test` setUpAll: ملف الترحيل المُعاد تسميته؛ FU-ACCOUNT-UI-BASELINE-1). `flutter analyze` (4 ملفات): لا مشاكل؛ التنسيق 0 تغيير (الملف الجديد فقط نُسّق آلياً، سطر واحد يدوياً)؛ `git diff --check` نظيف؛ CRLF محفوظ.

**الطفرات (استعادة SHA-256 بعد كل طفرة):** **15/16 مقتولة** — G1 قبول معرّف غير قانوني (قُتلت بعد إضافة اختبار مدخلات نطاق غير قانوني)، G2 نطاق بلا الفاصل الأخير، G3 `contains` بدل `startsWith`، G4 عدم نزع اللواحق، G5 حذف ملفات المدخلات التالفة، G6 تسجيل الحارس بعد الكنس، G7 حارس لا يرفض، G8 أي جلسة للحساب ترفعه، G9 جلسة أي حساب ترفعه، G10 عدم إزالة التنزيل المتأخر، G11 بلا فحص قبل التنزيل، G13 كتالوج بلا حارس، G14 CAS بلا حارس، G15 كتابة خريطة بلا حارس، G16 معاملة المدخلات التالفة كعناصر. **ناجية واحدة: G12** (الفحص بعد النسخ في التبنّي) — الفحص السابق للنسخ يلتقط كل ترتيب يمكن إنتاجه حتمياً في اختبار؛ G12 يحرس نافذة نسخ ملف واحد (لا نقطة اختبار فيها) — يبقى دفاعاً.

**حالات تنظيف ناقص باقية:** (1) مدخلات الكاش القديم بمفاتيح الحساب **بلا خريطة ولا كتالوج** — الفهرس غير قابل للتعداد ⇒ حتى الإخلاء الطبيعي (30 يوماً/200)؛ (2) تنزيلات `CachedNetworkImage` المباشرة داخل الودجات (بطاقات المفضلة/البحث بمفتاح ثابت) التي تكتمل بعد الخروج تكتب في الكاش القديم دون المرور بهذه الخدمة — لا تُحرس هنا (الشاشات تُهدم عند الخروج؛ إخلاء طبيعي)؛ (3) معرّفات avatar العارية السابقة ومفاتيح الروابط وسجلات `local_media` القديمة — لا ملكية مثبتة ⇒ لا تُلمس؛ (4) **D-DAM-5:** نافذة M1b بين آخر فحص جلسة وكتابة المكتبة في `PrivateMediaCache` — مفتوحة؛ (5) المسح الشامل الحالي في `forgetProfileMedia()` حين يكون الحساب المحذوف هو المسجَّل (يمسح خرائط كل الحسابات) — **قائم، لم يُوسَّع ولم يُعَد تصميمه**.
**الانقطاع وإعادة المحاولة:** الحارس في الذاكرة فقط (بعد إعادة التشغيل لا عمل جارياً، والحساب المحذوف فعلاً لا يعود). علامة الحذف تُمسح قبل المنظّف ⇒ **لا إعادة محاولة بعد انقطاع العملية** (**D-DAM-4 OPEN**)؛ الكنس idempotent إن شُغّل مجدداً. فشل Hive ⇒ مُبلَّغ في التقرير، الباقي يبقى.
**الأجهزة:** REAL_DEVICE_UNVERIFIED (لم يُشغَّل Delete Account على Samsung/iOS).

**المحفوظ:** قابلية نقل المسارات المطلقة على iOS؛ كشف التلف بنفس الحجم؛ روابط موقّعة قديمة في فهرس الكاش السابق؛ **M1d-3** بعد M3؛ **M1e**؛ **M2**؛ **M3**؛ **M4**؛ **M5**؛ FU-FAV-MEDIA-NO-IDENTITY **OPEN**؛ P4.3-ACCEPT-NONEMPTY **OPEN**؛ D-57 وقبول Samsung/iOS **DEFERRED**؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit معلّقان.

**الحالة:** **DA-MAP-1 = CODE_PROVEN — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** **NOW:** مراجعة المالك النهائية. **STOP:** لا commit/push؛ لا بدء M1e/M2/M3/M1d-3.

### M1e-a — خط أساس أداء كاش الصور الخاص وعدّ الطلبات — 2026-11-09 (MEASUREMENT + AUDIT؛ لا تغيير إنتاجي)

**Git (مُتحقَّق بعد fetch):** الفرع `perf/phase-1-startup-baseline`؛ HEAD `b02039e` = `origin` (دفع DA-MAP-1 مؤكَّد)؛ الفهرس فارغ؛ **ثلاثة** stashes محفوظة كما هي؛ ملفات plugin الثلاثة المُعاد توليدها معدّلة ولم تُلمس.

**أداة القياس (اختبار فقط):** `test/perf/m1e_private_media_baseline_test.dart` — 15 سيناريو بعدّادات صريحة على بدائل محكومة: `_Worker` (موضع التوقيع الوحيد: كل نداء يوقّع **كل** العناصر من جديد كما يفعل الـ Worker)، `_Transport` (تنزيلات بايتات R2 وعددها)، `fetchCachedBytes` (قراءات الكاش القديم)، خطافات النسخ/التحويل، ومصدر كل صورة معروضة (`firstFrame` = `heldNow` متزامن، `privateCopy`، `oldCache`، `download`). الاستدعاء يحاكي الإنتاج كما في الكود: `PrivateMediaImage._start` ⇒ `heldNow` وإلا `load(key, link)`؛ إحماء المعرض `_prefetchInitialMedia`/`_prefetchNearbyMedia` ⇒ `load` للحالي والتاليين حين يوجد رابط؛ العارض ⇒ `_imageProviderFor` للصفحة والصور المصغّرة المرئية (`ListView.builder` أفقي، `ResizeImage` 120). لا خدمة حقيقية، ولا روابط/معرّفات/حسابات في التقارير.

**مسارات الإنتاج المُتتبَّعة (كود):** فتح التفاصيل ⇒ `OfferDetailsLoadCoordinator.load` ⇒ بذرة متزامنة (`cachedOfferMedia` ⇒ `usableLocalPathForMediaId`) + **طلب Worker واحد `/offer-media` في كل فتح** (`_startMedia`) يوقّع كل العناصر، ومعه قراءة البيانات الوصفية إن لم تُحلّ؛ الصورة ⇒ `heldNow` (Hive + `existsSync`) ⇒ الكاش الخاص (`cached`) ⇒ القديم بالمفتاح الدقيق (قراءة فقط) ⇒ تنزيل واحد برابط في اليد؛ بعد إصابة قديمة ⇒ نسخ خلفي (M1d-1) ثم تحويل الخريطة (M1d-2). لا مسار صورة يطلب رابطاً.

| # | السيناريو | Worker (توقيعات) | تنزيلات | مصدر العرض | ملاحظات القياس | التصنيف |
|---|---|---|---|---|---|---|
| A | أول عرض، لا شيء محفوظ (صورة واحدة) | 1 (1) | **1** | download | ≈74 ms VM | MEASURED_ON_TEST_VM |
| B | في الكاش الخاص بلا خريطة | 0 | **0** | privateCopy | بحث خاص ≈1.1–1.3 ms؛ `heldNow` ≈49–64 µs؛ الخريطة تُصلَح ⇒ الإطار التالي متزامن | MEASURED_ON_TEST_VM |
| C/H | إعادة فتح ×3، رابط جديد كل مرة | 3 (3) | **0** | firstFrame | 4 روابط لنفس المعرّف ⇒ تنزيل واحد؛ ≈1.9–2.3 ms/فتح VM | MEASURED_ON_TEST_VM |
| D | معرض Owner (صورتان) | 1 لكل فتح | 2 أول فتح (الصفحة + إحماء)، **0** إعادة | firstFrame | نفس صيغة المفتاح والكتالوج | MEASURED_ON_TEST_VM |
| E | العارض الكامل: فتح ثم إغلاق/فتح ×4 | 0 (يستخدم مراجع التفاصيل) | **3** أول فتح (صور مصغّرة مرئية غير محفوظة)، **0** بعدها | firstFrame | المصغّرات تجلب الصورة الكاملة وتفكّها بعرض 120 | MEASURED_ON_TEST_VM |
| F | 8 صور | 1 (8) لكل فتح | **3** عند الفتح؛ 8 بعد التمرير على الكل؛ **0** إعادة | firstFrame | قرص خاص = مجموع البايتات فقط | MEASURED_ON_TEST_VM |
| F+ | 32 صورة × 64 KiB | 1 (32) لكل فتح | **32** مرة واحدة | — | 2 MiB تنزيل = 2 MiB قرص خاص؛ `heldNow` للـ 32 ≈2.4–2.9 ms VM | MEASURED_ON_TEST_VM |
| G | 5 طلبات متزامنة بـ 5 روابط | — | **1** | — | 0 تكرار | MEASURED_ON_TEST_VM |
| I/J | فتح offline / Worker غير متاح، مع كتالوج وخريطة | 1 محاولة فاشلة | **0** | firstFrame | البذرة الحقيقية تعطي 3/3 محلياً في ≈1.5–1.7 ms VM | MEASURED_ON_TEST_VM |
| K | إعادة تشغيل بنسخة خاصة صالحة | 1 | **0** | firstFrame | 0 قراءات للكاش القديم؛ `heldNow` ≈0.18 ms | MEASURED_ON_TEST_VM |
| M/N | نسخة قديمة: عرض + نسخ + تحويل | 0 | **0** | oldCache | عرض ≈3.5–3.8 ms؛ النسخ والتحويل في الخلفية ≈86–90 ms (200 KiB)؛ ازدواج قرص 200 KiB حتى M1d-3 | MEASURED_ON_TEST_VM |
| L | إخلاء النسخة الخاصة والقديم موجود | 0 | **0** | firstFrame (الاحتياط) | **إعادة النسخ لا تحدث بعرض الاحتياط وحده** (الودجة لا تستدعي `load`)؛ تحدث في أول فتح online (الإحماء برابط) ⇒ نسخة + تحويل | MEASURED_ON_TEST_VM |
| O | نسخة تالفة (الطول تغيّر) | — | بلا رابط **0** (لا شيء)؛ برابط **1** | none / download | التالف بنفس الحجم لا يُكتشف (قيد قائم) | MEASURED_ON_TEST_VM |
| P | استبدال الجلسة أثناء التنزيل | — | 1 (بايتات مهدرة) | — | 0 نشر، لا خريطة | MEASURED_ON_TEST_VM |
| Q | Delete Account أثناء تنزيل جارٍ | — | 1 (مهدر) | — | لا خريطة؛ كتابة متأخرة مرفوضة (DA-MAP-1) | MEASURED_ON_TEST_VM |
| R | صور بلا هوية ثابتة (معرض Owner Firebase `mediaUrls`، مرفقات المخطط، بدائل المفضلة/البحث بمفتاح الرابط) | — | **رابط جديد ⇒ مفتاح جديد ⇒ تنزيل جديد** | — | لم يُغيَّر (تعليمات)؛ من التدقيقات السابقة | CODE_VERIFIED / NOT_TESTED |

**فك الترميز (VM فقط):** PNG ‏1600×1200: كامل ≈19–26 ms و**7.68 MB** مفكوك؛ رأس المعرض بعرض 1080 ≈27–30 ms و**3.5 MB**؛ مصغّر 120 ≈16 ms و**43 KB**. صفحة العارض الكامل تفك بالدقة الكاملة (تكبير PhotoView) — متوقَّع. **مفاتيح ذاكرة الصور:** ملف محفوظ ⇒ `FileImage` بالمسار (إعادة الفتح تصيب ImageCache)؛ عنصر غير محفوظ بعد ⇒ `PrivateMediaImageProvider(مفتاح + رابط)` ⇒ رابط جديد = فك جديد (لا تنزيل) حتى تُكتب الخريطة.

**مقارنة قبل/بعد (فقط ما هو مُثبت):** قبل M1c (قراءة كود مُوثَّقة في مراجعة M1c أعلاه): ملف مُخطَّط ⇒ بلا تنزيل؛ وإلا `CachedNetworkImage(signedUrl, cacheKey)` على `DefaultCacheManager` ⇒ إصابة بالمفتاح، **لكن كل تنزيل يكتب الرابط الموقّع في `libCachedImageData.db`** و**بعد 7 أيام (`validTill`) إعادة تنزيل في كل عرض**؛ والإحماء ينزّل في الكاش القديم المشترك. بعد M1b–M1d-2: **0 روابط محفوظة**، صلاحية 365 يوماً بلا إعادة تحقق، نسخة محفوظة تُعرض بلا رابط، عزل حساب/جلسة، والقديم يُرحَّل بلا شبكة. **عدد تنزيلات أول عرض/إعادة الفتح قبل M1c: CODE_VERIFIED من القراءة، غير مُقاس**؛ **أزمنة ما قبل M1c: UNVERIFIED** (لم يُشغَّل كود قديم — لا worktree، لا مساس بالشجرة أو الـ stashes).

**الاختناقات الباقية حسب الأثر المُقاس:**
1. **طلب Worker واحد في كل فتح تفاصيل** يوقّع كل العناصر (8 توقيعات لمعرض من 8) حتى حين تكون كل الصور محلية — **مقصود** (القائمة المرجعية + إشارة السحب/الإزالة الوحيدة)، ولا يحجب الإطار الأول (البذرة تعرض محلياً أولاً). تغييره قرار حداثة/أمان، لا تحسين أداء.
2. **R — مسارات بلا هوية ثابتة** تعيد التنزيل مع كل رابط جديد — أكبر هدر شبكة متبقٍّ، لكنه نطاق **M3/FU-FAV-MEDIA-NO-IDENTITY** وقد استُبعد هنا.
3. **مصغّرات العارض** تجلب صوراً كاملة غير محفوظة (3 تنزيلات إضافية في معرض 8 عند أول فتح للعارض) — كانت ستُنزَّل عند التمرير أصلاً؛ لا نسخة مصغّرة على الخادم.
4. **الإحماء** ينزّل الحالي والتاليين (3) عند الفتح — مقصود.
5. **بعد الإخلاء** لا يُعاد النسخ إلا في فتح online تالٍ — آمن (الاحتياط يعرض)، أثر ضئيل.
6. **بايتات مهدرة** عند استبدال الجلسة/الحذف أثناء التنزيل (تنزيل واحد) — متأصل في الأمان.
7. ازدواج القرص للصور المرحّلة حتى M1d-3؛ فك الصفحة الكاملة بالدقة الكاملة في العارض.
- **لا تنزيلات مكررة** في أي سيناريو؛ **لا طلبات توقيع من مسار الصورة**؛ **لا مسار حي في تفاصيل Offers/Owners يخزّن تحت رابط متغيّر** (المتبقي في R فقط).

**التحقق من الصحة (لا عيوب):** حساب آخر لا يرى النسخة (اختبار)؛ جلسة مُزاحة لا تنشر (P)؛ التالف بطول مختلف لا يُعرض صالحاً (O)؛ فشل الترحيل لا يمس القديم (اختبارات M1d-1)؛ الإخلاء ⇒ احتياط موثَّق (L)؛ ترتيب المعرض والعارض دون تغيير (اختبارات M1c)؛ حراس DA-MAP-1 سليمة (Q). **202/202 ✅** (الأداة + M1b/M1c/M1d-1/M1d-2/DA-MAP-1/security-cleanup). `flutter analyze` على الأداة: لا مشاكل؛ التنسيق 0 تغيير؛ `git diff --check` نظيف.

**غير مُقاس (UNKNOWN / PENDING على الجهاز):** أزمنة الإطار الأول والفك على Samsung/iOS؛ ذاكرة العملية الفعلية (RSS)؛ توقيت SQLite لفهرس الكاش؛ مسح النظام لـ temp؛ زمن ذهاب وإياب الـ Worker وR2 الحقيقي وبايتات الصور الحقيقية؛ مسارات iOS المطلقة بعد تحديث؛ استهلاك البطارية/البيانات.

**خطة القبول على الجهاز (M1e — جلسة D-57 الموحّدة):** (1) أول فتح وإعادة فتح Offer بـ 8 صور: زمن أول صورة وعدد طلبات R2 (سجلات Worker/R2 أو proxy)؛ (2) فتح offline بارد بعد إعادة تشغيل؛ (3) فتح العارض وإغلاقه ×5؛ (4) صورة من الكاش القديم ⇒ النسخ والتحويل؛ (5) إخلاء/مسح temp ثم فتح offline؛ (6) Delete Account أثناء تحميل؛ (7) ذاكرة عند تمرير 32 صورة. نتائج ⇒ هذا القسم.

**التوصية:** **المتابعة إلى M2 مباشرة؛ لا M1e-b الآن.** القياسات لا تُظهر تكراراً أو هدراً قابلاً للإصلاح داخل نطاق المسار الخاص؛ الكلفة الأكبر (R) تخص M3، وطلب Worker لكل فتح قرار تصميم. **مرشحات M1e-b اختيارية (غير مبدوءة، تحتاج موافقة):** (أ) تأجيل جلب المصغّرات غير المحفوظة في العارض حتى تقترب؛ (ب) إعادة النسخ عند عرض الاحتياط بلا انتظار فتح online؛ (ج) تخطي طلب Worker عند إعادة فتح قريبة — **يحتاج قرار أمان/حداثة**، غير موصى قبل بيانات الجهاز.

**الملفات المعدّلة:** `test/perf/m1e_private_media_baseline_test.dart` (جديد، اختبار فقط) + هذا المتتبّع. **لا تغيير إنتاجي.**

**المحفوظ (OPEN):** D-DAM-4؛ D-DAM-5؛ تنزيلات `CachedNetworkImage` المباشرة خارج الخدمة؛ مدخلات قديمة بملكية غير مثبتة؛ مسارات iOS المطلقة؛ كشف التلف بنفس الحجم؛ **M2**؛ **M3**؛ **M1d-3** بعد M3 فقط؛ **M4**؛ **M5**؛ P4.3-ACCEPT-NONEMPTY؛ D-57 وقبول Samsung/iOS؛ إخفاقات Auth/Delete Account/Combine التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit offline.

**الحالة:** **M1e-a = MEASURED_ON_TEST_VM (عدّ الطلبات CODE_VERIFIED بالاختبار) — REAL_DEVICE_UNVERIFIED.** **NOW:** موافقة المالك. **STOP:** لا M1e-b/M2/M3/M1d-3.

### M2a — تصميم هوية وسائط Offers/Owners offline من القوائم المشفّرة — 2026-11-09 (AUDIT + DESIGN؛ SOURCE-READ؛ لا تغيير كود)

**Git (مُتحقَّق بعد fetch):** HEAD `4595449` = `origin` (دفع M1e-a مؤكَّد)؛ الفهرس فارغ؛ **ثلاثة** stashes محفوظة؛ ملفات plugin الثلاثة المُعاد توليدها معدّلة ولم تُلمس.

**تمييز مُلزِم:** **الهوية offline** = معرّف `media_objects.id` معروف للسجل بلا شبكة ⇒ يمكن **إيجاد** بايتات نزلت سابقاً (`offer-media:<uid>:<id>` في الكاش الخاص/الخريطة/الاحتياط/القديم). **البايتات offline** = ملف موجود على الجهاز. M2 يوفّر الأولى فقط؛ **لا يُنزّل أي صورة**؛ سجل لم تنزل صوره قط يبقى بلا صورة offline.

**1) المسار المُتتبَّع (كود):**
- **القوائم:** `getOffers()` ⇒ `_fetchOffers` ⇒ `_wholeList('offers', _offerColumns)` ⇒ `_pagedRows` (P4: صفحات 500 بمؤشر `created_at,id` تنازلي، `count(exact)` في الصفحة الأولى، جمع كامل أو فشل، ≤ 40 صفحة/20,000 صف، فحص الحساب+الجلسة بين الصفحات). `_offerColumns` يدمج اليوم `offer_areas(area, ordinal)`. Owners: `_wholeList('owners', '*')`. نفس الأعمدة تُستخدم في `getOfferMetadata` و`_rowsByIds` (المفضلة/البحث).
- **الصفوف بلا وسائط:** `_offerFromRow` ⇒ `mediaObjectIds` فارغ؛ `OwnerModel` **بلا حقل `mediaObjectIds` أصلاً**؛ `OffersLocalCache`/`OwnersLocalCache` تحذف الوسائط عمداً (اختبار P2.2 «لا وسائط»).
- **الكاش المشفّر:** D-3 v2 — قيمة `<entity>_v2` = `{"v":2,"p":<JSON القائمة>,"t":HMAC-SHA256}` داخل صندوق Hive AES لكل حساب؛ تُكتب **فقط** من قائمة خادم كاملة ناجحة للحساب النشط؛ لا توقيع محلي لـ v1؛ علامات الحذف (P3.1d) تمنع حفظ سجلات محذوفة؛ `_decode` يقرأ الحقول بالاسم ويتجاهل غير المعروف.
- **مصادر الهوية اليوم:** كتالوج الجهاز `offerMediaCatalog::<uid>::<record>` (يكتبه رد الـ Worker أو رفع قبله الخادم) ⇒ البذرة `_cachedRecordMedia` ⇒ `usableLocalPathForMediaId`. **المستهلكون:** بذرة التفاصيل؛ بطاقات البحث (`cached` ثم **Worker لكل بطاقة**)؛ المفضلة (`getOffersByIds` ⇒ **Worker لكل مفضلة** لوسائط العرض؛ كاشها المشفّر يحفظ **مفتاح بطاقة ثابت** واحداً، لا رابطاً)؛ الخريطة (`PrivateCardMedia`).
- **تعريف «الوسائط الحالية» في الـ Worker** (`handleMediaList`): صفوف `offer_media`/`owner_media` للأصل، `ordinal` تصاعدياً، الكائن `status = 'ready'`، نوع محتوى مسموح، `bucket` والمفتاح المتوقع `profiles/<uid>/…/<parent>/<id>.<ext>` — بعد `assertOwnsParent`.

**2) هل يمكن الحصول على معرّفات موثوقة ضمن القراءات المصرّح بها الحالية؟ نعم — بلا طلبات إضافية وبلا تغيير SQL/RLS/Worker.**
- `offer_media(offer_id → offers, media_id → media_objects)` و`owner_media(owner_record_id → owners, …)` جداول ربط بمفاتيح أجنبية ⇒ يمكن **تضمينها** (PostgREST embed) في الاستعلام المُقسَّم نفسه كما يُضمَّن `offer_areas`.
- **RLS قائم:** `offer_media_select_own` (`owns_offer`)، `owner_media_select_own` (`owns_owner_record`)، `media_objects_select_own` (`owner_id = auth.uid()`)، و`grant select … to authenticated`؛ **وسياسة `app_session_gate` المقيِّدة (Single Active Device)** تشمل `media_objects` و`offer_media` و`owner_media` (`20261005175500`). ⇒ المعرّفات تأتي من الجلسة نفسها، للحساب نفسه، تحت بوابة SAD نفسها، ولا يمكن أن تشير لحساب آخر.
- **ما يُعكس من مرشحات الـ Worker على العميل:** ترتيب `ordinal`، `status = 'ready'` (`!inner` + مرشح مضمَّن)، معرّف UUID قانوني. **ما لا يُعكس (عمداً):** فحص `bucket`/نمط المفتاح (إعداد خادم) — الفرق: عنصر قد يخفيه الـ Worker يمكن أن يُدرج offline **فقط إن كانت بايتاته نزلت سابقاً بإذن**؛ لا يمنح وصولاً. **لا معرّف يُستنتج من رابط موقّع أبداً.**

**3) البدائل:**
| | المصدر | طلبات إضافية | الحكم |
|---|---|---|---|
| **A (موصى)** | تضمين الربط في قراءات القائمة/المعرّفات/البيانات الوصفية القائمة | **0** | نفس الجلسة وRLS وSAD والاكتمال P4 |
| B | قراءة ربط مجمّعة منفصلة لكل صفحة (`offer_media?offer_id=in.(…)`) | +1 لكل صفحة (≤ 40) | أبطأ، نافذة اتساق ثانية بين طلبين |
| C | كتابة كتالوج الجهاز من القوائم | 0 | **مرفوض:** Hive نصي لـ 20,000 سجل وتقلّب كتابة، وسباق مع رفع يكتمل أثناء القراءة (لقطة القائمة ليست لقطة قاعدة واحدة — P4) قد يُسقط عنصراً جديداً |

**4) القرارات المقترحة (للمالك):**
- **D-M2-1 — المصدر:** الخيار A في `_offerColumns` (فيشمل القوائم و`getOfferMetadata` و`_rowsByIds`) وفي اختيار Owners (`*` ⇒ `*, owner_media(…)`). شكل مقترح للتحقق على staging: `offer_media(media_id, ordinal, media_objects!inner())` مع مرشح `offer_media.media_objects.status=eq.ready` وترتيب `offer_media.order=ordinal.asc` — **الصياغة الدقيقة وسلوك `max_rows` مع التضمين UNVERIFIED** ⇒ تحقق قراءة-فقط على staging بيد المالك قبل الدمج.
- **D-M2-2 — التخزين:** حقل اختياري `mediaObjectIds` (معرّفات مرتبة فقط — لا روابط، لا أنواع، لا بايتات) داخل سجلات `OffersLocalCache` و`OwnersLocalCache` ضمن حمولة v2 المُصادَقة. **القراءة:** غائب ⇒ `[]` (سجلات قديمة)؛ أي عنصر ليس UUID قانونياً ⇒ `[]` لذلك السجل فقط (فئة debug ثابتة) — القائمة تبقى مقروءة (الهوية لا تمنح شيئاً، فلا داعي لإسقاط القائمة كلها). اختبار P2.2 «لا وسائط» يُحدَّث عمداً: **المعرّفات مسموحة، الروابط/البايتات ممنوعة**.
- **D-M2-3 — أسبقية البذرة بلا كتابة كتالوج:** البذرة تستخدم كتالوج الجهاز (رد Worker لكل سجل) **أو** معرّفات سجل القائمة — **الأحدث يفوز** (`updatedAt` للكتالوج مقابل وقت لقطة القائمة من سجل المزامنة P2.5c)؛ التعادل ⇒ الكتالوج. **القوائم لا تكتب الكتالوج ولا تزيل أي أثر أبداً**؛ سلطة الإزالة تبقى للـ Worker (reconcile/accessDenied) وDelete Account (DA-MAP-1). كل عنصر يُعرض فقط إن وُجد ملفه (`usableLocalPathForMediaId`) وبعد بوابة الجلسة (`canRead`/`currentOwnerId`).
- **D-M2-4 — بلا رفع إصدار للكاش:** إضافة حقل داخل حمولة v2 (الوسم يغطيه)؛ لا `_v3`، لا ترحيل، لا حذف. **التراجع:** بناء أقدم يتجاهل الحقل (القراءة بالاسم)، وأول كتابة له تُسقطه — لا فقدان بيانات أخرى.
- **D-M2-5 — `OwnerModel.mediaObjectIds`** (حقل جديد بقيمة افتراضية `[]`) + `_ownerFromRow`.
- **D-M2-6 — المفضلة/البحث/الخريطة:** إعادة الاستخدام (مفاتيح البطاقات من المعرّفات بدل Worker لكل بطاقة حين تكون البايتات محفوظة) = **M3**، لا M2.

**5) التوافق والتحديث والقِدم:**
- **سجلات قديمة بلا معرّفات** ⇒ `[]` ⇒ سلوك اليوم (الكتالوج أو لا شيء) حتى أول قائمة خادم ناجحة.
- **استبدال صورة** ⇒ معرّف جديد (عدم القابلية للتغيير، M1b) ⇒ القائمة التالية تحمله. **حذف صورة** ⇒ القائمة الكاملة التالية لا تحمله؛ بايتاتها تبقى حتى reconcile الـ Worker عند فتح التفاصيل أو M1d-3 (كاليوم). **تحديث السجل** ⇒ المعرّفات تُستبدل مع السجل كاملاً (كل-أو-لا-شيء). **علامات الحذف** تمنع عودة سجل محذوف ومعه معرّفاته.
- **القِدم offline:** صورة أُزيلت على الخادم بعد آخر مزامنة وبايتاتها ما زالت محلية قد تُعرض offline — **نفس دلالة الكتالوج اليوم** (محتوى سبق التصريح به)؛ السحب `accessDenied` يزيل الآثار فلا تُعرض.
- **ليست إذناً:** الهوية المخزّنة لا تتجاوز بوابة الجلسة ولا تطلب روابط؛ الروابط الجديدة تبقى من الـ Worker فقط.
- **الإقلاع البارد offline:** بوابة الجلسة P1 كما هي (البذرة لا تعمل قبلها).

**6) الأداء (تقديرات مؤسَّسة؛ لا قياس جهاز):**
- **معرّفات لكل سجل:** حد أقصى **10** (`MAX_MEDIA_PER_OFFER/OWNER` في الـ Worker)؛ **المتوسط الحقيقي UNKNOWN** (استعلام عدّ قراءة-فقط على المضيف بيد المالك عند الحاجة). الحسابات بـ n=3 (نموذجي مفترض) وn=10 (أقصى).
- **الكاش المشفّر:** لكل سجل `19 + 39·n` بايت (`"mediaObjectIds":[…]`، UUID بعلامتي اقتباس وفاصلة) ⇒ n=3: **136 B**؛ n=10: **409 B**؛ مقابل سجل Offer ≈ 600 B (تقدير من قياس D-3: 2,000 Request ≈ 1.05 MB) ⇒ **+23% / +68%**.

| السجلات | كاش n=3 | كاش n=10 | سلك (مزامنة كاملة) n=3 | سلك n=10 | فك+تحقق إضافي (desktop JIT، تقدير) n=3 / n=10 |
|---|---|---|---|---|---|
| 500 | +68 KB | +205 KB | +77 KB | +255 KB | +14 ms / +43 ms |
| 1,000 | +136 KB | +409 KB | +153 KB | +510 KB | +29 ms / +86 ms |
| 5,000 | +680 KB | +2.0 MB | +765 KB | +2.5 MB | +143 ms / +430 ms |
| 20,000 | +2.7 MB | +8.2 MB | +3.1 MB | +10.2 MB | +570 ms / +1.7 s |
- السلك ≈ 51 B لكل رابط (`{"media_id":"<uuid>"}` مع تضمين ترشيح فارغ) — بلا ضغط؛ UUID لا تنضغط جيداً. الفك/HMAC بنسبة ≈ 0.21 ms/KB من D-3 (217 ms لـ 1.05 MB على desktop). **الجهاز أبطأ — UNVERIFIED.** كلفة القاعدة: ربط لكل صف بفهارس المفاتيح الأساسية + سياسة `owns_offer` لكل رابط + بوابة SAD مرة لكل جملة (`(select …)`) — UNVERIFIED على المضيف.
- **طلبات إضافية:** **0** (نفس الصفحات). **Worker:** بلا تغيير (طلب لكل فتح تفاصيل كما قيس في M1e-a).
- **الإطار الأول:** لكل سجل في القائمة المحفوظة تصبح الهوية متاحة متزامنة ⇒ البذرة تعرض ما بايتاته محفوظة **حتى بلا كتالوج** (الحالة التي وثّقتها مراجعة M1c B: «بلا كتالوج للسجل لا هوية offline»). القيمة الفعلية على الأجهزة تعتمد على كم سجلاً بايتاته محفوظة بلا كتالوج — **UNKNOWN**.
- **إعادة الاستخدام لاحقاً (M3):** بطاقات البحث/المفضلة يمكنها بناء مفاتيح ثابتة من المعرّفات دون Worker لكل بطاقة حين البايتات محفوظة (تقليل N+1) — بلا عمل مكرر لأن المصدر واحد (`_offerColumns`).

**7) الملفات المرجّحة (عند الموافقة):** `lib/src/services/supabase_core_entities_service.dart` (`_offerColumns`، اختيار Owners، `_offerFromRow`، `_ownerFromRow`، `_cachedRecordMedia` بالأسبقية)؛ `lib/src/data/models/ScreensModel/owners_model.dart` (`mediaObjectIds`)؛ `lib/src/services/offers_local_cache.dart` و`owners_local_cache.dart` (ترميز/فك الحقل)؛ `lib/src/views/Screens/ViewDetails/offer_details_load_coordinator.dart` + مسار تفاصيل Owner (تمرير معرّفات السجل/وقت اللقطة إلى البذرة) — أو فهرس داخل الخدمة مقيّد بالحساب، يُحسم في التنفيذ؛ اختبارات جديدة. **بلا تغيير:** `encrypted_account_list_cache.dart` (الصيغة/HMAC/الكتابة)، SQL/RLS، الـ Worker، Auth/SAD، الكاش الخاص، المفضلة/البحث (M3).

**8) خطة الاختبار أولاً:** (1) صف قائمة بروابط ربط ⇒ معرّفات `ready` فقط بترتيب `ordinal`، والمعلّقة/المحذوفة/غير UUID تُستبعد؛ (2) Owner مثل Offer؛ (3) **صفر طلبات إضافية** (عدّاد طلبات PostgREST الوهمي) و`count` والاكتمال P4 دون تغيير، وصفحة تتغير أثناء القراءة كما اليوم؛ (4) الحفظ المشفّر: المعرّفات داخل v2 والوسم يغطيها؛ تعديلها ⇒ رفض القائمة (D-3)؛ **لا رابط ولا نوع ولا بايتات** في الحمولة؛ (5) سجلات v2 قديمة بلا الحقل ⇒ `[]`؛ عنصر غير قانوني ⇒ `[]` لسجله فقط والقائمة مقروءة؛ (6) بناء أقدم (فك بلا الحقل) يقرأ الحمولة الجديدة — توافق التراجع؛ (7) البذرة offline بلا كتالوج تعرض العنصر ذا البايتات المحفوظة، ولا تعرض ما لا ملف له، ولا شيء لحساب آخر أو بلا جلسة؛ (8) الأسبقية: كتالوج أحدث يغلب قائمة أقدم والعكس، والتعادل للكتالوج؛ (9) القوائم لا تكتب الكتالوج ولا تحذف آثاراً؛ (10) علامة حذف تمنع حفظ سجل ومعرّفاته؛ (11) `accessDenied` يمنع العرض رغم بقاء المعرّفات في القائمة؛ (12) Delete Account يحذف الصندوق (كاليوم) والحارس DA-MAP-1 يبقى؛ (13) الأداء: حجم الحمولة وزمن الفك لـ 500/1,000/5,000/20,000 سجل (VM فقط). **طفرات مخططة:** قبول `pending`، إسقاط الترتيب، تخزين الروابط، فك غير متسامح يُسقط القائمة، القائمة تكتب الكتالوج، الأسبقية معكوسة، بلا فحص UUID. **تحقق staging (بيد المالك، قراءة فقط):** صياغة التضمين والمرشح والترتيب وسلوك `max_rows`.

**9) حدود التراجع:** إضافية فقط — لا حذف، لا ترحيل، لا تغيير مفاتيح؛ التراجع الكودي يعيد السلوك السابق فوراً (الحقل يُتجاهل ثم يُسقط عند أول كتابة). تكبير الحمولة يبقى حتى ذلك الحين.

**10) ترتيب التنفيذ الموصى:** **M2-1** القراءة والتضمين والنماذج (بلا حفظ) + تحقق staging؛ **M2-2** الحفظ المشفّر وتسامح الفك؛ **M2-3** أسبقية البذرة والاكتشاف offline؛ ثم **M3** (المفضلة/البحث/الخريطة). كل مرحلة بموافقة منفصلة.

**الملفات المعدّلة في هذه النقطة:** هذا المتتبّع فقط. **لا تغيير كود.**

**المحفوظ (OPEN):** **M3**؛ **M1d-3** بعد M3 فقط؛ **M4**/**M5**؛ مسارات iOS المطلقة؛ كشف التلف بنفس الحجم؛ D-DAM-4/D-DAM-5؛ تنزيلات `CachedNetworkImage` المباشرة؛ مدخلات قديمة بملكية غير مثبتة؛ FU-FAV-MEDIA-NO-IDENTITY؛ P4.3-ACCEPT-NONEMPTY؛ D-57 وقبول Samsung/iOS؛ إخفاقات Auth/Delete Account/Combine التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit.

**الحالة:** **M2a = AUDIT + DESIGN مكتمل.** **NOW:** قرارات المالك D-M2-1…6 وتحقق staging. **STOP:** لا تنفيذ M2؛ لا commit/push.

#### M2-1 — معرّفات وسائط Offers/Owners الموثوقة في قراءات القوائم القائمة — 2026-11-09 (CODE_PROVEN — HOSTED_UNVERIFIED؛ غير مدمج)

**قرارات المالك:** D-M2-1…D-M2-6 **معتمدة** بتنفيذ مرحلي؛ هذه النقطة = **M2-1 فقط** (القراءة والنموذج؛ لا حفظ ولا عرض).

**Git (مُتحقَّق بعد fetch):** HEAD `4595449` = `origin`؛ الفهرس فارغ؛ **ثلاثة** stashes (`stash@{0}` iOS-branch، `stash@{1}`، `stash@{2}`) محفوظة؛ تصميم M2a غير المودع محفوظ؛ ملفات plugin الثلاثة لم تُلمس.

**عقد الاستعلام (Phase 1):**
- **العميل:** `postgrest` 2.9.1 (عبر `supabase_flutter`)؛ `.select(columns)` يمرّر النص (بعد حذف المسافات) كما هو.
- **الشكل المعتمد — تضمين عادي (left join) بلا مرشحات مضمّنة وبلا `!inner`:** Offers: `…, offer_areas(area,ordinal), offer_media(media_id,ordinal,media_objects(status,content_type))`؛ Owners: `*, owner_media(media_id,ordinal,media_objects(status,content_type))`. **تغيير عن مسودة M2a عمداً:** لا `media_objects!inner()` ولا مرشح/ترتيب مضمَّن — تُطبّق شروط الـ Worker على العميل (أدناه)، فلا يعتمد الصواب على دلالات المرشحات المضمّنة في نسخة PostgREST المستضافة، ولا يمكن إسقاط صف أب. الكلفة: حقلا `status` و`content_type` لكل رابط.
- **النطاق:** `_offerColumns` (القائمة + `_rowsByIds`) و`getOfferMetadata` (صار يستخدم `_offerColumns` نفسه — يحفظ ثابت P4 «أعمدة القائمة = أعمدة القراءة المفردة»)؛ `_ownerColumns` للقائمة و`getOwner` و`getOwnersByIds`. **دون تغيير:** `getRelatedOffers` (عرض Related Items)، كل الكتابات.
- **قواعد الهوية على العميل (`_readyMediaIds`، مرآة `handleMediaList`):** فقط `media_objects.status == 'ready'`؛ نوع محتوى ضمن ما **يسرده** الـ Worker (`image/jpeg|png|webp|heic`، `video/mp4|quicktime|3gpp` — HEIC مسرود وإن لم يعد يُرفع)؛ `media_id` UUID قانوني بأحرف صغيرة؛ `ordinal` عدد صحيح ≥ 0؛ كل معرّف مرة واحدة؛ ترتيب `ordinal` ثم المعرّف. أي رابط مشوّه/ناقص/`media_objects` null ⇒ يُستبعد. روابط جدول أب آخر تُتجاهل. **لا يُعكس:** فحص `bucket`/نمط المفتاح (إعداد خادم؛ موثَّق في M2a). **لا قطع عند 10:** الحد يفرضه الخادم (`confirm_*_media_upload`).
- **الحقل:** `listedMediaObjectIds` (جديد، `[]` افتراضياً، يحفظه `copyWith`) في `OfferModel` و`OwnerModel`. **تنقيح تسمية عن D-M2-5:** `OfferModel.mediaObjectIds` **موجود** بمعنى «معرّفات مُحاذية لروابط الـ Worker الموقّعة» ويقرؤه نموذج التعديل (`_initialOfferMedia` يبني عناصر لكل معرّف) وبطاقة المفضلة والمنسّق — وضع معرّفات القائمة فيه **كان سيغيّر عرض نموذج التعديل** ⇒ حقل منفصل للهوية فقط، وبالاسم نفسه في Owners للتناظر. `mediaObjectIds`/`mediaUrls` لصفوف القوائم تبقى فارغة (اختبار + طفرة K12).

**الأدلة على القاعدة (PGlite — PostgreSQL 17.5 بالترحيلات الحقيقية الـ 19 كلها؛ **ليس Supabase ولا PostgREST ولا المضيف**؛ 15/15):** رفض الـ trigger لرابط عبر حسابين؛ العدّ الدقيق يعدّ الآباء فقط (المحذوف مستبعد)؛ كل الآباء تعود بما فيها بلا وسائط (`[]`)؛ 10 روابط تعود؛ رابط غير جاهز يعود (فالعميل يرشّح)؛ `created_at` متساوٍ مفصول بالمعرّف؛ حساب آخر لا يرى؛ **جلسة مُزاحة (SAD) لا ترى آباء ولا روابط ولا `media_objects`** (`app_session_gate` على الجداول الثلاثة)؛ Owners مثل Offers؛ لا `object_key`/`bucket`؛ **وتضمين inner كان سيُسقط الأب بلا وسائط** (سبب رفض `!inner`). نُفّذ الاستعلام بشكل SQL الذي يبنيه PostgREST للتضمين العادي (lateral + `json_agg`) بدور `authenticated` ومطالبات JWT.

**التحقق المستضاف: لم يُنفَّذ (HOSTED_UNVERIFIED).** لا جلسة حساب اختبار مُصرَّح بها في هذه النقطة؛ لم يُستخدم service_role ولا SQL مميّز ولا أي كتابة؛ ولم يُعتبر 401 مجهول دليلاً. **فحص مقترح بيد المالك (قراءة فقط، حساب الاختبار A على staging):** قراءة قائمة Offers مرة بالتطبيق أو REST بالـ `select` أعلاه + `Prefer: count=exact` ⇒ (1) لا 400 (`PGRST200`)؛ (2) العدد = عدد العروض؛ (3) سجل بلا وسائط موجود بـ `[]`؛ (4) معرّفات سجل واحد = `mediaObjectId`s رد `GET /offer-media?offerId=…` بالترتيب؛ (5) سلوك `max_rows` مع التضمين (المتوقع: يحدّ الصفوف العليا فقط).

**الأداء (MEASURED_ON_TEST_VM — خادم PostgREST مُحاكى؛ بلا ضغط؛ ليس الجهاز):**
| القائمة | السجلات | روابط/سجل | الطلبات (قبل = بعد) | الحمولة قبل ⇒ بعد | زيادة/سجل | زمن القراءة VM |
|---|---|---|---|---|---|---|
| Offers | 500 | 3 | 1 | 319 KB ⇒ 518 KB | **397 B** | 62 ms |
| Offers | 1,000 | 3 | 2 | 639 KB ⇒ 1.04 MB | 397 B | 141 ms |
| Offers | 5,000 | 3 / 10 | 10 | 3.2 MB ⇒ 5.2 / 9.6 MB | 397 / **1,286 B** | 746 / 1,284 ms |
| Offers | 20,000 | 3 | 40 | 12.9 MB ⇒ 20.8 MB | 397 B | 3,071 ms |
| Owners | 500 / 1,000 / 5,000 / 20,000 | 3 | 1 / 2 / 10 / 40 | +199 KB / +397 KB / +2.0 MB / +7.9 MB | 397 B | 33 / 80 / 446 / 2,873 ms |
- **≈ 130 B لكل رابط** (أكبر من تقدير M2a ≈ 51 B لأن الحالة والنوع يُختاران للترشيح على العميل). **طلبات إضافية: 0**؛ **نداءات Worker: 0**؛ الصفحات والمؤشر والعدّ بلا تغيير. الضغط على المضيف (gzip) **UNVERIFIED**؛ كلفة القاعدة الحقيقية للربط/RLS **UNVERIFIED**؛ ترتيب المعرّفات على العميل ≤ 10 عناصر لكل سجل (مهمل).

**الاختبارات:** جديد `test/lists/offer_owner_list_media_ids_test.dart` **31/31 ✅** — لكل من Offers وOwners: شكل الـ `select` (المعرّف/الترتيب/الحالة/النوع فقط؛ لا `object_key`/`bucket`/رابط/`!inner`؛ `offer_areas` باقٍ)؛ 0/1/10 وسائط بالترتيب، وأب بلا مفتاح تضمين؛ جاهز ونوع مسرود فقط، وتكرار ومعرّف تالف/بأحرف كبيرة/ترتيب غير صحيح أو سالب/`media_objects` ناقص أو null/مدخل ليس map ⇒ مستبعد؛ روابط جدول أب آخر مُتجاهلة؛ 1,200 سجل = 3 صفحات بعدّ دقيق و500 للصفحة و0 Worker؛ `created_at` متساوٍ؛ حساب آخر؛ حساب فارغ؛ فشل التضمين (400) وفشل الصفحة الأولى واللاحقة ⇒ خطأ بلا قائمة جزئية؛ تغيّر الحساب أثناء القراءة؛ القراءة المفردة تحمل الهوية نفسها؛ `mediaObjectIds`/`mediaUrls` فارغة؛ نماذج قديمة بلا الحقل و`copyWith`؛ **الكاش المشفّر لا يحفظ الهوية بعد** (كتابة/قراءة حقيقية ⇒ `[]`)؛ القياسات. **انحدار:** `test/lists` + `test/favorites` + `test/search` + `test/offers` + `test/owners` + `test/perf` + `test/home` + `test/related_items` ⇒ **2053/2053 ✅** (يشمل ثابت «أعمدة القائمة = القراءة المفردة» في `entity_keyset_pagination_test`). التركيز الأخير بعد التنسيق **183/183 ✅**. `flutter analyze` (4 ملفات): لا مشاكل؛ التنسيق 0 تغيير (سطرا كودي الجديد يدوياً؛ سطر فارغ بادئ في `owners_model.dart` قائم في HEAD لم يُلمس)؛ `git diff --check` نظيف؛ CRLF محفوظ.

**الطفرات (استعادة SHA-256):** **14/14 مقتولة** — K1 قبول غير الجاهز، K2 بلا ترتيب، K3 أي نوع، K4 أي نص معرّفاً، K5 إبقاء التكرار، K6 Offers بلا تضمين، K7 `!inner`، K8 قائمة Owners بلا تضمين، K9 القراءة المفردة بلا تضمين، K10 Owners من جدول Offers، K11 ترتيب سالب، K12 تسرّب الهوية إلى `mediaObjectIds`، K13/K14 `copyWith` يُسقط الهوية.

**التوافق:** إضافي فقط؛ الحقل الجديد افتراضيه `[]`؛ صيغ الكاش المشفّر v2/HMAC/علامات الحذف/النسخ الاحتياطي/عزل الحساب **بلا تغيير** (لا ترميز للحقل بعد)؛ لا SQL/ترحيل/Worker؛ لا Auth/SAD. **التراجع:** إرجاع الأعمدة والحقل؛ لا بيانات مخزّنة تعتمد عليه.

**المخاطر الباقية:** صياغة التضمين وسلوك `max_rows`/الضغط على المضيف **UNVERIFIED** حتى فحص المالك؛ زيادة حمولة كل قراءة Offers/Owners (≈ +62% لـ Offers بـ 3 روابط في المحاكاة) وقراءات المفضلة بالمعرّفات؛ فرق مرشح `bucket`/نمط المفتاح عن الـ Worker (هوية فقط، لا إذن)؛ زمن الجهاز REAL_DEVICE_UNVERIFIED.

**الملفات:** إنتاج: `lib/src/services/supabase_core_entities_service.dart`، `lib/src/data/models/ScreensModel/offers_model.dart`، `lib/src/data/models/ScreensModel/owners_model.dart`؛ اختبار جديد: `test/lists/offer_owner_list_media_ids_test.dart`؛ وهذا المتتبّع. أداة PGlite في مجلد الجلسة المؤقت فقط (خارج المستودع).

**التالي (بموافقة منفصلة):** **M2-2** حفظ المعرّفات داخل حمولة v2. **غير مبدوء:** M2-3، M3، M1d-3، M4، M5. **المحفوظ:** P4.3-ACCEPT-NONEMPTY؛ D-57؛ D-DAM-4/5؛ مسارات iOS؛ التلف بنفس الحجم؛ تنزيلات `CachedNetworkImage` المباشرة؛ FU-FAV-MEDIA-NO-IDENTITY؛ الإخفاقات التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit.

**الحالة:** **M2-1 = CODE_PROVEN (+ PGlite) — HOSTED_UNVERIFIED — REAL_DEVICE_UNVERIFIED؛ غير مدمج.** ← حُدّثت بالفحص المسبق أدناه.

##### M2-1 — الفحص المسبق النهائي لاستعلام المضيف والأمان — 2026-11-09 (لا تغيير مصدر؛ HOSTED_UNVERIFIED)

**Git (مُتحقَّق بعد fetch):** HEAD `4595449` = `origin`؛ الفهرس فارغ؛ ثلاثة stashes محفوظة؛ مجموعة M2-1 من Git: `lib/src/services/supabase_core_entities_service.dart`، `lib/src/data/models/ScreensModel/offers_model.dart`، `lib/src/data/models/ScreensModel/owners_model.dart`، `test/lists/offer_owner_list_media_ids_test.dart`، وهذا المتتبّع.

**المراجعة 1 — شكل الاستعلام الفعلي: PASS.** التُقطت الطلبات الحقيقية من العميل (`postgrest` 2.9.1 يحذف المسافات خارج الاقتباس) باختبار مؤقت حُذف فوراً (لم يدخل الشجرة):
- قائمة Offers ص1: `GET /rest/v1/offers?select=id,owner_id,…,updated_at,offer_areas(area,ordinal),offer_media(media_id,ordinal,media_objects(status,content_type))&owner_id=eq.<uid>&deleted_at=is.null&order=created_at.desc.nullslast,id.desc.nullslast&limit=500` + `Prefer: count=exact`؛ ص2: الشيء نفسه + `or=(created_at.lt.<t>,and(created_at.eq.<t>,id.lt.<id>))` بلا عدّ.
- القراءة المفردة لـ Offer: الـ `select` نفسه + `id=eq.<id>&deleted_at=is.null&limit=1`.
- Owners (قائمة/مفردة): `select=*,owner_media(media_id,ordinal,media_objects(status,content_type))` بالمرشحات/الترتيب/الحد نفسها.
- **لا `!inner`، لا مرشح ولا ترتيب مضمَّن**؛ `offer_areas` باقٍ؛ طلب واحد لكل صفحة (501 صفاً = طلبان)؛ 0 نداء Worker.
- **حلّ العلاقات (مخطط الترحيلات الحقيقي على PGlite):** `offer_media.offer_id → offers` و`offer_media.media_id → media_objects` مفتاح أجنبي واحد لكل منهما؛ ومثلهما `owner_media.owner_record_id → owners` و`owner_media.media_id → media_objects` ⇒ لا لبس متوقع (PGRST201). **تنبيه لـ M3:** `offers.plan_media_id`/`owners.plan_media_id → media_objects` موجودان، فتضمين `media_objects` **مباشرة** من الأب قد يكون ملتبساً — M2-1 لا يفعل ذلك. **الصلاحيات:** `grant select … to authenticated` على الجداول الثلاثة، بلا أي `revoke` أو منح عمود في الترحيلات.

**المراجعة 2 — التحقق المستضاف: لم يُنفَّذ أي طلب مستضاف.** لا جلسة حساب اختبار مخصّص مُصرَّح بها متاحة؛ الحساب A هو حساب هاتف المالك (أي جلسة جديدة له تزيح الهاتف تحت SAD) ⇒ **لم يُستخدم**؛ لا تسجيل دخول، لا مطالبة جلسة، لا service_role، لا SQL مميّز، لا كتابة. **شرط إطلاق H-M2-1 (بيد المالك، قبل أي بناء يصل للهاتف أو المستخدمين):** لو رفض المضيف التضمين (400)، تفشل online قراءات قوائم Offers/Owners **وقراءات بيانات التفاصيل الوصفية** وقراءات المفضلة بالمعرّفات (القوائم المحفوظة offline تبقى — كل-أو-لا-شيء). **أصغر خطة:** (أ) **الأقوى والأبسط:** تشغيل بناء M2-1 على هاتف المالك (جلسة A القائمة على جهازه، بلا إزاحة) وفتح قائمة Offers وقائمة Owners وتفاصيل Offer وOwner online ⇒ تحميلها = المضيف قبل التضمين والعلاقات والصلاحيات (البنود 1–3؛ الهويات لا تُعرض في M2-1)؛ (ب) **اختياري بلا جلسة:** طلب مجهول `…&limit=0` بالمفتاح العام لكل جدول — المتوقع 401/`42501` (صلاحية) **لا** 400 `PGRST200/201` ⇒ يثبت حلّ العلاقات في ذاكرة مخطط المضيف فقط، لا صفوف ولا RLS؛ (ج) **للصفوف (بموافقة منفصلة، حساب اختبار غير A):** الطلب نفسه بتوكن ذلك الحساب ⇒ 200، `content-range` = عدد سجلاته، سجل بلا وسائط بـ `[]`، معرّفات سجل واحد ومرتبتها = `GET /offer-media?offerId=…` بعد ترشيح `ready`، وجلسته المُزاحة ⇒ لا شيء. حدود الصفحات (> 500 سجل) **غير قابلة للتحقق** ببيانات الاختبار المتاحة (كـ P4.3-ACCEPT-NONEMPTY).

**المراجعة 3 — سلامة الهوية: PASS.** القارئ الوحيد لـ `listedMediaObjectIds` في `lib/` = سطرا التعيين في الخدمة (لا عرض ولا حفظ)؛ لا سطر في الـ diff يمس `mediaObjectIds` القائم ⇒ المعرض ونموذج التعديل والمفضلة بلا تغيير؛ الترميز/الكاش المشفّر لم يُلمس (واختبار الكتابة/القراءة يعيد `[]`)؛ النماذج القديمة `[]` افتراضياً؛ المشوّه/غير الجاهز/غير المسرود/المكرر مستبعد، والترتيب `ordinal` ثم المعرّف حتمي (مُختبر ومُطفَّر). **الفرق عن الـ Worker صريح:** العميل **لا** يعيد إنتاج فحص `bucket` ونمط `object_key` ولا `assertOwnsParent` (الأخير تغطيه RLS لنفس الحساب)؛ فالمرشح هوية فقط وليس قاعدة تفويض.

**المراجعة 4 — الأداء والتوافق: PASS.** عدد الطلبات **حتمي** (اختبار)؛ نمو الحمولة **مُقاس على المحاكي** (≈ 130 B/رابط بلا ضغط)؛ RLS/SAD على الصفوف المضمّنة **مُتحقَّق محلياً (PGlite)**؛ PostgREST المستضاف **UNVERIFIED**؛ Samsung/iOS **UNVERIFIED**. معاملات الصفحات/المؤشر/العدّ مطابقة لما قبل (الـ URLs أعلاه) ⇒ عقد الاكتمال P4 بلا تغيير؛ صيغة القائمة المحفوظة بلا تغيير.

**تصحيحات:** لا شيء (لا تغيير مصدر؛ لم تُعَد المجموعات). **القرار المقترح:** commit محلي **CODE_PROVEN** مقبول (الـ commit لا ينشر شيئاً)، مع **حجب الإطلاق/البناء على الهاتف حتى H-M2-1**؛ لا M2-2 فوقه قبل نجاح H-M2-1 أو موافقة المالك الصريحة.

**المحفوظ:** M2-2/M2-3/M3 **معلّقة**؛ P4.3-ACCEPT-NONEMPTY؛ D-57؛ D-DAM-4/5؛ مسارات iOS؛ التلف بنفس الحجم؛ M1d-3 بعد M3؛ M4/M5؛ إخفاقات Auth/Delete Account التاريخية؛ قيود PDF عروض الأسعار؛ Smart Map/Toolkit.

**الحالة:** **M2-1 = CODE_PROVEN — HOSTED_UNVERIFIED — REAL_DEVICE_UNVERIFIED؛ commit محلي واحد بموافقة المالك (2026-11-09).** **H-M2-1 = BLOCKING للإطلاق:** لا إنشاء ولا توزيع ولا تثبيت ولا نشر لإصدار عادي يحوي M2-1 حتى ينجح H-M2-1؛ بناء تشخيصي يتحكم به المالك لأجل H-M2-1 وحده يحتاج موافقة صريحة مسبقة؛ لا استخدام للحساب A من جهاز أو جلسة ثانية ولا إزاحة لجلسة الهاتف؛ لا افتراض لوجود حساب اختبار مخصّص قبل التحقق منه؛ نجاح PGlite المحلي أو 401 مجهول من المضيف **ليس** بديلاً عن تحقق الصفوف المستضاف الموثّق. P4.3-ACCEPT-NONEMPTY منفصل ومفتوح. **STOP:** لا M2-2/M2-3/M3.

##### H-M2-1a — الفحص المسبق لسلامة التحقق المستضاف من استعلام M2-1 — 2026-11-09 (قراءة فقط؛ لا طلب مستضاف؛ لا بناء؛ لا adb)

**Git (مُتحقَّق):** HEAD `45d51b0` = `origin` (دفعه المالك)؛ الفهرس فارغ؛ شجرة العمل نظيفة (ملفات plugin الثلاثة لم تعد تظهر معدّلة). **أربعة stashes الآن:** stash جديد `stash@{0}` «On perf/phase-1-startup-baseline: !!GitHub_Desktop<perf/phase-1-startup-baseline>» (2026-11-09 18:17 +0400، أبوه `45d51b0`) — شجرتا العمل والفهرس فيه **مطابقتان لشجرة HEAD**، وجزء الملفات غير المتتبَّعة (1,460 ملفاً) **مطابق لشجرة HEAD بلا فرق** ⇒ لا محتوى فيه خارج HEAD (الأرجح حالة نهايات الأسطر لملفات plugin). لم يُلمس؛ والثلاثة الأقدم (`iOS-branch`، `update-some-issues`، `toolkit-cloud-documents-readiness`) باقية.

**المرحلة 1 — ما يمكن فحصه بلا مصادقة التطبيق:**
- **دليل المخطط المستضاف (تاريخ لا فحص حيّ):** `docs/CURRENT_CHECKPOINT.md` يسجّل أن تاريخ ترحيلات المشروع `rbvcnvqpdqrhywcgxkne` (مشترك بين staging والإنتاج) = ترحيلات HEAD الـ 19 (آخرها `20261019100000`، 2026-10-21)، ولا ترحيل جديد في المستودع منذ ذلك ⇒ جداول الربط ومفاتيحها الأجنبية الأحادية موجودة **بحسب التاريخ**. المخطط الحيّ **لم يُقرأ** (انحراف من اللوحة ممكن نظرياً) ⇒ ليس إثباتاً.
- **فحص مجهول P-0 (مقترح، لم يُنفَّذ):** `anon` بلا أي صلاحية جدول (`revoke all on all tables in schema public from anon, authenticated` ثم `grant select … to authenticated` فقط). PostgREST يحلّ التضمين من ذاكرة مخططه عند بناء الطلب **قبل** أن ينفّذه Postgres ⇒ `401` + `"code":"42501"` = التضمين حُلّ؛ `400` + `PGRST200`/`PGRST201`/`PGRST100` = FAIL. طلبا GET فقط، بالمفتاح العام (القيمة الافتراضية في `lib/src/config/supabase_config.dart`، لا تُطبع)، **بلا** توكن مستخدم، `limit=0`، ومرشح مالك صفري:
  - `GET /rest/v1/offers?select=id,owner_id,offer_type,selected_city,location_text,phone_number,country_code,min_price,max_price,square_footage,notes,property_type,specific_property_type,rooms,bathrooms,pickup_location_text,pickup_latitude,pickup_longitude,pickup_address,legacy_uploaded_file_name,status,created_at,updated_at,offer_areas(area,ordinal),offer_media(media_id,ordinal,media_objects(status,content_type))&owner_id=eq.00000000-0000-0000-0000-000000000000&deleted_at=is.null&order=created_at.desc.nullslast,id.desc.nullslast&limit=0`
  - `GET /rest/v1/owners?select=*,owner_media(media_id,ordinal,media_objects(status,content_type))&owner_id=eq.00000000-0000-0000-0000-000000000000&deleted_at=is.null&order=created_at.desc.nullslast,id.desc.nullslast&limit=0`
  - القراءات المفردة وبالمعرّفات تستعمل الـ `select` نفسه ⇒ الحلّ نفسه؛ لا طلب إضافي. الأثر الجانبي: سطرا سجل API فقط. **لا يثبت شيئاً عن الصفوف أو RLS أو SAD.**
- **اللوحة/CLI:** لم تُستعمل؛ محرر الجداول وSQL و`supabase db query --linked` تعمل بدور مميّز (خارج الصلاحية الممنوحة)، وتصفح المخطط لا يضيف شيئاً على تاريخ الترحيلات لحلّ العلاقات.

**المرحلة 2 — سلامة الهاتف القائم (مُتحقَّق من المصدر/الأدوات المحلية):**
1. **المعرّف والنكهة:** `applicationId` = `com.example.broker_wallet`؛ لا `productFlavors`؛ debug/profile/release بالمعرّف نفسه ⇒ **أي** بناء يحلّ محل تطبيق الهاتف اليومي (خانة تطبيق واحدة).
2. **التوقيع:** لا `android/key.properties` ولا keystore في هذا المجلد ⇒ إعداد توقيع release فارغ هنا (مفتاح release موجود فقط في `C:/App-Projects/broker-wallet-main`، بشهادة مختلفة). debug/profile تُوقَّع بـ `~/.android/debug.keystore` (لم يتغير منذ 2023-10-10)، وهي الشهادة التي طابقت التطبيق المثبَّت في 2026-10-31 (`6dcf85…9f61`) ⇒ تحديث في المكان **متوقع** ممكناً؛ APK موقَّع release سيُرفض بـ `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
3–4. **خطر الاستبدال/الحذف — فخّان حرجان (مُتحقَّقان في `C:\Flutter\packages\flutter_tools`):** `flutter install` **يزيل التطبيق القائم أولاً افتراضياً** (`commands/install.dart`: `uninstall = true`)؛ و`flutter run` يجرب `install -r` ثم **يزيل ويعيد التثبيت تلقائياً عند أي فشل** (`android/android_device.dart` `installApp`: «Uninstalling old version...») ⇒ كلاهما قد يمحو كل بيانات الهاتف. **المسار الآمن الوحيد:** `adb -s R5CY10YYLSM install -r <apk>` (بلا `-d`)، الذي يتوقف عند عدم تطابق التوقيع دون لمس البيانات. `versionCode` = 1 (`1.0.0+1`) كالمثبَّت ⇒ ليس تخفيضاً.
5. **الاستمرارية:** جلسة Supabase في `FlutterSecureStorage` (Keystore)، القوائم المشفّرة AES بمفاتيح Keystore، الكاش الخاص للصور، مجلدات Toolkit، طوابير الرفع ⇒ **تبقى** في تحديث في المكان (UID وتوقيع واحد)، و**تضيع كلها** عند الإزالة أو مسح البيانات.
6. **النسخ الاحتياطي:** القواعد تستثني `offline_lists` و`offer_media` و`scanner` و`combine_pdfs` و`image_to_pdf` و`signature_pdfs` و`quotation_pdfs` و`profile_media` و`url_mapping`/`local_media` و`bwPrivateMedia.db`…، ومفاتيح Keystore لا تُنسخ أصلاً ⇒ **لا مسار استعادة** لهذه البيانات؛ مستندات Toolkit المحلية غير المرفوعة **لا تُسترد** بعد إزالة. نسخة APK ليست نسخة بيانات.
7–8. **الجلسة القائمة:** إقلاع بارد بجلسة محفوظة ⇒ `supabase_flutter` 2.17.2 `setInitialSession` → `initialSession`، و`gotrue` 2.27.2 `recoverSession` → `tokenRefreshed` فقط، **لا `signedIn` أبداً**. في `supabase_auth_repository.dart` لا يطالب (`claim_current_app_session`) إلا حدث `signedIn` وتسجيل الدخول/الإنشاء الصريحان؛ الجلسة المستعادة تنادي `is_current_app_session` (قراءة) ⇒ **تحديث في المكان + فتح التطبيق يستعمل جلسة A القائمة على الهاتف، بلا جلسة جديدة ولا مطالبة ولا إزاحة.** تدوير توكن التحديث العادي = كل فتح يومي. **شرط:** لو ظهرت شاشة الدخول بعد التحديث ⇒ STOP، لا تسجيل دخول (= مطالبة) دون موافقة.
9. **الكتابات أثناء الفحص:** فتح قوائم Offers/Owners وتفاصيلها = GET لـ PostgREST + `GET` للـ Worker (روابط موقّعة، قراءة) + عمل كاش محلي (تبنّي M1d-1، تبديل M1d-2 — محلي). كتابات قائمة **لا يسببها M2-1:** طابور رفع متبقٍّ يُستأنف عند أي فتح (`OfferMediaUploadQueue.setActiveOwner` → `_drain`)، وتدوير التوكن. **ممنوع لمسه أثناء الفحص:** تعديل/حفظ، حذف، تبديل مفضلة، إضافة وسائط، Toolkit، عروض الأسعار، تعديل الملف الشخصي، تسجيل الخروج (`release_current_app_session`)، Delete Account.

**مجهول حاسم — أي بناء على الهاتف الآن:** آخر سجل = Profile من `f686b80` مثبَّت في 2026-11-01 (§7I)، ولا سجل بعده. لو بقي كذلك فبناء HEAD سيجلب للهاتف **لأول مرة** كل العمل منذ ذلك (القوائم المشفّرة P2، P3/P4، خزنة Q-2، M1b–M1d-2، DA-MAP-1، M1e-a، M2-1) ويشغّل ترحيلاته لمرة واحدة على بيانات A الحقيقية ⇒ هو عملياً **جلسة الجهاز الموحّدة المؤجلة**، لا فحص M2-1 وحده. قرار المالك.

**المرحلة 3–4 — خطة القبول (بيد المالك؛ كل خطوة بموافقة منفصلة؛ لم يُنفَّذ شيء):**
- **H0 (بلا جلسة):** P-0 أعلاه. PASS ⇒ متابعة؛ `400 PGRST*` ⇒ STOP، لا بناء؛ الإصلاح تغيير كود في checkpoint جديد.
- **H1 (adb قراءة فقط):** `adb devices`؛ `adb -s R5CY10YYLSM shell getprop ro.serialno`؛ `pm path com.example.broker_wallet`؛ `sha256sum` لـ `base.apk`؛ `dumpsys package com.example.broker_wallet` (versionCode، firstInstallTime، lastUpdateTime، التوقيع)؛ `adb pull` لـ `base.apk` إلى مجلد جديد `Downloads\BW_H_M2_1\pre_install\` (نسخة APK فقط). تحديد البناء المثبَّت؛ شهادة ≠ debug ⇒ STOP.
- **H2 (بناء):** `flutter build apk --debug` على `45d51b0` — **أبداً** `flutter run`/`flutter install`. `apksigner verify --print-certs` يجب أن يطابق شهادة المثبَّت؛ تسجيل SHA-256. (اختياري لأجل الرجوع: APK debug من `4595449` في worktree منفصل، دون تبديل فرع هذا المجلد.)
- **H3 (تثبيت في المكان):** الهاتف مستيقظ وغير مقفل؛ `adb -s R5CY10YYLSM install -r build\app\outputs\flutter-apk\app-debug.apk`. أي `INSTALL_FAILED_*` ⇒ STOP، **لا إزالة أبداً**. بعده: `firstInstallTime` بلا تغيير، وSHA-256 على الهاتف = المبني.
- **H4 (على الهاتف، online):** فتح التطبيق ⇒ Home **بلا** شاشة دخول؛ قائمة Offers ثم Owners مع سحب للتحديث مرة؛ تفاصيل Offer بصور وأخرى بلا صور، وOwner بصور وآخر بلا صور. **المتوقع:** القوائم تُحمَّل بالسجلات نفسها كما قبل (والعدد حيث يُعرض)، السجلات بلا وسائط **باقية**، الصور تظهر كما قبل، لا حالة خطأ، لا خروج من الحساب. ثم وضع الطيران ⇒ القوائم المحفوظة تظهر كما اليوم.
- **H4b (اختياري؛ checkpoint وموافقة منفصلان؛ كود تشخيصي مؤقت debug فقط لا يُودَع):** عند فتح تفاصيل سجل يقارن `listedMediaObjectIds` بـ `mediaObjectIds` المصفوفة مع روابط الـ Worker (الجلسة نفسها، **بلا طلب إضافي**) ويسجّل أعداداً/قيماً منطقية فقط (`ids=3 worker=3 same=true uuid=true`)، لا معرّفات ⇒ يتحقق من صحة المعرّفات وترتيبها ومرشح `ready`/الأنواع على صفوف A المستضافة.

**PASS / PARTIAL / FAIL:**
- **PASS (قبول الاستعلام مستضافاً لصفوف A):** H0 = `401`/`42501` للجدولين؛ H3 في المكان؛ H4 كله يُحمَّل online بلا دخول ولا خطأ، والسجلات بلا وسائط باقية. يزيل خطر الـ 400 الذي وُجد H-M2-1 لأجله. (+H4b `same=true` لكل سجل مفتوح ⇒ الهويات مستضافة VERIFIED لـ A.)
- **PARTIAL:** H0 وحده (حلّ العلاقات فقط) أو H4 بلا H4b (الاستعلام مقبول؛ المعرّفات/الترتيب/المرشح مستضافاً UNVERIFIED). وفي كل الحالات تبقى UNVERIFIED: حدود 500 صف، سلوك الجلسة المُزاحة، العزل بين الحسابات.
- **FAIL:** `400 PGRST*` في H0؛ أو قائمة/تفاصيل لا تُحمَّل online أو فارغة أو خطأ في H4؛ أو ظهور شاشة الدخول؛ أو فشل التثبيت.

**التوقف الآمن عند الفشل:** توقف فوراً؛ لا إعادة محاولة متكررة، لا تسجيل دخول، لا إزالة، لا مسح بيانات، لا `flutter run`؛ سجّل الشاشة والوقت فقط؛ القوائم المحفوظة offline تبقى قابلة للقراءة.

**الرجوع:** **آمن بالتصميم فقط** إلى بناء `4595449` (HEAD^): M2-1 لا يحفظ شيئاً (لا صندوق ولا حقل جديد؛ صيغة القائمة المشفّرة بلا تغيير — مُختبر) ⇒ البناء الأقدم يقرأ البيانات نفسها؛ يحتاج بناءه مسبقاً و`adb install -r` (versionCode 1 والشهادة نفسها). الرجوع إلى نسخة `base.apk` المسحوبة **NOT VERIFIED SAFE** إن كانت أقدم من M1b (ترحيلات M1b–M1d-2 لمرة واحدة — فهرس الكاش الخاص وتبديل `url_mapping` — قد لا يقرأها الكود الأقدم؛ لم يُثبت أي اتجاه). **ممنوع دائماً:** الإزالة، مسح البيانات، `flutter run`، `flutter install`، `-d`، APK موقَّع release.

**لا يُعرض ولا يُسجَّل ولا يُرسَل:** توكنات الوصول/التحديث، JWT، ترويسات Authorization، قيمة المفتاح العام في المحادثة، معرّف الحساب، معرّفات السجلات والوسائط (مقنّعة فقط)، مفاتيح الكائنات، الروابط الموقّعة، بيانات العملاء (أسماء، هواتف، أسعار) في لقطات الشاشة، وlogcat خاماً.

**الموافقات المطلوبة بالترتيب:** (1) P-0؛ (2) adb قراءة + سحب APK؛ (3) بناء debug (+ بناء الرجوع `4595449` اختيارياً)؛ (4) التثبيت في المكان؛ (5) H4b اختيارياً. أي تسجيل دخول ليس جزءاً من الخطة.

**غير مُتحقَّق:** المخطط المستضاف الحيّ (التاريخ فقط)؛ البناء المثبَّت حالياً وشهادته الحالية؛ وجود طابور رفع متبقٍّ على الهاتف؛ نسخة PostgREST المستضافة؛ حساب اختبار مخصّص غير A — **غير موجود على هذا الحاسوب** (متغيرات `BW_TEST_*` = الحساب A؛ لا `BW_TEST_B_*`) ⇒ RLS بين الحسابات وسلوك الجلسة المُزاحة مستضافاً غير قابلين للتحقق دون حساب ثانٍ يوفّره المالك؛ حدود 500 صف (لا إنشاء بيانات)؛ عدد الطلبات على الجهاز (مُثبت بالاختبارات فقط)؛ Samsung/iOS.

**المحفوظ:** P4.3-ACCEPT-NONEMPTY **منفصل ومفتوح**؛ M2-2/M2-3 **NOT STARTED**؛ M3، M1d-3 (بعد M3)، M4/M5، D-57، D-DAM-4/5، مسارات iOS، التلف بنفس الحجم، الوصولات المباشرة لـ CachedNetworkImage، الإخفاقات التاريخية (Auth/Delete Account/Combine)، قيود PDF عروض الأسعار، Smart Map/Toolkit — **مفتوحة**.

**الحالة:** **H-M2-1a = PLAN READY (SOURCE/TOOL-VERIFIED، لا طلب مستضاف)؛ H-M2-1 = BLOCKING — NOT RUN.** **NOW:** قرار المالك بشأن P-0 ثم H1–H4 (والمجهول: البناء المثبَّت). **STOP:** لا بناء ولا تثبيت ولا فحص مستضاف مصادَق دون موافقة؛ لا M2-2/M2-3/M3.

##### H-M2-1 P-0 — الفحص المجهول المستضاف — 2026-11-09 (بموافقة المالك؛ طلبا GET فقط؛ بلا جلسة)

**Git:** الفرع `perf/phase-1-startup-baseline`؛ HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ التغيير الوحيد غير المودع = هذا المتتبّع (H-M2-1a + هذا القسم)؛ أربعة stashes محفوظة.

**التنفيذ:** سكربت Node في مساحة الجلسة المؤقتة قرأ عنوانَي P-0 **حرفياً** من قسم H-M2-1a أعلاه، والعنوان والمفتاح العام من القيم الافتراضية في `lib/src/config/supabase_config.dart` (لم يُطبع المفتاح)؛ ترويسة `apikey` فقط، **بلا** `Authorization`/توكن مستخدم ⇒ دور `anon`؛ كل طلب **مرة واحدة** بلا إعادة؛ طُبعت الحالة والرمز والرسالة وأسماء حقول الجسم فقط.

| الجدول | الشكل | الوقت (UTC) | HTTP | الرمز | الرسالة |
|---|---|---|---|---|---|
| `offers` | `select` الكامل لـ `_offerColumns` (+ `offer_areas(area,ordinal)` + `offer_media(media_id,ordinal,media_objects(status,content_type))`)، مالك صفري، `deleted_at=is.null`، ترتيب P4، `limit=0` | 18:09:09.717 | **401** | **`42501`** | `permission denied for table offers` |
| `owners` | `select=*,owner_media(media_id,ordinal,media_objects(status,content_type))`، المرشحات/الترتيب نفسها، `limit=0` | 18:09:10.295 | **401** | **`42501`** | `permission denied for table owners` |

لا `content-range`؛ لا صفوف (جسم خطأ فقط: `code,details,hint,message`)؛ لا `PGRST200`/`PGRST201`/`PGRST100`.

**ما يثبته (دليل مخطط/شكل مجهول فقط):** PostgREST المستضاف قبِل صياغة الـ `select` الكاملة وحلّ علاقات التضمين بمستوييها (`offer_media`/`owner_media` ← الأب، و`media_objects` من جدول الربط) و`offer_areas` من ذاكرة مخططه **دون لبس**، ثم أرسل الاستعلام فرفضه Postgres لغياب صلاحية `anon` ⇒ مطابق للترحيلات (`revoke all … from anon`). القراءات المفردة وبالمعرّفات تستعمل الـ `select` نفسه ⇒ الحلّ نفسه **استنتاجاً** (لم تُطلب). الاستدلال يعتمد على أن PostgREST يحلّ التضمين قبل التنفيذ (سلوكه المعروف؛ نسخة المضيف غير معروفة).

**ما لا يثبته (يبقى UNVERIFIED):** صلاحية `authenticated` الفعلية على `offer_media`/`owner_media`/`media_objects` مستضافاً؛ أي قراءة صفوف؛ العدّ الدقيق؛ بقاء السجلات بلا وسائط؛ صحة المعرّفات وترتيبها ومرشح `ready`/الأنواع؛ عزل RLS بين الحسابات؛ سلوك SAD؛ حدود 500 صف؛ عدد الطلبات على الجهاز. **H-M2-1 لم يجتز** — P-0 = H0 فقط.

**الحالة:** **H0/P-0 = PASS (ANONYMOUS SCHEMA/QUERY-SHAPE ONLY)؛ H-M2-1 = BLOCKING — PARTIAL (relationship resolution only)؛ M2-1 = CODE_PROVEN — HOSTED_AUTHENTICATED_UNVERIFIED — REAL_DEVICE_UNVERIFIED.** P4.3-ACCEPT-NONEMPTY منفصل ومفتوح؛ M2-2/M2-3 NOT STARTED. **NEXT (بموافقة منفصلة):** H1 (adb قراءة فقط: تحديد البناء المثبَّت وشهادته). **STOP.**

##### H-M2-1 H1 — جرد البناء المثبَّت على Samsung (قراءة فقط) — 2026-11-09 — **BLOCKED: لا جهاز متصل**

**Git:** الفرع `perf/phase-1-startup-baseline`؛ HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ التغيير الوحيد = هذا المتتبّع؛ أربعة stashes محفوظة.

**ADB (قراءة فقط):** `adb devices -l` ⇒ **قائمة فارغة** (لا USB ولا لاسلكي)؛ `adb mdns services` ⇒ لا خدمة مكتشفة (الهاتف لا يعلن تصحيحاً لاسلكياً). لم يُنفَّذ `adb connect` ولا اقتران ولا أي تغيير إعدادات ⇒ **توقف حسب شرط المرحلة 1.** لم يُقرأ شيء من الهاتف: الحزمة، النسخة، versionCode، أوقات التثبيت، مسارات/SHA-256 الـ APK، وشهادة المثبَّت = **UNKNOWN**. لا نسخة APK.

**حقائق محلية (قراءة ملفات فقط):**
- شهادة debug على هذا الحاسوب: `apksigner verify --print-certs` (build-tools 36.0.0) على `build\app\outputs\flutter-apk\app-debug.apk` (2026-11-07 16:09، مصدره **غير مسجّل**، SHA-256 `eb574041…acfec1`) ⇒ `CN=Android Debug`، SHA-256 الشهادة `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` = الشهادة التي سُجّلت للتطبيق المثبَّت في 2026-10-31 (`6dcf85…9f61`) ⇒ أي بناء debug/profile من هنا **يُتوقع** أن يطابق المثبَّت **إن لم يتغير منذ ذلك** (غير مُتحقَّق اليوم).
- **نسخة الرجوع مفقودة:** مجلد `Downloads\BW_P1_1a` (وفيه `installed_debug_2026-10-30\installed_base.apk`، SHA-256 `646255…22cc`، §7G) **لم يعد موجوداً**، ولا ملف بهذا الاسم تحت `Downloads` أو `C:\App-Projects`؛ و`app-profile.apk` (§7F/§7I) لم يعد في `build\` ⇒ لا قطعة معروفة المصدر لمطابقة الهاتف بها أو للرجوع إليها حالياً.

**ما زال مطلوباً من H1 (عند اتصال الهاتف):** `getprop ro.serialno` (يُذكر مقنّعاً)، `ro.build.version.release/sdk`؛ `pm list packages com.example.broker_wallet`؛ `pm path` (مع splits)؛ `dumpsys package` (versionName/versionCode/firstInstallTime/lastUpdateTime/installer/DEBUGGABLE)؛ `sha256sum` لكل APK؛ `adb pull` للـ APK فقط إلى مجلد جديد معزول؛ `apksigner --print-certs`؛ مطابقة SHA-256 مع القطع المعروفة (`646255…` debug 2026-10-30، `b578c054…` Profile `f686b80`)؛ وفحص ثابت للـ APK المنسوخ بحثاً عن علامات نصية للميزات (P2 القوائم المشفّرة، المفضلة المشفّرة، Search local-first، خزنة Q-2، M1b `bw-private-media://`، M1c، M1d، M2-1 `offer_media(media_id`) — قيم منطقية فقط، بلا قيم إعداد. بلا مطابقة SHA-256 مع قطعة معروفة ⇒ المراجعة المصدرية **UNKNOWN** (لا استنتاج من versionCode أو التاريخ أو التوقيع).

**شروط تمنع H2/H3:** لا جهاز أو غير مخوَّل؛ الحزمة غير مثبتة أو بمعرّف آخر؛ شهادة المثبَّت ≠ `6dcf85…9f61`؛ splits غير متوقعة؛ versionCode > 1؛ بناء مثبَّت مجهول الميزات دون قرار المالك بقبول الترحيلات المتراكمة (§H-M2-1a)؛ عدم وجود APK رجوع مُتحقَّق (بناء `4595449` أو نسخة مسحوبة مُطابَقة).

**الحالة:** **H1 = BLOCKED (NO DEVICE)؛ H-M2-1 = BLOCKING — PARTIAL (P-0 فقط).** P4.3-ACCEPT-NONEMPTY وD-57 وكل البنود المفتوحة باقية؛ M2-2/M2-3 NOT STARTED. **NEXT:** المالك يوصل الهاتف (USB، مفتوح القفل، تصحيح USB مفعّل ومخوَّل مسبقاً لهذا الحاسوب) ويؤكد متابعة H1 بالموافقة نفسها. **STOP.**

##### H-M2-1 H1 (متابعة بعد توصيل الهاتف) — جرد البناء المثبَّت — 2026-11-09 — **DONE (قراءة فقط)**

**الجهاز:** `adb devices -l` ⇒ جهاز واحد، **مخوَّل** (`device`)، نموذج SM-S928B؛ `ro.serialno` = المتوقع (`R5CY…LSM`)؛ Android 17 / SDK 37؛ المنطقة الزمنية `Asia/Dubai` (+04). لم يُتصل بجهاز آخر ولم يُغيَّر أي إعداد.

**الحزمة (`pm`/`dumpsys`، قراءة فقط):** `com.example.broker_wallet` مثبتة للمستخدم 0 فقط (المستخدمان 95 و150: غير مثبتة)؛ `versionName` 1.0.0؛ `versionCode` **1**؛ `minSdk` 24 / `targetSdk` 35؛ `arm64-v8a`؛ **`DEBUGGABLE`**؛ ملف واحد `base.apk` (**بلا splits**)؛ `apkSigningVersion` 2؛ `packageSource=3` (ملف محلي)؛ المثبِّت `com.google.android.packageinstaller`، **المصدر `com.whatsapp`** (APK فُتح من WhatsApp، لا adb)؛ لا `updateOwner` ⇒ لا مالك تحديث يمنع adb. **`firstInstallTime` = 2026-11-04 13:38:12 (+04)** — أحدث من سجلات §7G–§7I (التي أبقت وقت التثبيت الأول الأصلي) ⇒ **أُزيل التطبيق وأُعيد تثبيته** بين 2026-11-01 و2026-11-04 (غير مسجّل هنا)، فبيانات الهاتف الحالية تبدأ من 2026-11-04. **`lastUpdateTime` = 2026-11-08 00:14:49 (+04).**

**هوية الـ APK:** SHA-256 على الجهاز = SHA-256 النسخة المسحوبة = **`eb57404122ab70037e24b9ddaeff4016a5340b1a2f24320ee28f459aacacfec1`** (231,601,957 بايت) = **مطابق بايتياً** لـ `build\app\outputs\flutter-apk\app-debug.apk` على هذا الحاسوب (بُني 2026-11-07 16:09:38 +04). الشهادة (`apksigner --print-certs`): `CN=Android Debug`، SHA-256 **`6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61`** = شهادة debug المحلية (`~/.android/debug.keystore`) ⇒ أي بناء debug/profile من هذا الحاسوب **يطابق** توقيع المثبَّت.

**المراجعة المصدرية (فحص ثابت للنسخة المسحوبة؛ قيم منطقية فقط؛ لا قيم إعداد):** نواة debug تضمّ مصادر Dart حرفياً. **كل ملفات `lib/` المترجمة فيها (461) مطابقة بايتياً لـ `e8162a9`** (`security(media): exclude private media metadata from backups`، 2026-11-07 15:57:42 +04 — قبل البناء بـ 12 دقيقة)؛ 0 ملف مختلف، 0 مكتبة إضافية (مقارنة لا تتأثر بحالة `Views`/`views`)؛ 27 ملفاً في الشجرة غير مستورد فلم يُترجم. الجاران يختلفان: `45fa169` (2 مختلفان + 1 إضافي) و`2ee9585` (3 مختلفة). قواعد النسخ الاحتياطي المترجمة: `libCachedImageData.db` موجود (e8162a9)، `bwPrivateMedia.db` غائب (2ee9585). **الحكم:** شيفرة Dart في التطبيق المثبَّت = `e8162a9` **مُثبتة بالمحتوى**؛ لا معرّف commit مضمَّن، والأجزاء الأصلية (Gradle/plugins) لم تُقارن بايتياً — لكن `pubspec.yaml`/`pubspec.lock`/`android/` لم تتغير بين `e8162a9` وHEAD إلا قاعدتا النسخ الاحتياطي.

**الميزات على الهاتف:** **موجودة:** القوائم المشفّرة P2 (+HMAC)، المفضلة المشفّرة (`bcf4b9a`)، Search local-first (`f14f3e6`)، قائمة عروض الأسعار المشفّرة (`a5b6ff9`)، خزنة PDF (`45fa169`)، استثناءات M0.5 (`e8162a9`). **غائبة:** M1b (`2ee9585`)، M1c (`7edee16`)، M1d-1 (`a665814`)، M1d-2 (`45b275e`)، DA-MAP-1 (`b02039e`)، M2-1 (`45d51b0`).

**تقييم الترقية إلى HEAD (قراءة فقط):**
1. **التوقيع:** يطابق (الشهادة نفسها) ⇒ `adb install -r` تحديث في المكان **ممكن تقنياً**؛ `versionCode` 1 = 1 ⇒ ليس تخفيضاً؛ لا splits؛ لا مالك تحديث.
2. **جلسة A:** تبقى (UID وتخزين آمن واحد)، والإقلاع البارد لا يطالب (H-M2-1a) — **مشروط** بعدم ظهور شاشة الدخول.
3. **القوائم المشفّرة/Keystore:** صيغتها لم تتغير منذ `e8162a9` (M2-1 لا يحفظ شيئاً) ⇒ تُقرأ كما هي.
4. **الترحيلات المتراكمة (أضيق مما خُشي في H-M2-1a):** فقط سلسلة الوسائط M1b→M2-1 (12 ملف `lib/`، +1,644/−100): أول تشغيل ينشئ الكاش الخاص `bwPrivateMedia`، ويتبنّى الصور القديمة عند العرض (M1d-1، نسخ)، ويبدّل `url_mapping` بمقارنة-وتبديل مع `::previous-copy` (M1d-2)، ويفعّل حارس DA-MAP-1، ويضيف تضمين M2-1. كلها **CODE_PROVEN — REAL_DEVICE_UNVERIFIED** ⇒ فحص H4 هو أيضاً **أول تشغيل جهاز** لهذه السلسلة على بيانات A الحقيقية.
5. **APK الرجوع:** **متوفر الآن ومُتحقَّق** — النسخة المسحوبة (`eb574041…`، الشهادة نفسها، versionCode 1) = ما يعمل اليوم بالضبط. **توافق البيانات عند الرجوع = PLAUSIBLE بقراءة المصدر، غير مُتحقَّق على الجهاز:** قارئ `e8162a9` يعامل قيم `url_mapping` كمسارات ملفات ويفحص وجودها (`File(...).existsSync()`) ويتجاهل مفاتيح `::previous-copy` وقاعدة `bwPrivateMedia.db`؛ أسوأ المتوقع صور تحتاج تنزيلاً online من جديد، لا فقدان قوائم.

**حدود نسخة الـ APK:** **شيفرة التطبيق فقط** — لا جلسة ولا توكنات ولا مفاتيح Keystore ولا قوائم مشفّرة ولا وسائط ولا مستندات Toolkit ولا طوابير رفع؛ **ليست نسخة احتياطية لبيانات المستخدم**. محفوظة معزولة في مساحة الجلسة المؤقتة (`…\scratchpad\h1_apk_20261109\installed_base.apk` + `kernel_blob.bin` المستخرج + XML النسخ الاحتياطي)، لم تُرفع ولم تُنشر؛ مجلد مؤقت قد يُمسح ⇒ يُنسخ إلى مكان دائم بموافقة المالك قبل H3 لو اعتُمد للرجوع.

**ما لم يُنفَّذ:** لا تثبيت/تحديث/إزالة/تشغيل/إيقاف قسري؛ لا بيانات تطبيق؛ لا logcat؛ لا SQL ولا طلب مستضاف؛ لا بناء.

**شروط تمنع H2/H3 (تُفحص من جديد قبلهما):** تغيّر SHA-256 أو الشهادة أو `versionCode` على الهاتف عن أعلاه؛ ظهور splits أو مالك تحديث؛ غياب نسخة رجوع دائمة مُتحقَّقة (`eb574041…`)؛ عدم قبول المالك صراحةً أن H4 هو أول تشغيل جهاز لـ M1b→M2-1؛ طابور رفع معلّق مجهول (يُستأنف عند أي إقلاع).

**الحالة:** **H1 = DONE؛ التطبيق المثبَّت = Dart `e8162a9` (CONTENT-PROVEN)، شهادة debug مطابقة، الرجوع متوفر (توافق البيانات PLAUSIBLE).** **H-M2-1 = BLOCKING — PARTIAL (P-0 فقط).** P4.3-ACCEPT-NONEMPTY وD-57 وكل البنود المفتوحة باقية؛ M2-2/M2-3 NOT STARTED. **NEXT (بموافقة منفصلة):** H2 = بناء `flutter build apk --debug` على `45d51b0` (لا `flutter run`/`flutter install`) + `apksigner` + حفظ دائم لنسخة الرجوع. **STOP.**

##### H-M2-1 H2 — حفظ APK الرجوع وبناء APK التشخيص — 2026-11-09 — **DONE (لا تثبيت؛ الهاتف لم يُلمس)**

**Git:** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes محفوظة؛ قبل البناء: التغيير الوحيد = هذا المتتبّع (لا تغيير في `lib/` و`android/` و`ios/` و`pubspec.*`). بعد البناء: ملفات plugin الثلاثة المولَّدة (`macos/Flutter/GeneratedPluginRegistrant.swift`، `windows/flutter/generated_plugin_registrant.cc`، `windows/flutter/generated_plugins.cmake`) تظهر معدّلة — الفخ المعروف؛ لم تُلمس ولم تُدرج.

**1) الرجوع أولاً (قبل أي Flutter/Gradle):** نسخة H1 المسحوبة (`…\scratchpad\h1_apk_20261109\installed_base.apk`) تحققت SHA-256 الكاملة = `eb57404122ab70037e24b9ddaeff4016a5340b1a2f24320ee28f459aacacfec1`، ونُسخت إلى **`C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__e8162a9__installed-on-samsung__debug__eb574041.apk`** (231,601,957 بايت؛ SHA-256 النسخة مطابقة؛ **للقراءة فقط**). المجلد داخل ملف المستخدم، خارج المستودع و`build\` والمجلدات المؤقتة، و**ليس** تحت OneDrive (مجلد Documents مُعاد توجيهه إلى OneDrive فاستُبعد لتجنّب رفع سحابي). فيه `MANIFEST.txt` و`SHA256SUMS.txt` (هويات وبصمات فقط، لا أسرار). **نسخة شيفرة فقط — ليست نسخة بيانات** (لا جلسة/مفاتيح Keystore/قوائم مشفّرة/وسائط/مستندات Toolkit).

**2) سلامة البناء:** القرص C: **10.0 GB حرة** قبل البناء (235.7 GB إجمالاً) و**9.5 GB** بعده — هامش ضيق، كافٍ لبناء debug تزايدي؛ Flutter 3.47.2 stable (Dart 3.13.2)؛ `applicationId` `com.example.broker_wallet`، `version: 1.0.0+1`، لا `key.properties` (debug يُوقَّع بـ `~/.android/debug.keystore`). لا `flutter clean`.

**3) البناء:** `flutter build apk --debug` على `45d51b0` ⇒ **exit 0**، 232 ث (2026-11-09 23:11:44–23:15:36 +04؛ Gradle `assembleDebug` 218.5 ث)؛ التحذيرات الوحيدة: إشعارات Flutter المعروفة لترقية AGP 8.11.1 وKotlin 2.2.20 مستقبلاً. لا `flutter run`/`flutter install`/أي adb.

**4) التحقق من الـ APK الجديد:** `build\app\outputs\flutter-apk\app-debug.apk`، 275,963,041 بايت، SHA-256 **`2e86b1231ff14117d7beba8d041642c4dfe4a4fa2fd908a17b051c97215fcdaf`**؛ `aapt2 dump badging`: `package: name='com.example.broker_wallet' versionCode='1' versionName='1.0.0'`، `targetSdkVersion 35`، `application-debuggable`، ABIs `arm64-v8a armeabi-v7a x86_64`؛ `apksigner verify`: **Verifies**، مخطط v2، موقِّع واحد `CN=Android Debug`، SHA-256 الشهادة `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` = **شهادة المثبَّت على Samsung**؛ مصادر Dart المضمّنة: **464 ملف `lib/` مترجم مطابقة بايتياً لـ `45d51b0`**، 0 مختلف، 0 مكتبة إضافية. **مقارنة المحتوى مع APK الرجوع:** 3 مدخلات فقط تختلف (غير مضغوطة: `kernel_blob.bin` +107,384 B، `data_extraction_rules.xml` +912 B، `backup_rules.xml` +512 B)؛ كل المكتبات الأصلية وبقية الأصول بالحجم نفسه (لم تُجزَّأ بصمتها) ⇒ فرق حجم الملف (+44 MB) تغليف/ضغط لا محتوى. نسخة دائمة: **`C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__45d51b0__M2-1-diagnostic__debug__2e86b123.apk`** (SHA-256 مطابقة، **للقراءة فقط**، ملف منفصل؛ نسخة الرجوع أُعيد فحصها بعد ذلك: سليمة). (أول محاولة نسخ في السكربت فشلت بخطأ ربط نص قبل أي كتابة؛ لا ملفات شاردة.)

**حدود:** توافق التوقيع والإصدار **لا يثبت** سلامة الترحيلات ولا الرجوع؛ لم يُشغَّل الـ APK في أي مكان؛ بايتات المكتبات الأصلية لم تُقارن؛ `build\…\app-debug.apk` لم يعد مطابقاً للمثبَّت (النسخة الدائمة هي المرجع).

**مخاطر H3 (قراءة فقط):**
- **التوافق:** نفس الحزمة والشهادة و`versionCode` 1 (ليس تخفيضاً)، لا splits، لا مالك تحديث (H1) ⇒ `adb install -r` **متوقع** أن ينجح كتحديث في المكان يحفظ البيانات؛ أي `INSTALL_FAILED_*` ⇒ STOP (لا إزالة).
- **جلسة A:** تبقى؛ الإقلاع البارد `initialSession`/`tokenRefreshed` ⇒ `is_current_app_session` (قراءة)، لا مطالبة. ظهور شاشة الدخول ⇒ STOP.
- **أول تشغيل لسلسلة الوسائط M1b→M2-1** على بيانات A: إنشاء `bwPrivateMedia`، تبنّي صور قديمة عند العرض (M1d-1)، تبديل `url_mapping` مع `::previous-copy` (M1d-2)، حارس DA-MAP-1، تضمين M2-1 — **REAL_DEVICE_UNVERIFIED**.
- **القوائم المشفّرة ومستندات عروض الأسعار:** صيغتها وخزنة PDF لم تتغير بين `e8162a9` و`45d51b0` (لا تغيير في ملفاتها) ⇒ تُقرأ كما هي.
- **طوابير الرفع:** أي عنصر معلّق يُستأنف عند الإقلاع (سلوك قائم، لا من M2-1) ⇒ كتابة مستضافة محتملة؛ يُستحسن أن يؤكد المالك عدم وجود رفع معلّق قبل H3.
- **الرجوع:** ممكن تقنياً بـ `adb install -r` لنسخة `eb574041…` (الشهادة نفسها، versionCode 1). **توافق البيانات بعد الرجوع = UNVERIFIED** (PLAUSIBLE بقراءة المصدر: قارئ `e8162a9` يعامل قيم `url_mapping` كمسارات ملفات بفحص وجود، ويتجاهل مفاتيح `::previous-copy` و`bwPrivateMedia.db`) ⇒ معناه: قد تحتاج صور تنزيلاً online من جديد بعد الرجوع، والملفات/المفاتيح الإضافية تبقى يتيمة؛ لم يُختبر.

**خطوات H3 المقترحة (كلها بموافقة صريحة منفصلة):** (1) قبول المالك أن H4 = أول تشغيل جهاز لـ M1b→M2-1، وتأكيد لا رفع معلّق؛ (2) قبل التثبيت (قراءة): `adb devices`، `getprop ro.serialno`، SHA-256 للمثبَّت = `eb574041…`، `dumpsys package` (versionCode 1، الشهادة)، الشاشة مستيقظة وغير مقفلة؛ (3) **`adb -s R5CY10YYLSM install -r "C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__45d51b0__M2-1-diagnostic__debug__2e86b123.apk"`** — لا `-d`، لا `flutter run`/`install`؛ (4) بعده (قراءة): SHA-256 على الهاتف = `2e86b123…`، `firstInstallTime` = 2026-11-04 13:38:12 بلا تغيير، `lastUpdateTime` جديد؛ (5) **لا تشغيل** حتى يفتح المالك التطبيق بنفسه في H4.

**الحالة:** **H2 = DONE (APK الرجوع محفوظ ومُتحقَّق؛ APK التشخيص `2e86b123…` مبني ومُتحقَّق؛ غير مثبَّت).** **H-M2-1 = BLOCKING — PARTIAL (P-0 فقط).** P4.3-ACCEPT-NONEMPTY وD-57 وM2-2/M2-3/M3 وكل البنود المفتوحة باقية. **NEXT:** موافقة المالك على H3. **STOP.**

##### H-M2-1 H3 — تثبيت التشخيص في المكان — 2026-11-09 — **DONE (Success؛ لا تشغيل)**

**Git:** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes محفوظة؛ المعدّل: هذا المتتبّع + ملفات plugin الثلاثة المولَّدة (لم تُلمس ولم تُدرج).

**الفحص المسبق (قراءة فقط، 23:2x +04):** (1) جهاز واحد مخوَّل SM-S928B؛ (2) `ro.serialno` = المعتمد؛ (3) مسار APK واحد، SHA-256 على الهاتف = `eb574041…acfec1` (= H1)؛ (4) `versionCode` 1، `versionName` 1.0.0، التوقيع `7b4386ef` كما في H1، لا `updateOwner`؛ شهادة APK التشخيص = `6dcf852d…9ef39f61`؛ (5) النسختان المحفوظتان: SHA-256 مطابقة، وكلتاهما للقراءة فقط؛ (6) **التخزين:** `/data` 460G، مستخدم 372G، **متاح 88G** (81%)؛ **البطارية:** 92%، تشحن عبر USB (`status 2`)، `health 2` (جيدة)، 32.4°C؛ (7) الشاشة `Awake`، `isKeyguardShowing=false`، **التطبيق غير مشغَّل** (لا عملية). (8–10) **أكد المالك صراحةً** (2026-11-09): لا رفع ولا عملية محلية مهمة معلّقة؛ APK القديم شيفرة فقط وليس نسخة بيانات؛ توافق البيانات بعد الرجوع UNVERIFIED.

**التثبيت (مرة واحدة، بلا إعادة):** `adb -s R5CY10YYLSM install -r "C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__45d51b0__M2-1-diagnostic__debug__2e86b123.apk"` ⇒ `Performing Streamed Install` → **`Success`**، exit 0، 23:25:37–23:26:03 +04 (26 ث). لا أعلام أخرى؛ لا `flutter run/install`، لا إزالة، لا `pm clear`، لا `am start/force-stop`.

**بعد التثبيت (قراءة فقط):** الحزمة مثبتة؛ **مسار APK واحد** (مسار `/data/app` جديد كما يحدث في كل تحديث)، بلا splits؛ SHA-256 على الهاتف **و**للنسخة المسحوبة = **`2e86b1231ff14117d7beba8d041642c4dfe4a4fa2fd908a17b051c97215fcdaf`**؛ الشهادة `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` (`CN=Android Debug`)؛ `versionCode` 1، `versionName` 1.0.0؛ التوقيع `7b4386ef` بلا تغيير؛ الأعلام نفسها (`DEBUGGABLE`…)؛ **`firstInstallTime` = 2026-11-04 13:38:12 بلا تغيير**، `lastUpdateTime` = 2026-11-09 23:26:03؛ `initiatingPackageName=com.android.shell`؛ **المستخدم 0: `ceDataInode=2948116` و`deDataInode=2945000` مطابقان لما قبل التثبيت (H1)** ⇒ مجلدا البيانات لم يُعادا إنشاؤهما ⇒ **تحديث في المكان مؤكَّد ولا مسح للبيانات**؛ التطبيق لم يُشغَّل (لا عملية).

**ملاحظة غير متوقعة — المستخدم 95:** بعد التثبيت أصبح `User 95: installed=true` (ملف Samsung الثاني، على الأرجح Dual Messenger) بمجلدات بيانات جديدة، `stopped=true notLaunched=true`؛ في H1 كان `installed=false`. السبب: `adb install -r` بلا `--user` يثبّت لكل المستخدمين، بينما تثبيت 2026-11-04 من WhatsApp كان للمستخدم 0 فقط (وفي 2026-10-31 §7G كانت الحزمة موجودة للمستخدمين 0 و95). نسخة مستقلة فارغة لم تُشغَّل، بلا جلسة، لا تشارك بيانات المستخدم 0. **لم تُلمس**؛ إزالتها (`pm uninstall --user 95`) تغيير حالة حزمة يحتاج موافقة منفصلة. للمستقبل: إضافة `--user 0` للتثبيتات (بموافقة).

**حدود دليل حفظ البيانات:** الإينودات ووقت التثبيت الأول تثبت أن مجلدات البيانات لم تُحذف/تُنشأ من جديد — **لا** تثبت سلامة كل ملف خاص أو قائمة مشفّرة أو مفتاح Keystore أو الجلسة؛ لم يُقرأ أي من بيانات التطبيق (ممنوع). يظهر ذلك فقط عند فتح المالك التطبيق (H4).

**المخاطر الباقية:** أول تشغيل (H4) = **أول تشغيل جهاز** لسلسلة M1b→M2-1 على بيانات A (إنشاء `bwPrivateMedia`، تبنّي M1d-1، تبديل M1d-2، حارس DA-MAP-1، تضمين M2-1) — REAL_DEVICE_UNVERIFIED؛ طابور رفع متبقٍّ يُستأنف (المالك أكد لا شيء مهم معلّق)؛ ظهور شاشة الدخول ⇒ STOP بلا تسجيل دخول. **الرجوع:** APK `eb574041…` محفوظ وسليم؛ الرجوع (`adb install -r`، ويستحسن `--user 0`) **يحتاج موافقة منفصلة**؛ توافق البيانات بعد تشغيل الترحيلات الجديدة **UNVERIFIED**؛ لا إزالة أبداً.

**الحالة:** **H3 = DONE — تحديث في المكان مؤكَّد (Success؛ SHA-256 `2e86b123…` على الهاتف؛ الشهادة نفسها؛ مجلدات بيانات المستخدم 0 نفسها)؛ التطبيق لم يُشغَّل.** **H4 = جاهز للتنفيذ بيد المالك بموافقة منفصلة** (الخطوات في H-M2-1a/H4). **H-M2-1 = BLOCKING — PARTIAL (P-0 فقط).** P4.3-ACCEPT-NONEMPTY منفصل ومفتوح؛ D-57، M2-2، M2-3، M3 وكل البنود الأمنية ووسائط offline المفتوحة باقية. **STOP.**

##### H-M2-1 H4 — قبول المالك على Samsung مستضافاً (جلسة A القائمة، المستخدم 0) — 2026-11-09 — **PASS ضمن النطاق المختبَر**

**قبل البدء (قراءة فقط):** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes؛ الهاتف متصل؛ SHA-256 المثبَّت (المستخدم 0) = `2e86b123…15fcdaf`؛ التطبيق لم يكن مشغَّلاً. ملاحظات المالك سُجّلت كإجابات PASS/FAIL فقط (لا لقطات، لا بيانات عملاء، لا logcat تطبيق).

**المرحلة 1 — الإقلاع الأول (المالك، الملف الرئيسي، online):** **PASS** — فُتح بلا انهيار، **بلا شاشة دخول**، Home ظهر ببيانات A كما قبل، لا خطأ ولا تحذير سلامة ولا بيانات فارغة. العملية تعمل كـ `u0_a1692` (المستخدم 0) ⇒ **جلسة A القائمة محفوظة** (لا تسجيل دخول ⇒ لا `claim_current_app_session`).

**المرحلتان 2–3 — القوائم online (سحب للتحديث مرة):** **Offers: PASS** و**Owners: PASS** — السجلات القائمة ظهرت، اكتمل التحديث، **لا خطأ تحميل/PostgREST**؛ أقل من 10 سجلات في كل قائمة؛ سجل واحد على الأقل **بلا صور ما زال مُدرجاً**.

**المرحلة 4 — التفاصيل والمعرض:** Offer بصور: **PASS** (النص والمعرض، العارض بملء الشاشة والعودة، وعند إعادة الفتح ظهرت الصور **بلا إعادة تحميل ظاهرة**)؛ Owner بصور: **PASS** (المثل)؛ Offer بلا صور: **PASS** (فُتح عادياً)؛ Owner بلا صور: **PASS**.

**فحص لاحق (قراءة فقط):** SHA-256 المثبَّت ما زال `2e86b123…`؛ المستخدم 0 `ceDataInode=2948116`/`deDataInode=2945000` بلا تغيير؛ **0** سطر في مخزن الانهيارات (`logcat -b crash`، عدّ فقط) يذكر الحزمة منذ التثبيت.

**حادث المستخدم 95 (غير متوقع):** بعد المرحلة 1 ظهرت عملية ثانية `u95_a1692` و`User 95: stopped=false notLaunched=false` ⇒ نسخة الملف الثاني (Dual Messenger) **شُغّلت**. **المالك:** فُتحت **بالخطأ**، **بلا تسجيل دخول** ⇒ لا جلسة جديدة ولا مطالبة. **بعدها أكد المالك** أن التطبيق الرئيسي ما زال على حساب A ببياناته **بلا رسالة إزاحة جلسة**. لم تُلمس النسخة (لا إيقاف قسري ولا إزالة). **متابعة مستقلة (FU-H3-USER95، بموافقة منفصلة، لا تُخلط بالقبول):** تنظيف آمن للحساب لنسخة المستخدم 95 — مثلاً `adb -s R5CY10YYLSM uninstall --user 95 com.example.broker_wallet` (يمس المستخدم 95 فقط؛ يُتحقق قبله وبعده أن المستخدم 0 مثبَّت وبنفس الإينودات)؛ وحتى ذلك: **لا تسجيل دخول في نسخة الملف الثاني أبداً** (= مطالبة تزيح الهاتف). للمستقبل: `--user 0` في كل تثبيت.

**ما تحقق مستضافاً (جلسة A المصرَّح بها، صفوف A فقط):** قبِل PostgREST المستضاف **مصادَقاً** استعلامات M2-1 المضمّنة لقوائم Offers وOwners (صفحة واحدة، < 500) ولقراءات تفاصيل Offer/Owner الوصفية؛ السجلات الأب عُرضت؛ **السجل بلا وسائط بقي** (التضمين العادي لا يُسقط الأب) — مُلاحَظ؛ صلاحيات `authenticated` على `offer_media`/`owner_media`/`media_objects` و`app_session_gate` لم ترفض قراءة A ⇒ **يزيل خطر الـ 400 الذي وُجد H-M2-1 لأجله**، ضمن هذا النطاق.

**ما بقي غير مُتحقَّق:** صحة المعرّفات وترتيبها `ordinal` ومرشح `ready`/الأنواع على الصفوف المستضافة (M2-1 لا يعرض `listedMediaObjectIds`؛ المعرض يأتي من روابط الـ Worker) ⇒ يحتاج **H4b** (تشخيص debug مؤقت، بموافقة منفصلة)؛ حدود 500 صف (< 10 سجلات) ⇒ **P4.3-ACCEPT-NONEMPTY منفصل ومفتوح**؛ عزل RLS بين الحسابات وسلوك الجلسة المُزاحة (حساب A وحده)؛ قراءات المفضلة بالمعرّفات (لم تُختبر صراحةً)؛ الأداء على الجهاز (لا قياس)؛ عدد الطلبات على الجهاز.

**سلوك الوسائط الأول على الجهاز (M1b→M2-1):** أول تشغيل لم يُظهر خطأ؛ المعارض عُرضت، والعارض بملء الشاشة عمل، وإعادة الفتح بلا إعادة تحميل ظاهرة (متسق مع الكاش الخاص/تبنّي M1d-1، **ملاحظة بصرية فقط**؛ لم يُقرأ أي ملف كاش ولم يُقس شيء) ⇒ M1b/M1c/M1d-1/M1d-2 = **REAL_DEVICE_SMOKE_PASS (owner-observed)**، لا تحقق كامل (offline، الإخلاء، Delete Account، DA-MAP-1، حالات الحواف تبقى مفتوحة).

**الحالة:** **H4 = PASS (owner-run، ضمن النطاق المختبَر).** **H-M2-1 = PARTIAL — حاجز الـ 400 مُزال لصفوف A** (P-0 + H4)؛ **إغلاقه قرار المالك**: مقترح «إغلاق الحاجز للإطلاق مع إبقاء H4b (هوية/ترتيب)، الحدود، والعزل بين الحسابات مفتوحة»؛ حتى قرار المالك يبقى **BLOCKING**. P4.3-ACCEPT-NONEMPTY، D-57، D-DAM-4/5، مسارات iOS، التلف بنفس الحجم، M2-2، M2-3، M3، M1d-3، M4/M5، Smart Map، Toolkit، الإخفاقات التاريخية — **مفتوحة**؛ FU-H3-USER95 **جديد ومفتوح**. **STOP:** لا H4b ولا M2-2/M2-3/M3.

##### H-M2-1 H4b — تصميم التحقق المستضاف من هوية الوسائط — 2026-11-09 (تصميم فقط؛ لا كود؛ لا APK؛ لا وصول للهاتف)

**قرار المالك:** «KEEP BLOCKING, DO H4b». **Git:** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes؛ المعدّل: هذا المتتبّع + ملفات plugin الثلاثة المولَّدة (لم تُلمس). C: 9.1 GB حرة.

**H4 — ما تحقق (PASSED ضمن نطاقه، يبقى كما هو):** جلسة A القائمة نجت؛ Home فُتح؛ قائمتا Offers/Owners online بلا خطأ؛ السجلات بلا صور بقيت؛ تفاصيل Offer/Owner ومعارضها فُتحت؛ تنفيذ استعلامات M2-1 المستضافة نجح لسجلات A المختبرة؛ لا خطأ علاقة PostgREST.

**المرحلة 1 — مقارنة العقد (قراءة مصدر):** الـ Worker (`handleMediaList`): `assertOwnsParent` ← روابط الأب `order=ordinal.asc` ← يُبقي `status='ready'` و`bucket` المتوقع و`object_key` المتوقع للأب ← `mediaObjectId=media_objects.id`، مع `role` و`ordinal`؛ **لا مرشح نوع صريح** (يفترض نوعاً معروفاً: `OFFER_MEDIA_TYPES[type].mediaType` يرمي لنوع مجهول ⇒ فشل القائمة كلها)، **لا إزالة تكرار**، **لا كسر تعادل**. العميل (`_readyMediaIds`): UUID قانوني، `ordinal ≥ 0`، `ready`، نوع ضمن 7 أنواع، إزالة تكرار، ترتيب `ordinal` ثم المعرّف؛ **لا** فحص `bucket`/`object_key` ولا ملكية الأب (RLS + `app_session_gate` تغطيها لنفس الحساب). **قيود المخطط:** `primary key (parent, media_id)` ⇒ **التكرار مستحيل**؛ `unique (parent, role, ordinal)` + `ordinal ≥ 0`؛ الكاتب الوحيد للروابط (RPC التأكيد، service-role) يكتب `role='gallery'` دائماً ⇒ ordinals فريدة لكل أب عملياً ⇒ ترتيب الـ Worker = ترتيب العميل (إلا لصفوف قديمة بدور آخر — **غير معروف مستضافاً**)؛ `media_objects.content_type` **بلا قيد CHECK** ⇒ نوع غير مدرج ممكن نظرياً (العميل يُسقطه، الـ Worker يفشل). **الفروق الحقيقية الممكنة بين القائمتين:** (أ) رابط `ready` بـ `bucket`/`object_key` غير متوقع ⇒ عند العميل لا عند الـ Worker؛ (ب) نوع غير مدرج ⇒ الـ Worker يفشل؛ (ج) أدوار غير `gallery` بنفس `ordinal` ⇒ ترتيب قد يختلف.

**ما يدعمه H4 فعلاً وما لا يدعمه:** H4 يثبت تنفيذ الاستعلام وعرض الأب وبقاء السجل بلا وسائط ونجاح المعرض (المعرض من الـ Worker). **لا** يثبت شيئاً عن قيم `listedMediaObjectIds` (لا تُعرض ولا تُحفظ في M2-1) ⇒ **غير مُتحقَّق مستضافاً:** (1) صحة UUID للقيم الفعلية، (2) ارتباطها بالأب الصحيح، (3) الترتيب، (4) مرشح `ready`/النوع على صفوف فعلية (وهل مُورس أصلاً)، (5) التكرار (مستحيل بالمخطط — يُؤكد فقط)، (6) السجل بلا وسائط ⇒ `[]`، (7) الفروق (أ)–(ج)، (8) خلو الحقل من روابط/مسارات (القيم UUID فقط بالبناء — يُؤكد على القيم الفعلية).

**المرحلة 2 — أصغر تصميم آمن (H4b-D، يحتاج APK جديداً):**
- **التعديل (مؤقت، لا يُودَع، ملف واحد):** `lib/src/services/supabase_core_entities_service.dart` فقط، محمي بـ `kDebugMode && const bool.fromEnvironment('BW_H4B_DIAG')` (صفر أثر في أي بناء آخر). (i) في `_offerFromRow`/`_ownerFromRow`: حفظ في **ذاكرة فقط** (`Map` ثابتة) لكل أب: `listedMediaObjectIds` + عدّادات الإدخال الخام من `_readyMediaIds` (روابط خام، غير `ready`، نوع غير مدرج، UUID غير قانوني، ordinal سالب/مفقود، مكرر) + مصدر الصف (قائمة/تفاصيل/بالمعرّفات). (ii) في `_resolveRecordMedia` بعد استجابة Worker ناجحة لنفس الأب ونفس الحساب: مقارنة معرّفات الـ Worker (بترتيبها) مع آخر `listedMediaObjectIds` للأب، وطباعة **سطر تجميعي واحد** عبر `debugPrint`: `H4B kind=offer rec=#3 src=list listed=3 worker=3 sameSet=true sameOrder=true uuidOk=true raw=4 notReady=1 badType=0 badUuid=0 badOrdinal=0 dup=0 listedOnly=0 workerOnly=0 workerOrdinalsIncreasing=true workerRolesGallery=true`. `rec=#k` رقم تسلسلي للجلسة (**لا معرّف سجل ولا وسائط**)؛ لا روابط ولا مفاتيح ولا قيم. **صفر طلبات إضافية** (يستعمل قراءات القائمة/التفاصيل ونداء الـ Worker القائم عند فتح التفاصيل)؛ لا كتابة ولا حفظ.
- **البناء:** `flutter build apk --debug --dart-define=BW_H4B_DIAG=true` على `45d51b0` + الرقعة (مطبّقة بـ `git apply` من ملف في المساحة المؤقتة، تُعكس بعد البناء بـ `git apply -R`، والتحقق أن الملف = blob HEAD؛ لا reset). تحقق `apksigner`/الحزمة/versionCode كما في H2؛ حفظ دائم للقراءة فقط في `BrokerWallet-Artifacts\H-M2-1\`.
- **التثبيت:** `adb -s R5CY10YYLSM install -r --user 0 <diag-apk>` (فحوص H3 قبل/بعد: الإينودات، `firstInstallTime`). ملاحظة: شيفرة APK مشتركة بين المستخدمين، فنسخة المستخدم 95 ستحمل الشيفرة نفسها لو شُغّلت — **لا تُفتح**.
- **التنفيذ (المالك):** فتح التطبيق من الملف الرئيسي online، ثم فتح **تفاصيل كل** Offer وكل Owner (أقل من 10 لكل منهما) مرة واحدة، دون تعديل.
- **الاستخراج (قراءة فقط):** `adb -s R5CY10YYLSM shell "logcat -d | grep 'H4B '"` — الترشيح **على الجهاز** فلا يغادر سوى الأسطر التجميعية؛ لا logcat كامل.
- **الإعادة:** تثبيت APK `45d51b0` النظيف المحفوظ (`2e86b123…`) بـ `install -r --user 0` لإزالة شيفرة التشخيص (نفس الشيفرة دون تسجيل؛ التشخيص لا يحفظ شيئاً ⇒ آمن بالتصميم)، ثم فحوص H3 اللاحقة.
- **البدائل المرفوضة:** (ب) خدمة Dart VM لبناء debug القائم (`flutter attach` + تقييم تعابير) — وصول اعتباطي لذاكرة التطبيق بما فيها التوكنات، أوسع بكثير من المطلوب؛ (ج) SQL مميّز/service_role — يستبدل سلوك التطبيق المصادَق (ممنوع)؛ (د) طلبات بتوكن A مستخرج — ممنوع؛ (هـ) جلسة A ثانية — تزيح الهاتف.

**المرحلة 3 — حدود القبول:** تنفيذ الاستعلام = **PASSED (H4)**؛ صحة المعرّفات وارتباطها بالأب = **H4b** (`sameSet` لكل سجل)؛ الترتيب = **H4b** (`sameOrder`)؛ مرشح ready/النوع = **H4b** (مُورس فقط إن `notReady`/`badType` > 0؛ وإلا «لم يُمارَس على صفوف A» مع `sameSet`)؛ السجل بلا وسائط = **H4b** (`listed=0 worker=0`)؛ تفويض الحساب ضمن الجلسة = مغطى بـ H4 + H4b لصفوف A فقط؛ **العزل بين الحسابات = NOT VERIFIED** (لا حساب ثانٍ مخوَّل)؛ **حدود 500 صف = NOT VERIFIED** (< 10 سجلات)؛ **الأداء = غير مُثبت** (ملاحظة بصرية فقط). **PASS لـ H4b:** كل سطر `sameSet=true sameOrder=true uuidOk=true dup=0`، وكل سجل فُتح له سطر، والسجلات بلا وسائط `listed=0 worker=0`. **فرق مُفسَّر (PARTIAL):** `listedOnly>0` مع سبب (أ) — يُقرر المالك هل يتبنى M2-2 فحص الموقع. **FAIL:** أي `sameSet=false` غير مفسَّر، `uuidOk=false`، `dup>0`، أو `sameOrder=false` لأدوار `gallery` فقط.

**المخاطر وحماية البيانات:** تثبيتان إضافيان في المكان (تشخيص ثم نظيف) بالضمانات نفسها لـ H3 (نفس الشهادة/versionCode؛ فشل ⇒ STOP بلا إزالة)؛ لا ترحيلات جديدة (التشخيص = HEAD + تسجيل في الذاكرة)؛ جلسة A كما في H4 (إقلاع بارد لا يطالب)؛ السطور التجميعية لا تحوي معرّفات ولا بيانات عملاء؛ logcat يُرشَّح على الجهاز؛ الرقعة لا تُودَع ولا تبقى في الشجرة؛ القرص 9.1 GB (بناء debug تزايدي يكفي). يبقى: أول تشغيل جهاز للسلسلة قد تم في H4 بلا خطأ؛ نسخة المستخدم 95 لا تُفتح (FU-H3-USER95 مستقل).

**الموافقات المطلوبة (منفصلة، بالترتيب):** (1) كتابة الرقعة المؤقتة للتشخيص ومراجعتها (بلا إيداع)؛ (2) بناء APK التشخيص بالـ dart-define وحفظه؛ (3) تثبيته في المكان بـ `--user 0`؛ (4) تشغيل المالك وفتح تفاصيل كل السجلات + قراءة أسطر `H4B` المرشَّحة؛ (5) إعادة تثبيت APK `45d51b0` النظيف. يمكن دمج (1)+(2) في موافقة واحدة و(3)+(4)+(5) في أخرى إن رغب المالك.

**الحالة:** **H4 = PASSED (ضمن نطاقه)؛ H4b = DESIGN READY — NOT RUN؛ H-M2-1 = PARTIAL — BLOCKING** حتى تقييم عقد الهوية وموافقة المالك على قرار الإطلاق. P4.3-ACCEPT-NONEMPTY منفصل ومفتوح؛ FU-H3-USER95 مفتوح ومستقل؛ M2-2، M2-3، M3، M1d-3، M4/M5، D-57، D-DAM-4/5، الإخفاقات التاريخية، Smart Map، Toolkit — **مفتوحة**. **STOP.**

##### H-M2-1 H4b الخطوتان 1–2 — رقعة التشخيص المؤقتة وبناء APK — 2026-11-10 — **DONE (لا تثبيت؛ الهاتف لم يُلمس)**

**Git:** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes محفوظة. قبل البدء حُفظت نسخة بايتية من `lib/src/services/supabase_core_entities_service.dart` (blob `ea6db19…` = HEAD، SHA-256 `146ad128…0f63`). **بعد البناء أُعيد الملف بايتياً** (blob = HEAD، SHA-256 = الأصل) وأُزيل ملف الاختبار المؤقت ⇒ الشجرة الآن: هذا المتتبّع + ملفات plugin الثلاثة المولَّدة فقط (لم تُلمس ولم تُدرج). **لا commit.**

**الرقعة (مؤقتة، ملف إنتاج واحد، +256/−2):** صنف `H4bMediaIdentityDiagnostic` في نهاية الملف + ثلاث نقاط استدعاء: (1) `_offerFromRow`/`_ownerFromRow`: `listedMediaObjectIds: _listedIds(kind, row, link)` = `_readyMediaIds(...)` نفسه + `noteListed` (القيمة المعادة **مطابقة** لما قبل)؛ (2) `_resolveRecordMedia`: `noteWorkerFailed` في فرعي الفشل وفي فحص تغيّر الحساب، و`noteWorker` بعد نجاح الـ Worker لنفس الأب/الحساب، **قبل** المسار القائم دون تغييره؛ (3) `_rawLinkCounts` يعدّ ما أسقطه المرشح بأول فحص يفشل (`notMap/badUuid/badOrdinal/noMediaRow/notReady/badType/dup`). **البوابة:** `debugEnabledOverride ?? (kDebugMode && const bool.fromEnvironment('BW_H4B_DIAG'))` — كل نداء يعود فوراً إن لم تتحقق؛ release/profile: `kDebugMode=false`. كل جسم ملفوف بـ `try/catch` لا يؤثر على القراءة. الحالة **في الذاكرة فقط** (مفاتيح `kind|owner|record`)؛ لا تخزين.

**دلالات المقارنة:** لكل سجل فُتحت وسائطه: `result=PASS` فقط إن رُئي صف PostgREST للسجل **و**احتوى التضمين (`embed=present`) **و**نجح الـ Worker **و**`sameSet` (مجموعتان متساويتان بلا تكرار) **و**`sameOrder` (المعرّفات بالترتيب نفسه موضعاً بموضع) **و**`uuidOk` للطرفين و`workerDup=0`؛ `MISMATCH` غير ذلك مع `listedOnly/workerOnly/workerNonGallery/workerOrdinalsIncreasing` و`hint` (`worker-only` | `listed-only-check-storage-location` | `legacy-role-order` | `unexplained`)؛ `NO_LISTED` إن لم يُرَ صف (`embed=unseen`) أو غاب التضمين (`embed=absent`)؛ `WORKER_FAILED` عند أي فشل للـ Worker (بلا رسالة الخطأ). صفر/صفر = `PASS listed=0 worker=0` («صفر مُتحقَّق»: PostgREST يؤكد غياب الروابط مستقلاً). صف لاحق (تفاصيل) يُقارن من جديد مع آخر إجابة Worker (`trigger=row`)؛ السطر المكرر لا يُطبع ثانيةً. **حد معروف:** عميل الـ Worker يُسقط بصمت مدخلاً بلا معرّف/رابط، ويعيد `[]` لجسم 200 بلا `media` — فلا يُميَّز عن الفراغ في هذه الطبقة؛ لكنه لا يُنتج PASS كاذباً إلا حين يؤكد PostgREST أيضاً الصفر. **الخصوصية:** السطر `H4B kind=… rec=#n …` — أعداد وقيم منطقية ورقم تسلسلي للتشغيل فقط؛ لا معرّف حساب/سجل/وسائط، لا رابط، لا مفتاح، لا مسار، لا رسالة استثناء.

**الاختبارات (ملف مؤقت `test/lists/h4b_media_identity_diagnostic_test.dart`، أُزيل من المستودع بعد البناء؛ نسخة مراجعة محفوظة):** كُتبت أولاً وفشلت (الصنف غير موجود)، ثم **30/30 PASS** (لـ Offers وOwners): البوابة (جدول الحقيقة؛ معطلة في الاختبار دون define)؛ العلم مطفأ ⇒ لا سطر، نفس المعرّفات، **لا حالة في الذاكرة** (`debugTrackedRecords=0`)؛ تطابق ⇒ PASS؛ نفس المجموعة بترتيب مختلف ⇒ MISMATCH `sameOrder=false`؛ دور قديم بنفس ordinal ⇒ `hint=legacy-role-order`؛ ناقص/زائد ⇒ `listedOnly`/`workerOnly`؛ صفر/صفر ⇒ PASS؛ عدّادات الخام الثمانية؛ فشل Worker (HTTP 500 واستثناء يحوي رابطاً) ⇒ `WORKER_FAILED` ولا PASS، والاستدعاء ما زال يفشل كما قبل؛ لا صف ⇒ `NO_LISTED unseen`؛ صف بلا تضمين ⇒ `NO_LISTED absent`؛ إعادة المقارنة عند صف لاحق ومرة واحدة؛ حساب آخر ⇒ `StateError` كما قبل، لا سطر، لا نداء Worker؛ **لا معرّف/رابط/`/`/`http`/`sig` في أي سطر** (نمط مسموح صارم)؛ **عدد طلبات PostgREST والـ Worker ومعرّفات المعرض والمعرّفات المدرجة متطابقة مع العلم وبدونه**. **طفرات: 7/7 قُتلت** (البوابة `||`، PASS يتجاهل الترتيب، إسقاط ملاحظة فشل HTTP، غياب التضمين كحضور، إلغاء منع التكرار، إزالة فحص `enabled` — قُتلت بعد إضافة `debugTrackedRecords`، عدم عدّ `dup`)؛ الملف أُعيد مطابقاً بعد كل طفرة. **انحدار مركّز:** 7 ملفات (التشخيص، M2-1 list ids، منسّق تحميل التفاصيل، تفويض وسائط Offer، الكاش الخاص، هوية كاش الوسائط، وسائط Owner) **160/160 PASS**. `flutter analyze` (الملفان): **No issues**؛ `dart format` للملف الجديد نظيف، وللملف القائم: صفر فرق تنسيق (سطران من أسطري أُصلحا يدوياً)؛ `git diff --check` نظيف؛ CRLF موحّد.

**البناء:** C: 9.0 GB حرة قبل، 8.4 GB بعد؛ النسختان المحفوظتان تحققتا (SHA-256، للقراءة فقط) قبل البناء. `flutter build apk --debug --dart-define=BW_H4B_DIAG=true` ⇒ **exit 0**، 84 ث (00:19:10–00:20:34 +04). **APK:** 275,983,550 بايت، SHA-256 **`fcfcb7cd6d69eea3f638abf6bbfdaa93db436d4936bf0ef3770998186b9bfe4a`**؛ `com.example.broker_wallet` versionCode 1 versionName 1.0.0، debuggable، `targetSdk` 35؛ الشهادة `6dcf852de490e490e37237e9d7e37885bd8e5bc482a83d3a34b939289ef39f61` (= المثبَّت والنسختين). **هوية الشيفرة:** 463 ملف `lib/` مطابقة بايتياً لـ `45d51b0`، وملف واحد مختلف = الخدمة **المرقّعة مطابقة بايتياً**؛ الصنف التشخيصي **موجود في هذا الـ APK فقط** (غائب عن APK `45d51b0` النظيف `2e86b123…`، الذي يحوي الخدمة الأصلية بايتياً). قيمة الـ define لا تُقرأ من الثنائي ⇒ تفعيلها يُثبت عند أول سطر `H4B` في التشغيل. نسخة دائمة للقراءة فقط: **`C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__45d51b0+H4b-patch__H4B-DIAG-debug__fcfcb7cd.apk`**؛ `SHA256SUMS.txt` و`MANIFEST.txt` محدّثان؛ مراجعة المصدر في `…\H-M2-1\H4b-diagnostic-source\` (الرقعة، الاختبار، الملف المرقّع). **تنبيه تسمية:** الملف `…45d51b0__M2-1-diagnostic…2e86b123.apk` هو بناء M2-1 **النظيف** (بلا H4b) — مرجع الإعادة.

**المخاطر الباقية (أمن/خصوصية):** APK debug يطبع عبر `debugPrint` إلى logcat — أسطر تجميعية فقط، لكن logcat يحوي أيضاً سجلات التطبيق العادية ⇒ الاستخراج **مرشَّح على الجهاز** (`adb shell "logcat -d | grep 'H4B '"`) فقط؛ الـ APK التشخيصي **يجب ألا يبقى** على الهاتف بعد H4b (إعادة `2e86b123…`)؛ لا طلب إضافي ولا كتابة؛ لا ترحيل جديد. **المستخدم 95:** في نموذج حِزم Android لكل حزمة مسار شيفرة واحد مشترك بين المستخدمين المثبَّتة لهم؛ تحديث `install -r --user 0` لحزمة مثبتة أصلاً للمستخدم 95 **يُتوقع** أن يستبدل شيفرتها لديه أيضاً (غير مُتحقَّق على هذا الجهاز) ⇒ **لا يُدّعى أن `--user 0` يعزل الشيفرة**؛ يُتحقق قراءةً بعد التثبيت بـ `pm path --user 95` وSHA-256؛ نسخة 95 لا تُفتح؛ FU-H3-USER95 مستقل.

**الموافقة المطلوبة للخطوة التالية (H4b-3..5، منفصلة):** (3) فحوص H3 المسبقة + `adb -s R5CY10YYLSM install -r --user 0 "C:\Users\xr343\BrokerWallet-Artifacts\H-M2-1\com.example.broker_wallet__45d51b0+H4b-patch__H4B-DIAG-debug__fcfcb7cd.apk"` + فحوص لاحقة (SHA-256 `fcfcb7cd…`، الإينودات، `firstInstallTime`، `pm path --user 95`)؛ (4) المالك يفتح التطبيق (الملف الرئيسي) online ويفتح **تفاصيل كل** Offer وOwner مرة دون تعديل، ثم استخراج `H4B` المرشَّح على الجهاز؛ (5) **إعادة** APK `45d51b0` النظيف (`…2e86b123.apk`) بـ `install -r --user 0` + فحوص لاحقة. لا رجوع لـ `e8162a9` ضمنها.

**الحالة:** **H4b-1/2 = DONE (رقعة مؤقتة مُختبرة 30/30 + 7/7 طفرات، APK `fcfcb7cd…` مبني ومُتحقَّق ومحفوظ؛ المصدر أُعيد إلى HEAD).** **H4 = PASSED (ضمن نطاقه)؛ H-M2-1 = PARTIAL — BLOCKING.** P4.3-ACCEPT-NONEMPTY، FU-H3-USER95، M2-2، M2-3، M3، M1d-3، M4/M5، D-57، D-DAM-4/5، الإخفاقات التاريخية، Smart Map، Toolkit — **مفتوحة**. **STOP.**

##### H-M2-1 H4b الخطوات 3–5 — التحقق المستضاف من هوية الوسائط وإعادة APK النظيف — 2026-11-10 — **H4b = PASS (كل سجلات A: 7 Offers + 2 Owners)**

**Git/المصدر:** HEAD `45d51b0` = `origin`؛ الفهرس فارغ؛ أربعة stashes؛ الخدمة = blob HEAD (الرقعة غير موجودة في الشجرة)؛ المعدّل: هذا المتتبّع + ملفات plugin الثلاثة فقط. النسخ الثلاث المحفوظة: SHA-256 مطابقة وللقراءة فقط (`eb574041…`، `2e86b123…`، `fcfcb7cd…`)؛ شهادة APK التشخيص = `6dcf852d…9ef39f61`.

**الفحص المسبق (قراءة فقط):** جهاز SM-S928B (`R5CY…LSM`؛ متصل بـ USB وبالتصحيح اللاسلكي معاً — استُعمل رقم USB التسلسلي وحده)؛ المثبَّت للمستخدم 0 = النظيف `2e86b123…`، versionCode 1، التوقيع `7b4386ef`؛ إينودات المستخدم 0 `2948116/2945000`؛ التخزين 87G متاحة؛ البطارية 55% تشحن USB، `health 2`، 37.8°C؛ الشاشة Awake وغير مقفلة؛ التطبيق غير مشغَّل. **تغيّر منذ H4: المستخدم 95 `installed=false` وإينوداته `-1`** — **أكد المالك أنه أزالها بنفسه** (لم يُلمس من هنا). **بوابات المالك:** لا رفع ولا عمل غير محفوظ؛ جلسة A في الملف الرئيسي هي الوحيدة المقصودة.

**الخطوة 3 — تثبيت التشخيص (مرة واحدة):** علامة بدء السجل = epoch الجهاز `1794309545`؛ `adb -s R5CY10YYLSM install -r --user 0 "…\com.example.broker_wallet__45d51b0+H4b-patch__H4B-DIAG-debug__fcfcb7cd.apk"` ⇒ **`Success`**، exit 0 (15:19:04–15:19:29). بعده: مسار واحد، SHA-256 على الهاتف = `fcfcb7cd…`، versionCode 1، التوقيع نفسه، **إينودات المستخدم 0 و`firstInstallTime` (2026-11-04 13:38:12) بلا تغيير**، `lastUpdateTime` 15:19:30؛ المستخدم 95 ما زال `installed=false` (لم يُضِف `--user 0` شيئاً له)؛ لا عملية.

**الخطوة 4 — تشغيل المالك:** فتح المالك التطبيق من الملف الرئيسي online (بلا تسجيل دخول) وفتح تفاصيل **كل** Offer و**كل** Owner مرة دون تعديل. **الاستخراج:** `adb shell "logcat -d -T '<marker>.000' | grep 'H4B '"` (مرشَّح على الجهاز) ⇒ **9 أسطر تشخيص** بوسم `I flutter` + أسطر صدى من `adbd` لأوامر grep نفسها (ليست من التطبيق، لا بيانات)؛ لا نص شبيه بـ UUID؛ آخر سطر تشخيص 15:21:32. **التغطية:** أكد المالك أن القائمتين = **7 Offers و2 Owners** ⇒ **9/9 سجلات** لها سطر (`rec=#1..#9`). **وجود التشخيص مُفعَّلاً** مُثبت بالأسطر نفسها.

| النوع | السجلات | النتيجة | الوسائط (listed=worker) |
|---|---|---|---|
| Offer | #1–#4، #7 | **PASS** ×5 | 0=0 (**صفر مُتحقَّق**، `raw=0`) |
| Offer | #5، #6 | **PASS** ×2 | 10=10 (الحد الأقصى MAX_MEDIA) |
| Owner | #8 | **PASS** | 1=1 |
| Owner | #9 | **PASS** | 2=2 |

كل الأسطر: `embed=present sameSet=true sameOrder=true uuidOk=true listedOnly=0 workerOnly=0 workerDup=0 workerNonGallery=0 workerOrdinalsIncreasing=true hint=none`؛ عدّادات الخام كلها 0 (`notMap/badUuid/badOrdinal/noMediaRow/notReady/badType/dup`) و`raw` = `listed` لكل سجل. **لا** `MISMATCH` ولا `WORKER_FAILED` ولا `NO_LISTED`.

**التصنيف:** (1) صحة المعرّفات وارتباطها بالأب: **VERIFIED_HOSTED** لكل سجلات A (مجموعتان متطابقتان مع قائمة الـ Worker التي تتحقق من ملكية الأب والحاوية ومفتاح الكائن)؛ (2) الترتيب: **VERIFIED_HOSTED** موضعاً بموضع (بما فيه سجلان بـ 10 وسائط)، ordinals الـ Worker متزايدة وكل الأدوار `gallery`؛ (3) مرشح `ready`/النوع: **مُتسق لكنه لم يُمارَس** — لا روابط غير `ready` ولا نوع غير مدرج في صفوف A (`notReady=badType=0`)؛ منطقه مُثبت بالاختبارات فقط؛ (4) التكرار: 0 (والمخطط يمنعه)؛ (5) السجل بلا وسائط: **VERIFIED (Offers ×5)**؛ **لا Owner بلا صور موجود** ⇒ صفر Owner **NOT TESTED** (**تصحيح لـ H4:** إجابة «Owner بلا صور فُتح عادياً» في H4 لا تطابق البيانات — السجلان لديهما صور)؛ (6) فروق الـ Worker/العميل: فرق الموقع (أ)، النوع (ب)، الدور القديم (ج) **لم يظهر أي منها** في بيانات A؛ (7) فشل الـ Worker/غياب PostgREST لا يُحسبان PASS: مُثبت بالاختبارات، ولم يحدث في التشغيل؛ (8) لا طلب إضافي: **مُثبت بالاختبارات** (عدّ متطابق)، **غير مُقاس على الجهاز**؛ لا كتابة مستضافة من التشخيص (لا كود كتابة فيه)؛ لا انهيار (`logcat -b crash`: 0).

**الخطوة 5 — إعادة APK النظيف:** `adb -s R5CY10YYLSM install -r --user 0 "…\com.example.broker_wallet__45d51b0__M2-1-diagnostic__debug__2e86b123.apk"` ⇒ **`Success`**، exit 0 (15:23:09–15:23:37). بعده: مسار واحد؛ SHA-256 على الهاتف **وللنسخة المسحوبة** = `2e86b123…`؛ الشهادة `6dcf852d…9ef39f61`؛ versionCode 1/versionName 1.0.0؛ التوقيع `7b4386ef`؛ **إينودات المستخدم 0 و`firstInstallTime` بلا تغيير**؛ `lastUpdateTime` 15:23:37؛ المستخدم 95 `installed=false`؛ 0 سطر انهيار؛ بعد فتح المالك للتطبيق: عملية `u0_a1692` فقط، والبناء النظيف **لا يطبع أي سطر H4B**. **المالك:** على حساب A، Home والقائمتان بالبيانات نفسها والصور تظهر، **بلا رسالة جلسة ولا خطأ** ⇒ **جلسة A محفوظة**. APK التشخيص **لم يعد مثبتاً**.

**المستخدم 95:** أزال المالك نسخة الملف الثاني بنفسه قبل H4b؛ لم تُشغَّل ولم تُلمس من هنا؛ تحديثات `--user 0` لم تُعِدها ⇒ **FU-H3-USER95 = RESOLVED BY OWNER** (يُتحقق في أي تثبيت مستقبلي بـ `--user 0` و`dumpsys`).

**حالة H-M2-1 (للمالك):** معايير القبول المعتمدة لعقد الهوية **مدعومة لصفوف A**: تنفيذ الاستعلام المستضاف (P-0 + H4)، عرض الأب، الصفر لـ Offers، صحة المعرّفات وترتيبها مقابل الـ Worker (H4b 9/9). **يبقى غير مُتحقَّق:** حدود 500 صف (A < 10 سجلات ⇒ **P4.3-ACCEPT-NONEMPTY منفصل ومفتوح**)؛ العزل بين الحسابات وسلوك الجلسة المُزاحة مستضافاً (لا حساب ثانٍ مخوَّل)؛ ممارسة مرشح `ready`/النوع على صفوف فعلية؛ صفر Owner؛ قراءات المفضلة بالمعرّفات؛ الأداء وعدد الطلبات على الجهاز. **المقترح:** رفع حاجز H-M2-1 لعقد الهوية (يسمح ببدء M2-2 بعد موافقة المالك)، مع إبقاء البنود أعلاه مفتوحة كمتابعات منفصلة؛ **القرار للمالك — حتى ذلك H-M2-1 = PARTIAL — BLOCKING.**

**الحالة:** **H4b = PASS (9/9، كل سجلات A)؛ APK النظيف مُعاد ومُتحقَّق؛ جلسة A محفوظة؛ FU-H3-USER95 = RESOLVED BY OWNER.** P4.3-ACCEPT-NONEMPTY، M2-2، M2-3، M3، M1d-3، M4/M5، D-57، D-DAM-4/5، مسارات iOS، التلف بنفس الحجم، الإخفاقات التاريخية، Smart Map، Toolkit — **مفتوحة**. **STOP:** لا M2-2/M2-3/M3.

##### H-M2-1 — قرار القبول النهائي للمالك — 2026-11-10 — **ACCEPTED / RELEASE GATE LIFTED (ضمن نطاق عقد هوية الوسائط المستضاف المختبَر)**

**القرار (المالك):** رفع حاجز إطلاق H-M2-1 **لعقد هوية الوسائط المستضاف المحدَّد في M2-1** الذي أثبته H4 وH4b. **ليس** موافقة على إطلاق إنتاج عام.

**النطاق المقبول:** استعلامات Offers/Owners المستضافة بتضمين M2-1 نُفِّذت تحت جلسة A القائمة (P-0 + H4)؛ جلسة A بقيت سليمة؛ فُحص 7 Offers و2 Owners على Samsung؛ أنتجت السجلات التسعة كلها مقارنة H4b صالحة؛ محتوى معرّفات الوسائط وترتيبها `ordinal` طابقا الـ Worker في كل سجل مختبَر؛ Offers بلا وسائط أعادت فراغاً متطابقاً؛ لا `MISMATCH` ولا `WORKER_FAILED` ولا `NO_LISTED`؛ APK التشخيص أُزيل باستبدال في المكان بالـ APK النظيف؛ `45d51b0` النظيف مُعاد على Samsung؛ مصدر التشخيص أُعيد بايتياً إلى HEAD.

**الحالة:** **H-M2-1 = ACCEPTED / RELEASE GATE LIFTED** ضمن النطاق المختبَر. **M2-1 = CODE_PROVEN + قبول مستضاف مصادَق لسجلات A المختبرة** (ليس REAL_DEVICE_VERIFIED شاملاً، وليس إطلاقاً). **FU-H3-USER95 = RESOLVED** — فقط للتنظيف الذي أكده المالك وتُحقق منه قراءةً (`User 95: installed=false`، إينودات `-1`، ولم يُعِده أي تثبيت `--user 0` لاحق).

**بنود مفتوحة منفصلة (محفوظة):**
1. **P4.3-ACCEPT-NONEMPTY** وحدود 500 صف (A < 10 سجلات).
2. **RLS بين الحسابات** وقبول **الجلسة المُزاحة** مستضافاً (لا حساب ثانٍ مخوَّل).
3. **مرشح `ready`/النوع السلبي مستضافاً** (لم يُمارَس: لا روابط غير `ready` ولا نوع غير مدرج في صفوف A).
4. **سيناريو Owner بلا وسائط** (لا Owner بلا صور في بيانات A؛ تصحيح H4 مسجَّل في H4b 3–5).
5. **قراءات المفضلة بالمعرّفات** مستضافاً.
6. **عدد الطلبات والذاكرة والأداء على الجهاز** (غير مُقاس).
7. **D-57** — قبول Samsung/iOS الموحّد.
8. كل مشكلات **Auth/Delete Account** التاريخية.
9. **D-DAM-4/5**، قابلية نقل مسارات **iOS**، اكتشاف **التلف بنفس الحجم**.
10. **M3**، **M1d-3**، **M4**، **M5**، **Smart Map**، **Toolkit**.

**المرحلة التالية:** **M2-2** (تخزين مشفّر لمعرّفات وسائط Offer/Owner الموثوقة) **مؤهَّلة للبدء بعد إيداع هذا الـ checkpoint التوثيقي ودفعه** — **NOT STARTED**؛ M2-3 وM3 **NOT STARTED**. **NOW:** موافقة المالك على commit التوثيق. **STOP.**

---

## 8) مراجع الاستمرار

- `AGENTS.md` (القيود الملزمة للمشروع).
- `CLAUDE.md` (traps المتعلقة بالـ format وCRLF وSupabase Auth event streams وأوامر Flutter).
- `docs/CURRENT_CHECKPOINT.md` (مرجع كل milestones الحية داخل الفرع، بعد التحقق من Git).
- `docs/DECISIONS.md` (القرارات المعمارية والأمنية).
- `BROKER_WALLET_MASTER_CONTEXT_PRO_PLUS_UPDATED_2026-10-31.md` (سياق محمول؛ مرحلة Firebase النهائية صاحبها تقرير المالك).
- `BROKER_WALLET_FINAL_PRODUCTION_CHECKLIST_UPDATED_2026-10-31.md` (حواجز إطلاق مستقلة).
- `App_Startup_Launch_Guide_English_Updated_12_Videos.pdf` (Video 03 cache / Video 12 N+1؛ دليل تعليم لا يحل محل القياس).

**قاعدة ختامية:** لا نعتمد تغييرات لمجرد أن الفكرة تبدو أسرع؛ القبول يحتاج دليلاً، والحد الأدنى من التعديل، وحفظ الأمان والسلوك، وموافقة صاحب المنتج بين المراحل.

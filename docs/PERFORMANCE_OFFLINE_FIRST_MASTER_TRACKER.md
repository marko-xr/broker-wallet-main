# BROKER WALLET — PERFORMANCE + OFFLINE-FIRST MASTER TRACKER

**الإصدار:** 1.3 — 2026-10-31 (تصحيح توقف P1.1-a + تسليم وثيقة قابلة للإيداع؛ لا توجد قياسات جديدة)  
**طبيعة الملف:** سجل تنفيذ ومراجعة محمول، يُحدّث في كل handoff. ليس إثباتاً بأن الأعمال المستقبلية قد نُفذت.  
**المسار المقترح داخل المستودع:** `docs/PERFORMANCE_OFFLINE_FIRST_MASTER_TRACKER.md` (المالك يطلب الآن تحديثه؛ يمكن لوكيل البرمجة إنشاؤه/تحديثه كتغيير توثيقي محصور بعد التحقق من الفرع وعدم الكتابة فوق عمل قائم بلا مراجعة).  
**الفرع المستهدف:** `perf/phase-1-startup-baseline` — أبلغ Claude بأنه تحقق منه من checkout الحي في 2026-10-31 15:42 +04؛ **دليل مقدم من المالك، ولم نتحقق منه مباشرة من Git هنا**. ZIP لا يحتوي `.git`.  
**المرحلة النشطة:** `P1 — Startup & Initial Screen Performance`؛ `P1.0` مراجعة مصدر فقط؛ `P1.1-a` **PAUSED BY PROCESS / NOT RUN** بعد تشديد التعليمات، وليس بسبب فشل تقني مثبت. `P1.1-b` **NOT APPROVED**. لا بناء ولا تثبيت ولا benchmark مثبت بهذه النسخة.  
**حالة المشروع:** PRE-PUBLIC-RELEASE؛ الأداء وOffline-First لا يغلقان بنود إطلاق المتاجر #8–#52.
**نسخة المستودع:** أُنشئ هذا الملف في المستودع بتاريخ 2026-10-31 19:06 +04 من النسخة المحمولة 1.3 دون تغيير محتواها السابق؛ أحدث حالة مُتحقَّق منها مباشرة من Git والجهاز في §7D–§7N (آخر تحديث 2026-11-01، P2.1).

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
| `P2` | Smart Local Caching & Background Refresh | `IN PROGRESS` — P2.1 (قراءة Requests offline) CODE_PROVEN، غير مدمج (§7M) | عرض آمن للكاش، تحديث صريح، عزل الحسابات، offline/refresh/empty/error tests. |
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

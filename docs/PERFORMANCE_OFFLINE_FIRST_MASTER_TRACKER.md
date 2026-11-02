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

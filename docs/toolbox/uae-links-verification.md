# UAE Useful Links: verification register

Maintained register for `UAELinksData` (`lib/src/data/models/uae_links_catalogue.dart`). Toolbox S5.
Verification date: **2026-10-19**. Every status below comes from an actual check on that date; nothing is assumed.

## Method and limits

- **HTTP fetch + title**: GET with redirects followed (max 8), 20 s timeout, one request every ~0.5 s, no login, no CAPTCHA bypass. The status is only a first signal: the page title or heading was read and matched to the service name (a 404 can come back as a full HTML page).
- **Browser render**: the page was opened in a real browser and its rendered content read. Used where the page is script-only or blocks automated requests.
- **VERIFIED_OFFICIAL**: authority, URL and page content all observed and consistent. It is not awarded for a `.gov.ae` domain or an HTTP 200 alone.
- **OFFICIAL_MANUAL_CHECK_REQUIRED**: authority and URL established but the destination could not be fully confirmed (login wall, script-only page, unread PDF, unresolved platform ownership). The app tells the user to check the details on the official site.
- **Not tested anywhere**: authenticated transactions, UAE PASS sign-in, payments, uploads. "Requires sign-in" means the official page asks for it.
- Bot blocking (HTTP 403) was not treated as proof a site is down.

## Summary

- Active entries: **97** (89 VERIFIED_OFFICIAL, 8 OFFICIAL_MANUAL_CHECK_REQUIRED).
- Live check of all 97 catalogue URLs on 2026-10-19: 94 returned HTTP 200 on the bounded pass; DEWA (2) returned 403 to automated requests (read in a browser); `www.digitaluaq.ae` timed out once and then returned 200 on three retries.
- One catalogue address (`mun.rak.ae/?page_id=620`) redirected; the canonical target is listed instead.

## Entries

### UAE-wide

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `uae-uae-pass` | UAE PASS | UAE PASS (UAE national digital identity) | <https://www.uaepass.ae/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `uae-leasing-guide` | Leasing a property in the UAE (guide) | UAE Government Portal (u.ae) | <https://u.ae/en/information-and-services/moving-to-the-uae/leasing-a-property-in-the-uae> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `uae-housing-guide` | Housing and property (guide) | UAE Government Portal (u.ae) | <https://u.ae/en/information-and-services/housing> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `uae-legislation` | UAE Legislation portal | UAE Federal Government | <https://www.uaelegislation.gov.ae/en> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | The bare domain without `www` did not respond. |

### Dubai

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `dubai-dld-home` | Dubai Land Department | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-dld-services` | DLD e-services directory | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/all-services/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-ejari-register-renew` | Register or renew a tenancy contract (Ejari) | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/register-renew-ejari-contract/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `dubai-ejari-cancel` | Cancel a tenancy contract (Ejari) | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/cancel-tenancy-contract/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `dubai-ejari-certificate` | Download the rental certificate (Ejari) | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/download-ejari-certificate/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-rental-index` | Rental Index | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/rental-index/rental-index/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-title-deed-verification` | Verify a title deed | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/title-deed-verification-overview/title-deed-verification/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-property-status` | Property status enquiry | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/property-status-overview/property-status/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-real-estate-ad-permit` | Real estate advertising permit (Trakheesi) | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/real-estate-ad-permit/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Old `request-a-real-estate-permit` address redirected here. "Trakheesi" is a common name; the DLD page is titled "Real Estate Ad Permit". Page asks for sign-in. |
| `dubai-validate-licences-permits` | Verify real estate licences and permits | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/validate-real-estate-licenses-and-permits/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-licensed-brokerages` | Licensed real estate brokerage companies | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/licensed-real-estate-brokers-offices/licensed-real-estate-brokers-offices-list/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-licensed-brokers` | Licensed real estate brokers | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/licensed-real-estate-brokers/licensed-real-estate-brokers-list/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-broker-ecard` | E-card verification | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/validate-e-card-overview/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-project-status` | Project status enquiry | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/real-estate-project-status-landing/real-estate-project-status/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-licensed-developers` | Licensed developers | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/approved-real-estate-developers/approved-developers/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-escrow-trustees` | Approved escrow account trustees | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/certified-escrow-agents/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-oqood` | Oqood: off-plan sales registration | Dubai Land Department (DLD) | <https://oqood.dubailand.gov.ae/> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Redirects to the Arabic My DLD sign-in (`dubailand.gov.ae/ar/MyDLD/#/login`); the DLD e-services page lists Oqood as a My DLD application. Sign-in not tested. Page asks for sign-in. |
| `dubai-mollak` | Mollak: jointly owned property | Dubai Land Department (DLD) | <https://mollak.dubailand.gov.ae/publicpages/home.html> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | The root address redirects by script to `home.html`. |
| `dubai-service-charge-index` | Service charge index | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/service-charge-index-overview/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-property-sale-registration` | Property sale registration | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/property-sale-registration/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-rest` | Dubai REST app | Dubai Land Department (DLD) | <https://dubailand.gov.ae/en/eservices/dubai-rest/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `dubai-rental-disputes-centre` | Rental Disputes Centre | Rental Disputes Centre, Dubai | <https://rdc.gov.ae/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `dubai-noqodi` | Noqodi payment platform | Noqodi (payment platform used by DLD) | <https://www.noqodi.com/> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Payment platform. The DLD site links to Noqodi payment support; platform ownership not established. |
| `dubai-dewa-move-in` | DEWA: activate electricity and water (move-in) | Dubai Electricity and Water Authority (DEWA) | <https://www.dewa.gov.ae/en/consumer/supply-management/activation-of-electricity-water-move-in> | VERIFIED_OFFICIAL | Browser render; HTTP 403 | Automated requests get HTTP 403 (bot block, not proof of failure); read in a browser. Page asks for sign-in. |
| `dubai-dewa-move-out` | DEWA: deactivate electricity and water (move-out) | Dubai Electricity and Water Authority (DEWA) | <https://www.dewa.gov.ae/en/consumer/supply-management/deactivation-of-electricity-water-move-out> | VERIFIED_OFFICIAL | Browser render; HTTP 403 | Automated requests get HTTP 403 (bot block, not proof of failure); read in a browser. Page asks for sign-in. |

### Abu Dhabi

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `abudhabi-adrec-home` | Abu Dhabi Real Estate Centre | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-adrec-services` | ADREC services | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/services> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Catalogue is script-rendered; a plain download shows only the frame. |
| `abudhabi-verify-document` | Verify an ADREC document | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/verify-document> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-market-data` | Abu Dhabi market data and indices | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/property_and_index> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-laws` | Abu Dhabi real estate laws and regulations | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/rules_and_regulations> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-dispute-settlement-centre` | Real Estate Dispute Settlement Centre (Taswea) | Abu Dhabi Real Estate Centre (ADREC) | <https://adrec.gov.ae/en/adrec-drc> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-tamm` | TAMM: Abu Dhabi Government Services | Abu Dhabi Government (TAMM) | <https://www.tamm.abudhabi/> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Script-rendered; a plain download shows an empty frame. |
| `abudhabi-dari-home` | DARI: Abu Dhabi real-estate platform | Abu Dhabi Real Estate Centre (ADREC) | <https://www.dari.ae/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-dari-services` | DARI service directory | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/services/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `abudhabi-tawtheeq-register` | Register a lease contract (Tawtheeq) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/tenancy-contract-registration/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-tawtheeq-renew` | Renew a lease contract (Tawtheeq) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/tenancy-contract-renewal-2/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-tawtheeq-cancel` | Cancel a lease contract (Tawtheeq) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/tenancy-contract-cancellation/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-sale-registration` | Register the sale of land or real estate | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/consumer-services/registration-of-sale-and-purchase-of-land-and-real-estate/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-ownership-certificate` | Property ownership certificate | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/certificate-of-owned-properties/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-valuation-certificate` | Property valuation certificate | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/business-services/request-a-valuation-certificate/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-mortgage-registration` | Register a unit mortgage | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/register-unit-mortgage/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-broker-company-licence` | Brokerage company licence (issue or renew) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/developers/register-broker-company-2/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-broker-individual-licence` | Individual broker licence (issue or renew) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/developers/register-broker-individual/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-madhmoun-permit` | Madhmoun: issue a listing advertisement permit | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/madhmoun-en/request-permit-to-advertise-on-websites-2/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-madhmoun-renew` | Madhmoun: renew a listing advertisement permit | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/madhmoun-en/renew-permit-to-advertise-on-website/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-offplan-first-sale` | Register a unit for first sale (off-plan) | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/business-services/request-to-register-a-unit-for-first-sale/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-offplan-ad-permit` | Off-plan sale advertisement permit | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/company-services/property-management-company-services/request-an-off-plan-sale-advertisement-permit-2/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `abudhabi-developer-registration` | Real estate developer registration | Abu Dhabi Real Estate Centre (ADREC) | <https://services.dari.ae/business-services/manage-real-estate-developer-registration/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |

### Sharjah

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `sharjah-srerd-home` | Sharjah Real Estate Registration Department | Sharjah Real Estate Registration Department (SRERD) | <https://www.shjrerd.gov.ae/> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Script-only site (a plain download shows a "JavaScript required" notice); Arabic content. |
| `sharjah-srerd-services` | SRERD e-services | Sharjah Real Estate Registration Department (SRERD) | <https://www.shjrerd.gov.ae/services> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `sharjah-srerd-document-verification` | Verify a SRERD document | Sharjah Real Estate Registration Department (SRERD) | <https://www.shjrerd.gov.ae/doc-inquiry> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `sharjah-srerd-fee-calculator` | SRERD fee calculator | Sharjah Real Estate Registration Department (SRERD) | <https://www.shjrerd.gov.ae/fee-calculator> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `sharjah-srerd-projects` | Registered development projects | Sharjah Real Estate Registration Department (SRERD) | <https://www.shjrerd.gov.ae/projects> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `sharjah-srerd-gates` | SRERD portals (individuals, developers, banks) | Sharjah Real Estate Registration Department (SRERD) | <https://gates.shjrerd.gov.ae/> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Linked from the SRERD home page; opens "Login - RERD". Authenticated functions not tested. Page asks for sign-in. |
| `sharjah-digital` | Digital Sharjah (Aqari platform) | Sharjah Digital Department | <https://ds.sharjah.ae/> | OFFICIAL_MANUAL_CHECK_REQUIRED | Browser render; HTTP 200 | Home page lists Aqari; the Aqari card leads to a sign-in page. No public Aqari address could be confirmed, so none is listed. Page asks for sign-in. |
| `sharjah-municipality` | Sharjah City Municipality | Sharjah City Municipality | <https://shjmun.gov.ae/> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Old `portal.shjmun.gov.ae` home redirects here. |
| `sharjah-tenancy-contract-details` | Request tenancy contract details | Sharjah City Municipality | <https://portal.shjmun.gov.ae/en/eservices/Pages/GetTenancyContractInfo.aspx> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `sharjah-sewa-home` | SEWA: Sharjah electricity, water and gas | Sharjah Electricity, Water and Gas Authority (SEWA) | <https://www.sewa.gov.ae/en/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `sharjah-sewa-eservices` | SEWA customer e-services | Sharjah Electricity, Water and Gas Authority (SEWA) | <https://eservice.sewa.gov.ae/portal/default.aspx> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Login page. The move in / out form was not opened. Page asks for sign-in. |

### Ajman (includes the EtihadWE northern-emirates entry)

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `ajman-land-home` | Department of Land and Real Estate Regulation | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-land-services` | Land department services directory | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-land-eservices` | Land department e-services (sign-in) | Dept. of Land and Real Estate Regulation, Ajman | <https://eservices.ajmanre.gov.ae/en/> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Script-only page; sign-in not tested. Page asks for sign-in. |
| `ajman-sale-registration` | Sale registration of a property or unit | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/sale-registration-of-a-real-estate-real-estate-unit/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-long-term-lease` | Register a long-term lease contract | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/registration-of-a-long-term-lease/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | The old `/our-services/` address redirected to this URL. |
| `ajman-office-registration` | Real estate office registration certificate | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/issuance-of-a-real-estate-office-registration-certificate/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-practice-card` | Real estate activity practice card | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/issuance-of-a-real-estate-activity-practice-card/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-ad-permit` | Real estate advertising permit | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/real-estate-advertisement-permission-real-estate-advertisements-plan/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-valuation` | Real estate valuation | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/real-estate-valuation/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-project-registration` | Real estate project registration | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/real-estate-project-registration/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-dispute-resolution` | Apply to resolve a real estate dispute | Dept. of Land and Real Estate Regulation, Ajman | <https://ajmanre.gov.ae/en/services/application-for-resolution-of-a-real-estate-dispute/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-tasdeeq-home` | Tasdeeq: lease contract attestation (Ajman) | Ajman Municipality and Planning Department | <https://tasdeeq.am.gov.ae/en/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Ajman service (footer: Municipality and Planning Department, Government of Ajman). The old directory filed it under Sharjah. |
| `ajman-tasdeeq-services` | Tasdeeq services list | Ajman Municipality and Planning Department | <https://tasdeeq.am.gov.ae/en/services.html> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `ajman-tasdeeq-residential` | Attest a residential lease contract (Tasdeeq) | Ajman Municipality and Planning Department | <https://www.am.gov.ae/en/services/authentication-of-lease-contract-for-residential-purposes/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `ajman-tasdeeq-economic` | Attest a lease contract for economic activities (Tasdeeq) | Ajman Municipality and Planning Department | <https://tasdeeq.am.gov.ae/en/service06.html> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `ajman-tasdeeq-cancel` | Cancel a lease contract (Tasdeeq) | Ajman Municipality and Planning Department | <https://tasdeeq.am.gov.ae/en/service07.html> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 | Page asks for sign-in. |
| `ajman-digital-catalogue` | Ajman government service catalogue: land and real estate | Department of Digital Ajman | <https://www.ajman.ae/en/servicecatalog/service_categories/department-land-real-estate-regulation> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `northern-etihadwe-activation` | EtihadWE: activate electricity and water | Etihad Water and Electricity (EtihadWE) | <https://www.etihadwe.ae/en/Services/eServices/Pages/Service-Activation.aspx> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Page asks for sign-in. |

### Ras Al Khaimah

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `rak-lands-properties-sector` | Lands and Properties Sector | Ras Al Khaimah Municipality | <https://mun.rak.ae/home/rak-municipality/organizational-structure/lands-properties-sector/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-real-estate-regulatory` | Real Estate Regulatory Administration | Ras Al Khaimah Municipality | <https://mun.rak.ae/home/rak-municipality/organizational-structure/lands-properties-sector/real-estate-regulatory-administration/> | VERIFIED_OFFICIAL | HTTP fetch + title | The `?page_id=620` address redirects to this canonical URL. |
| `rak-sanad-rental-affairs` | Rental affairs: service cards | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/rental-affairs> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-new-tenancy` | ZL41: new tenancy contract | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/services-card-english-temp-32> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-renew-tenancy` | ZL43: renew a tenancy contract | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/services-card-english-temp-57> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-modify-tenancy` | ZL44: modify a tenancy contract | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/services-card-english-temp-58> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-sanad-lands-properties` | Lands and properties: service cards | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/lands-and-properties> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-sale-contract` | ZL13: real estate sale contract registration | Ras Al Khaimah Municipality | <https://sanad.mun.rak.ae/docs/en/services-card-arabic-temp-28> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP 200 |  |
| `rak-digital` | RAK Digital: government e-services | RAK Digital (Ras Al Khaimah Government) | <https://rakdigital.rak.ae/index.html?sap-language=en> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | Script-only SAP page; the municipality links to it as "E-Services". Page asks for sign-in. |

### Umm Al Quwain

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `uaq-services-platform` | Umm Al Quwain services platform (Digital UAQ) | Digital UAQ (Umm Al Quwain Government) | <https://portal.uaq.ae/> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `uaq-digital-department` | Digital Umm Al Quwain | Digital UAQ (Umm Al Quwain Government) | <https://www.digitaluaq.ae/> | VERIFIED_OFFICIAL | HTTP fetch + title; HTTP timeout |  |

### Fujairah

| ID | Service | Authority | Canonical URL | Status | Method | Limits / notes |
|---|---|---|---|---|---|---|
| `fujairah-municipality` | Fujairah Municipality | Fujairah Municipality | <https://www.fujmun.gov.ae/> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |
| `fujairah-rental-services` | Rental services | Fujairah Municipality | <https://portal.fujmun.gov.ae/OnlineEServices/en/eService/ServicePages/services.aspx?RK=rental&packid=11> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Page asks for sign-in. |
| `fujairah-ejaar` | Ejaar: Fujairah tenancy system | Fujairah Municipality | <https://ejaar.fujmun.gov.ae/ejaar/pages/LoginForm> | VERIFIED_OFFICIAL | Browser render; HTTP 200 | Page asks for sign-in. |
| `fujairah-ejaar-guide` | Ejaar user guide (PDF) | Fujairah Municipality | <https://ejaar.fujmun.gov.ae/Ejaar/assets/files/EJAAR%20User%20Guide_English.pdf> | OFFICIAL_MANUAL_CHECK_REQUIRED | HTTP fetch + title; HTTP 200 | PDF (~1.2 MB) reachable; text not read, so content and date unconfirmed. |
| `fujairah-government-portal` | Fujairah Government official portal | Fujairah Government | <https://www.fujairah.ae/en/Pages/default.aspx> | VERIFIED_OFFICIAL | Browser render; HTTP 200 |  |

## Legacy links (the 25 entries of the old directory)

Outcome: **14 retained**, **8 corrected or replaced**, **3 removed**.

| Old address | Old label / emirate | Outcome | Reason |
|---|---|---|---|
| `uaepass.ae/` | UAE PASS (essentials) | Retained as `https://www.uaepass.ae/` | Same service; canonical host. |
| `noqodi.com/` | Noqodi (essentials) | Retained, moved to Dubai, relabelled a payment platform, MANUAL_CHECK | It is a payment platform used with DLD, not a regulator or department; ownership not established. |
| `dubailand.gov.ae/en/` | DLD home | Retained | Verified. |
| `.../eservices/dubai-rest/` | Dubai REST | Retained | Verified. |
| `.../eservices/rental-index-form-landing/` | RERA rental calculator | **Replaced** by `.../rental-index/rental-index/` | Old address returned "Page Not Found". The service is now the Rental Index. |
| `.../eservices/request-a-real-estate-permit/` | Advertisement permit | **Replaced** by `.../real-estate-ad-permit/` | Old address redirected to the new one. |
| `.../validate-real-estate-licenses-and-permits/` | Validate licences and permits | Retained | Verified. |
| `mollak.dubailand.gov.ae/` | Mollak | **Corrected** to `.../publicpages/home.html` | Root only redirects by script. |
| `oqood.dubailand.gov.ae/` | Oqood | Retained, MANUAL_CHECK | Official subdomain; redirects to the Arabic My DLD sign-in. |
| `rdc.gov.ae/` | Rental Disputes Center | Retained | Verified. |
| `www.dari.ae/` | DARI | Retained | Verified. |
| `services.dari.ae/services/` | DARI services | Retained | Verified. |
| `adrec.gov.ae/en` | ADREC | Retained as `/en/` | Verified. |
| `portal.shjmun.gov.ae/en/` | Sharjah municipality services | **Replaced** by `shjmun.gov.ae/` | Old address redirects to the new site. |
| `portal.shjmun.gov.ae/en/eservices/pages/services.aspx?sercatid=48` | Renew tenancy (residential) | **Removed** | Serves the same generic municipality page as the home address; no renewal service could be shown at it. |
| `portal.shjmun.gov.ae/en/eservices/Pages/GetTenancyContractInfo.aspx` | Tenancy contract details | Retained | Heading "Request for details of tenancy contract" observed. |
| `tasdeeq.am.gov.ae/en/index.html` | Tasdeeq (filed under **Sharjah**) | **Corrected**: now Ajman, `https://tasdeeq.am.gov.ae/en/` plus its service pages | Tasdeeq is run by the Ajman Municipality and Planning Department. |
| `ajmanre.gov.ae/en/` | Land department home | Retained | Verified. |
| `ajmanre.gov.ae/en/services/eservices/` | eServices portal | **Replaced** by `/en/services/` and `eservices.ajmanre.gov.ae/en/` | Old address returned "Page not found". |
| `ajmanre.gov.ae/en/our-services/registration-of-a-long-term-lease/` | Register long-term lease | **Corrected** to `/en/services/registration-of-a-long-term-lease/` | Old address redirected. |
| `ajman.ae/.../department-land-real-estate-regulation` | Service directory | Retained | Verified. |
| `rak.ae/wps/portal/rak/e-services/govt/!/z/tenancy` | Register tenancy (RAK) | **Removed** | Legacy portal; returns a generic "Rak Digital" page and no tenancy service could be shown. Replaced by the municipality's current Sanad service cards (ZL41, ZL43, ZL44) and RAK Digital. |
| `md.uaq.ae/service.php` | UAQ municipality lease services | **Removed** | No response on 2026-10-19. Replaced by the UAQ services platform. |
| `portal.fujmun.gov.ae/OnlineEservices/default.aspx?lang=en` | Fujairah municipality rental contract | **Replaced** by the rental services page and the municipality site | Generic landing; the rental services page lists the real services. |
| `ejaar.fujmun.gov.ae/.../EJAAR User Guide_English.pdf` | Ejaar user guide | Retained, MANUAL_CHECK | PDF reachable; text not read. |

## Candidates not published

| Candidate | Why it is not in the directory |
|---|---|
| Public Aqari (Sharjah) address | Digital Sharjah lists Aqari but its card leads to a sign-in page. `aqari.ae` is **not** the government site (a domain that redirects to a domain-sale listing); `aqari.shj.ae` and similar did not resolve. No address was guessed. |
| Sharjah tenancy renewal / attestation deep links | Delivered through Aqari / the municipality behind a sign-in or script-only pages; no stable public address found. The municipality home and the tenancy-details page are listed instead. |
| Dubai Municipality (planning, permits) | Home page reachable, but no real-estate-specific service page was verified. |
| UAQ Land and Property Department, UAQ municipality lease attestation | No official address could be confirmed: candidate hosts did not respond and web results were third-party blogs only. The UAQ services platform is listed so the user can search its directory. |
| TAMM deep links (Tawtheeq, property services) | TAMM is script-rendered; only the verified TAMM home and the DARI service pages are listed. |
| RAK cancellation card and the Arabic-only RAK cards (real-estate office, valuation) | Reached only through Arabic URL slugs that were not verified; the Sanad "Lands and properties" category is listed. |
| Ministry of Justice site | Returned "Request Rejected" to the automated check; relevance to brokers not established. |
| Dubai REST store listings, commercial portals (Property Finder, Bayut, Dubizzle), calculators, blogs, news articles | Out of policy: only government pages and the one labelled payment platform are listed. WAM, Gulf News and Sharjah24 were read for background only. |

## Known limits

- Only the first screen of login-walled services was read; no transaction, sign-in, payment or upload was tested.
- Fees, document lists and processing times are **not** copied into the app, because they change; the user opens the official page for them.
- EtihadWE: the site says it serves "the northern emirates"; the entry is assigned to Ajman, Ras Al Khaimah, Umm Al Quwain and Fujairah on that statement and the RAK municipality's own reference to EtihadWE. Per-emirate coverage was not confirmed.
- Sharjah Municipality and SRERD content is largely Arabic; their cards say so.

## How to re-verify

1. Re-run the bounded check over `url:` values in the catalogue (GET, follow redirects, timeout 20 s, rate-limited), then open script-only pages in a browser.
2. For a changed or moved page, update the `url`, the `lastVerified` date and the `evidence`; keep the entry's `id`.
3. If a page cannot be confirmed, downgrade to `officialManualCheckRequired` with the reason, or set `retired` (not shown) and add a row above.
4. `flutter test test/uae_links` enforces ids, domains, coverage, language completeness and verification metadata.

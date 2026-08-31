class UAELinkItem {
  final String label;
  final String url;
  final String? description;

  UAELinkItem({
    required this.label,
    required this.url,
    this.description,
  });
}

class UAELinkCategory {
  final String title;
  final List<UAELinkItem> items;

  UAELinkCategory({
    required this.title,
    required this.items,
  });
}

class UAELinksData {
  static List<UAELinkCategory> getCategories(
      String Function(String) translate) {
    return [
      UAELinkCategory(
        title: translate('uaeEssentials'),
        items: [
          UAELinkItem(
            label: translate('uaePass'),
            url: 'https://uaepass.ae/',
            description: translate('uaePassDescription'),
          ),
          UAELinkItem(
            label: translate('noqodiPayments'),
            url: 'https://www.noqodi.com/',
            description: translate('noqodiPaymentsDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('dubaiDldRera'),
        items: [
          UAELinkItem(
            label: translate('dldHome'),
            url: 'https://dubailand.gov.ae/en/',
            description: translate('dldHomeDescription'),
          ),
          UAELinkItem(
            label: translate('dubaiRest'),
            url: 'https://dubailand.gov.ae/en/eservices/dubai-rest/',
            description: translate('dubaiRestDescription'),
          ),
          UAELinkItem(
            label: translate('reraRentalCalculator'),
            url:
                'https://dubailand.gov.ae/en/eservices/rental-index-form-landing/',
            description: translate('reraRentalCalculatorDescription'),
          ),
          UAELinkItem(
            label: translate('advertisementPermit'),
            url:
                'https://dubailand.gov.ae/en/eservices/request-a-real-estate-permit/',
            description: translate('advertisementPermitDescription'),
          ),
          UAELinkItem(
            label: translate('validateLicensesPermits'),
            url:
                'https://dubailand.gov.ae/en/eservices/validate-real-estate-licenses-and-permits/',
            description: translate('validateLicensesPermitsDescription'),
          ),
          UAELinkItem(
            label: translate('mollakJop'),
            url: 'https://mollak.dubailand.gov.ae/',
            description: translate('mollakJopDescription'),
          ),
          UAELinkItem(
            label: translate('oqoodOffPlan'),
            url: 'https://oqood.dubailand.gov.ae/',
            description: translate('oqoodOffPlanDescription'),
          ),
          UAELinkItem(
            label: translate('rentalDisputesCenter'),
            url: 'https://rdc.gov.ae/',
            description: translate('rentalDisputesCenterDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('abuDhabi'),
        items: [
          UAELinkItem(
            label: translate('dariMain'),
            url: 'https://www.dari.ae/',
            description: translate('dariMainDescription'),
          ),
          UAELinkItem(
            label: translate('dariServices'),
            url: 'https://services.dari.ae/services/',
            description: translate('dariServicesDescription'),
          ),
          UAELinkItem(
            label: translate('adrec'),
            url: 'https://adrec.gov.ae/en',
            description: translate('adrecDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('sharjah'),
        items: [
          UAELinkItem(
            label: translate('sharjahMunicipalitySmartServices'),
            url: 'https://portal.shjmun.gov.ae/en/',
            description:
                translate('sharjahMunicipalitySmartServicesDescription'),
          ),
          UAELinkItem(
            label: translate('renewTenancyResidential'),
            url:
                'https://portal.shjmun.gov.ae/en/eservices/pages/services.aspx?sercatid=48',
            description: translate('renewTenancyResidentialDescription'),
          ),
          UAELinkItem(
            label: translate('tenancyContractDetails'),
            url:
                'https://portal.shjmun.gov.ae/en/eservices/Pages/GetTenancyContractInfo.aspx',
            description: translate('tenancyContractDetailsDescription'),
          ),
          UAELinkItem(
            label: translate('tasdeeqAttestation'),
            url: 'https://tasdeeq.am.gov.ae/en/index.html',
            description: translate('tasdeeqAttestationDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('ajman'),
        items: [
          UAELinkItem(
            label: translate('deptLandRealEstateHome'),
            url: 'https://ajmanre.gov.ae/en/',
            description: translate('deptLandRealEstateHomeDescription'),
          ),
          UAELinkItem(
            label: translate('eServicesPortal'),
            url: 'https://ajmanre.gov.ae/en/services/eservices/',
            description: translate('eServicesPortalDescription'),
          ),
          UAELinkItem(
            label: translate('registerLongTermLease'),
            url:
                'https://ajmanre.gov.ae/en/our-services/registration-of-a-long-term-lease/',
            description: translate('registerLongTermLeaseDescription'),
          ),
          UAELinkItem(
            label: translate('serviceDirectory'),
            url:
                'https://www.ajman.ae/en/servicecatalog/service_categories/department-land-real-estate-regulation',
            description: translate('serviceDirectoryDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('rasAlKhaimah'),
        items: [
          UAELinkItem(
            label: translate('registerTenancyContract'),
            url:
                'https://www.rak.ae/wps/portal/rak/e-services/govt/!/z/tenancy',
            description: translate('registerTenancyContractDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('ummAlQuwain'),
        items: [
          UAELinkItem(
            label: translate('municipalityServicesLeaseContracts'),
            url: 'https://md.uaq.ae/service.php',
            description:
                translate('municipalityServicesLeaseContractsDescription'),
          ),
        ],
      ),
      UAELinkCategory(
        title: translate('fujairah'),
        items: [
          UAELinkItem(
            label: translate('municipalityRentalContract'),
            url:
                'https://portal.fujmun.gov.ae/OnlineEservices/default.aspx?lang=en',
            description: translate('municipalityRentalContractDescription'),
          ),
          UAELinkItem(
            label: translate('ejaarUserGuidePdf'),
            url:
                'https://ejaar.fujmun.gov.ae/Ejaar/assets/files/EJAAR%20User%20Guide_English.pdf',
            description: translate('ejaarUserGuidePdfDescription'),
          ),
        ],
      ),
    ];
  }
}

// Canonical UAE residential / real-estate area catalog.
//
// ONE source of truth for the Request, Offer and Owner forms. Each city lists the
// top-level communities, districts and neighbourhoods a UAE property user
// would realistically search, ordered by product priority — highest market
// prominence first (current residential demand, sale/rental inventory, broker
// recognisability, then newer and peripheral areas). The order is NOT
// alphabetical and is NOT an official ranking.
//
// The stored value of an area is its key (a stable ID that is also its
// localization key); the English and Arabic names live in the ARB files.
// Keys already stored by older Requests/Offers were kept exactly (an Owner stores
// its location as readable text instead; see OwnerLocationCodec). Never
// rename a key: add a new one instead. Buildings, towers, tower clusters,
// project phases and numbered sub-districts are deliberately not areas.

/// Ordered, per-city area catalog shared by Add Request, Add Offer and Add Owner.
abstract final class UaeAreaCatalog {
  /// The cities the Request, Offer and Owner forms support.
  static const List<String> supportedCities = [
    'Dubai',
    'Abu Dhabi',
    'Sharjah',
    'Ajman',
    'Ras Al Khaimah',
    'Fujairah',
    'Umm Al Quwain',
    'Al Ain',
    'Khor Fakkan',
  ];

  /// The area keys offered for [city], most important first; empty for an
  /// unknown city.
  static List<String> areasFor(String city) =>
      _offered[city] ?? const <String>[];

  /// Whether [areaKey] is offered for new selection in [city].
  static bool isOffered(String city, String areaKey) =>
      areasFor(city).contains(areaKey);

  /// Whether [areaKey] belongs to [city]: offered for it now, or one an older
  /// picker offered for it that the catalog no longer lists. An area never
  /// belongs to more than one city.
  static bool isAreaOf(String city, String areaKey) =>
      isOffered(city, areaKey) ||
      (legacyOnlyAreas[city]?.contains(areaKey) ?? false);

  /// Whether [areaKey] is a key this app has ever offered: in any city's
  /// catalog, or one an older picker offered that is no longer listed. Saved
  /// Requests and Offers may carry any of them and must still render.
  static bool isSupported(String areaKey) => _supported.contains(areaKey);

  /// The localization key of a supported city's name (`dubai`, `abuDhabi`, …),
  /// for any screen that shows or stores the city. An unknown name is returned
  /// unchanged, as the forms' own helpers always did.
  static String cityKey(String city) => _cityKeys[city] ?? city;

  static const Map<String, String> _cityKeys = {
    'Dubai': 'dubai',
    'Abu Dhabi': 'abuDhabi',
    'Sharjah': 'sharjah',
    'Ajman': 'ajman',
    'Ras Al Khaimah': 'rasAlKhaimah',
    'Fujairah': 'fujairah',
    'Umm Al Quwain': 'ummAlQuwain',
    'Al Ain': 'alAin',
    'Khor Fakkan': 'khorFakkan',
  };

  /// Keys an older picker offered that the catalog no longer lists for new
  /// selection. They stay localized so a saved record keeps showing them.
  static const Map<String, List<String>> legacyOnlyAreas = {
    'Fujairah': [
      'qalaatAlFujairah',
    ],
    'Umm Al Quwain': [
      'alMuroorUAQ',
      'alHadarah',
      'alShabiya',
    ],
  };

  static const Map<String, List<String>> _offered = {
    'Dubai': _dubai,
    'Abu Dhabi': _abuDhabi,
    'Sharjah': _sharjah,
    'Ajman': _ajman,
    'Ras Al Khaimah': _rasAlKhaimah,
    'Fujairah': _fujairah,
    'Umm Al Quwain': _ummAlQuwain,
    'Al Ain': _alAin,
    'Khor Fakkan': _khorFakkan,
  };

  static final Set<String> _supported = {
    for (final areas in _offered.values) ...areas,
    for (final areas in legacyOnlyAreas.values) ...areas,
  };

  // Dubai — 91 areas.
  static const List<String> _dubai = [
    'dubaiMarina', // Dubai Marina
    'downtownDubai', // Downtown Dubai
    'businessBay', // Business Bay
    'jvc', // Jumeirah Village Circle
    'dubaiHillsEstate', // Dubai Hills Estate
    'palmJumeirah', // Palm Jumeirah
    'jlt', // Jumeirah Lakes Towers (JLT)
    'arabianRanches', // Arabian Ranches
    'dubaiCreekHarbour', // Dubai Creek Harbour
    'jbr', // Jumeirah Beach Residence (JBR)
    'mohammedBinRashidCity', // Mohammed Bin Rashid City
    'alFurjan', // Al Furjan
    'arjan', // Arjan
    'damacHills', // DAMAC Hills
    'dubaiSouth', // Dubai South
    'townSquare', // Town Square
    'palmJebelAli', // Palm Jebel Ali
    'mudon', // Mudon
    'tilalAlGhaf', // Tilal Al Ghaf
    'meydan', // Meydan
    'emaarBeachfront', // Emaar Beachfront
    'dubaiHarbour', // Dubai Harbour
    'bluewatersIsland', // Bluewaters Island
    'theValley', // The Valley
    'emaarSouth', // Emaar South
    'arabianRanches3', // Arabian Ranches 3
    'arabianRanches2', // Arabian Ranches 2
    'damacHills2', // DAMAC Hills 2
    'jumeirah', // Jumeirah
    'alBarsha', // Al Barsha
    'mirdif', // Mirdif
    'dubaiSiliconOasis', // Dubai Silicon Oasis
    'dubaiSportsCity', // Dubai Sports City
    'motorCity', // Motor City
    'discoveryGardens', // Discovery Gardens
    'dubaiProductionCity', // Dubai Production City
    'dubaiInvestmentsPark', // Dubai Investments Park
    'theSprings', // The Springs
    'theMeadows', // The Meadows
    'theLakes', // The Lakes
    'emiratesHills', // Emirates Hills
    'theGreens', // The Greens
    'theViews', // The Views
    'jumeirahGolfEstates', // Jumeirah Golf Estates
    'sobhaHartland', // Sobha Hartland
    'alBarari', // Al Barari
    'nadAlSheba', // Nad Al Sheba
    'jumeirahVillageTriangle', // Jumeirah Village Triangle (JVT)
    'jumeirahPark', // Jumeirah Park
    'jumeirahIslands', // Jumeirah Islands
    'victoryHeights', // Victory Heights
    'cityWalk', // City Walk
    'difc', // DIFC
    'dubaiIslands', // Dubai Islands
    'dubaiFestivalCity', // Dubai Festival City
    'barshaHeights', // Barsha Heights (Tecom)
    'dubaiStudioCity', // Dubai Studio City
    'internationalCity', // International City
    'umSuqeim', // Umm Suqeim
    'alWasl', // Al Wasl
    'alSafa', // Al Safa
    'alSatwa', // Al Satwa
    'alSufouh', // Al Sufouh
    'alQuoz', // Al Quoz
    'deira', // Deira
    'burDubai', // Bur Dubai
    'karama', // Karama
    'alQusais', // Al Qusais
    'alNahdaDubai', // Al Nahda
    'dubaiLandResidenceComplex', // Dubai Land Residence Complex
    'majan', // Majan
    'liwan', // Liwan
    'remraam', // Remraam
    'cultureVillage', // Culture Village
    'dubaiMaritimeCity', // Dubai Maritime City
    'expoCityDubai', // Expo City Dubai
    'alKhawaneej', // Al Khawaneej
    'alWarqa', // Al Warqa
    'alMizhar', // Al Mizhar
    'alTwar', // Al Twar
    'muhaisnah', // Muhaisnah
    'alGarhoud', // Al Garhoud
    'alRashidiyaDubai', // Al Rashidiya
    'oudMetha', // Oud Metha
    'alJaddaf', // Al Jaddaf
    'jebelAli', // Jebel Ali
    'rasAlKhor', // Ras Al Khor
    'nadAlHamar', // Nad Al Hamar
    'alMamzar', // Al Mamzar
    'portSaeed', // Port Saeed
    'horAlAnz', // Hor Al Anz
  ];

  // Abu Dhabi — 39 areas.
  static const List<String> _abuDhabi = [
    'yasIsland', // Yas Island
    'alReemIsland', // Al Reem Island
    'saadiyatIsland', // Saadiyat Island
    'alRahaBeach', // Al Raha Beach
    'abuDhabiCorniche', // Corniche
    'alMaryahIsland', // Al Maryah Island
    'khalifaCity', // Khalifa City
    'alReef', // Al Reef
    'mohammedBinZayedCity', // Mohammed Bin Zayed City
    'masdarCity', // Masdar City
    'hudayriyatIsland', // Hudayriyat Island
    'alKhalidiyah', // Al Khalidiyah
    'touristClubArea', // Tourist Club Area (Al Zahiyah)
    'alMushrif', // Al Mushrif
    'alMuroor', // Al Muroor
    'alBateen', // Al Bateen
    'jubailIsland', // Jubail Island
    'alMarkaziyah', // Al Markaziyah
    'alKaramah', // Al Karamah
    'alDanah', // Al Danah
    'alNahyan', // Al Nahyan
    'alRawdahAbuDhabi', // Al Rawdah
    'alManhal', // Al Manhal
    'alMina', // Al Mina
    'alRahaGardens', // Al Raha Gardens
    'shakhboutCity', // Shakhbout City
    'baniyas', // Baniyas
    'alShamkha', // Al Shamkha
    'madinatAlRiyad', // Madinat Al Riyad
    'alFalahAbuDhabi', // Al Falah
    'hydraVillage', // Hydra Village
    'alGhadeer', // Al Ghadeer
    'rabdan', // Rabdan
    'sasAlNakhl', // Sas Al Nakhl
    'zayedCity', // Zayed City
    'alShawamekh', // Al Shawamekh
    'alWathba', // Al Wathba
    'alMaqtaa', // Al Maqtaa
    'mussafah', // Mussafah
  ];

  // Sharjah — 45 areas.
  static const List<String> _sharjah = [
    'aljada', // Aljada
    'muwailehCommercial', // Muwaileh Commercial
    'muwaileh', // Muwaileh
    'alMajaz', // Al Majaz
    'alKhan', // Al Khan
    'alTaawun', // Al Taawun
    'alNahdaSharjah', // Al Nahda
    'alQasba', // Al Qasba
    'alZahia', // Al Zahia
    'alRahmaniya', // Al Rahmaniya
    'tilalCity', // Tilal City
    'sharjahSustainableCity', // Sharjah Sustainable City
    'masaar', // Masaar
    'alWahda', // Al Wahda
    'alSuyoh', // Al Suyoh
    'alJuraina', // Al Juraina
    'alTai', // Al Tai
    'alGharayen', // Al Gharayen
    'alNoaf', // Al Noaf
    'hoshi', // Hoshi
    'alQasimia', // Al Qasimia
    'abuShagara', // Abu Shagara
    'alYarmook', // Al Yarmook
    'alNabba', // Al Nabba
    'alMusalla', // Al Musalla
    'alGhuwair', // Al Ghuwair / Rolla
    'alJazzat', // Al Jazzat
    'alRamtha', // Al Ramtha
    'alAzra', // Al Azra
    'alHeerah', // Al Heerah
    'alFisht', // Al Fisht
    'alSharqan', // Al Sharqan
    'alRifahSharjah', // Al Rifah
    'alNekhailat', // Al Nekhailat
    'alDarari', // Al Darari
    'alFalajSharjah', // Al Falaj
    'alFayha', // Al Fayha
    'alSweihat', // Al Sweihat
    'alBarashi', // Al Barashi
    'alButina', // Al Butina
    'alFalah', // Al Falah
    'alMirgab', // Al Mirgab
    'maysaloon', // Maysaloon
    'sharjahIndustrialArea', // Sharjah Industrial Area
    'alSajaa', // Al Sajaa
  ];

  // Ajman — 28 areas.
  static const List<String> _ajman = [
    'alNuaimia', // Al Nuaimia
    'alRashidiya', // Al Rashidiya
    'alRawda', // Al Rawda
    'ajmanDowntown', // Ajman Downtown
    'alYasmeen', // Al Yasmeen
    'alMowaihat', // Al Mowaihat
    'ajmanCorniche', // Ajman Corniche
    'alZorah', // Al Zorah
    'alJurf', // Al Jurf
    'alZahya', // Al Zahya
    'emiratesCity', // Emirates City
    'alHelio', // Al Helio
    'alHamidiya', // Al Hamidiya
    'alBustan', // Al Bustan
    'alRumaila', // Al Rumaila
    'alNakhilAjman', // Al Nakhil
    'alJurfIndustrial', // Al Jurf Industrial
    'alAlia', // Al Alia
    'alTallah', // Al Tallah
    'alAmerah', // Al Amerah
    'alBahiaAjman', // Al Bahia
    'alRaqaib', // Al Raqaib
    'mushairef', // Mushairef
    'liwara', // Liwara
    'alOwan', // Al Owan
    'alSawan', // Al Sawan
    'alZahra', // Al Zahra
    'ajmanIndustrialArea', // Ajman Industrial Area
  ];

  // Ras Al Khaimah — 24 areas.
  static const List<String> _rasAlKhaimah = [
    'alHamraVillage', // Al Hamra Village
    'alMarjanIsland', // Al Marjan Island
    'minaAlArab', // Mina Al Arab
    'alNakheel', // Al Nakheel
    'alDhait', // Al Dhait
    'alSeer', // Al Seer
    'alMamourah', // Al Mamourah
    'alMairid', // Al Mairid
    'khuzam', // Khuzam
    'alQusaidat', // Al Qusaidat
    'alRams', // Al Rams
    'alJazeeraAlHamra', // Al Jazeera Al Hamra
    'alRiffa', // Al Riffa
    'alUraibi', // Al Uraibi
    'seihAlUraibi', // Seih Al Uraibi
    'dafanAlKhor', // Dafan Al Khor
    'dafanAlNakheel', // Dafan Al Nakheel
    'julphar', // Julphar
    'alQurm', // Al Qurm
    'shamal', // Shamal
    'alGhail', // Al Ghail
    'alKharran', // Al Kharran
    'alHudaiba', // Al Hudaiba
    'alJuwais', // Al Juwais
  ];

  // Fujairah — 20 areas.
  static const List<String> _fujairah = [
    'sharm', // Sharm
    'alFaseel', // Al Faseel
    'sakamkam', // Sakamkam
    'fujairahCityCorniche', // Fujairah City / Corniche
    'alHayl', // Al Hayl
    'madhab', // Madhab
    'merashid', // Merashid
    'murbah', // Mirbah
    'dibbaFujairah', // Dibba Fujairah
    'alAqah', // Al Aqah
    'dadna', // Dadna
    'alBidya', // Al Bidya
    'qidfa', // Qidfa
    'alGurfa', // Al Gurfa
    'alHlaifat', // Al Hlaifat
    'minaAlFajer', // Mina Al Fajer
    'thoban', // Thoban
    'alTawyeen', // Al Tawyeen
    'alBithnah', // Al Bithnah
    'masafi', // Masafi
  ];

  // Umm Al Quwain — 18 areas.
  static const List<String> _ummAlQuwain = [
    'uaqOldTown', // Old Town
    'alSalama', // Al Salama
    'alRamlah', // Al Ramlah
    'alRaas', // Al Raas
    'alRaudahUAQ', // Al Raudah
    'alHumrah', // Al Humrah
    'alRiqqah', // Al Riqqah
    'alMaidan', // Al Maidan
    'alDarAlBaida', // Al Dar Al Baida
    'ummAlThuoob', // Umm Al Thuoob
    'falajAlMualla', // Falaj Al Mualla
    'alHawiyah', // Al Hawiyah
    'alSeanneeah', // Al Seanneeah
    'alRaafa', // Al Raafa
    'alHaditha', // Al Haditha
    'alKhorUAQ', // Al Khor
    'ummaquwainIndustrialArea', // Umm Al Quwain Industrial Area
    'kingFaisalRoad', // King Faisal Road
  ];

  // Al Ain — 31 areas.
  static const List<String> _alAin = [
    'alJimi', // Al Jimi
    'alMuwaiji', // Al Muwaiji
    'alHili', // Al Hili
    'alFoah', // Al Foah
    'alBateenAlAin', // Al Bateen
    'alMaqam', // Al Maqam
    'alSarooj', // Al Sarooj
    'alTowayya', // Al Towayya
    'alKhabisi', // Al Khabisi
    'falajHazza', // Falaj Hazza
    'alMutarad', // Al Mutarad
    'alMutawaa', // Al Mutawaa
    'alMarkhaniya', // Al Markhaniya
    'zakhir', // Zakher
    'alYahar', // Al Yahar
    'alAinIndustrialArea', // Al Ain Industrial Area
    'alDhahir', // Al Dhahir
    'manaseer', // Manaseer
    'alJahili', // Al Jahili
    'alQattara', // Al Qattara
    'alKuwaitat', // Al Kuwaitat
    'remah', // Remah
    'alFaqa', // Al Faqa
    'sweihan', // Sweihan
    'alSalamat', // Al Salamat
    'shabAlAshkhar', // Shab Al Ashkhar
    'alRawdahAlSharqiyah', // Al Rawdah Al Sharqiyah
    'umGhafah', // Um Ghafah
    'neima', // Neima
    'alMasoudi', // Al Masoudi
    'alAmeriya', // Al Ameriya
  ];

  // Khor Fakkan — 15 areas.
  static const List<String> _khorFakkan = [
    'alMudaifi', // Al Mudaifi
    'hayawa', // Hayawa
    'alKhaledya', // Al Khaledya
    'zubara', // Zubara
    'alHaray', // Al Haray
    'alBurdi', // Al Burdi
    'alQadisiyahKhorFakkan', // Al Qadisiyah
    'alYarmoukKhorFakkan', // Al Yarmouk
    'shabiyaKhorFakkan', // Shabiya
    'alMusallaKhorFakkan', // Al Musalla
    'alRifaaKhorFakkan', // Al Rifa'a
    'alLulayyah', // Al Lulayyah
    'nahwa', // Nahwa
    'wadiShis', // Wadi Shis
    'hatim', // Hatim
  ];
}

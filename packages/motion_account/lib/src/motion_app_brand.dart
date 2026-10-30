// Store brand spelling of each app id for user-facing text ("JabLab", not
// "Jablab"). An id without an entry keeps the capitalised id, as before.
const _brandNames = {'jablab': 'JabLab', 'gravita': 'Gravita', 'ostinato': 'Ostinato', 'choreia': 'Choreia', 'lissom': 'Lissom'};

String motionAppBrandName(String appId) =>
    _brandNames[appId] ??
    (appId.isEmpty ? appId : appId[0].toUpperCase() + appId.substring(1));

unit Atlas.Core.Credentials.Contract;

// Anmeldespeicher für Schlüssel und Token (#1922): Was ein Modul an Geheimem
// braucht (Zugang zum Build-Server, Token des Issue-Trackers, Schlüssel eines
// KI-Anbieters), steht nur im Anmeldespeicher von Windows, nie in einer Datei,
// der Registry, den Einstellungen oder dem Protokoll. Die Umsetzung liegt in
// Atlas.Core.Credentials.Adapters.Windows; Tests setzen eine Fälschung ein.
// Lesen auch im Hintergrund-Thread.

interface

type
  IAtlasCredentialStore = interface
    ['{0B6C3A57-8E21-4F49-A6D3-5C1E9F27B084}']
    /// <summary>Eintrag zu ATarget lesen; False ohne Eintrag.</summary>
    function Read(const ATarget: string; out AUser, ASecret: string): Boolean;
    /// <summary>Eintrag anlegen oder ersetzen, AComment für die Anmeldeinformationsverwaltung; False bei Fehler oder
    /// zu langem Geheimnis.</summary>
    function Write(const ATarget, AUser, ASecret, AComment: string): Boolean;
    /// <summary>Eintrag entfernen; True auch, wenn es keinen gab.</summary>
    function Delete(const ATarget: string): Boolean;
  end;

implementation

end.

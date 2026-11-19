unit Atlas.IDE.Welcome.Areas;

// Die Quellen der Bereiche der Atlas-Willkommensseite (#753), wie die
// Steuerung (Atlas.IDE.Welcome.Commands) und die Köpfe sie sehen: Refresh
// führt sie nach den Einstellungen nach, Stop hält sie in der Reihenfolge an,
// die das Beenden der IDE braucht, Release gibt sie frei, dazu die Karte
// „Neu in Atlas“ (#756). Die Quellen selbst sind Adapter; sie legt die
// Composition an (Atlas.IDE.Welcome.Composition.Areas), die Steuerung kennt
// nur diese Sicht.

interface

uses
  Atlas.Core.Welcome.Contract,
  Atlas.UI.Welcome.Contract;

type
  TAtlasIdeWelcomeAreas = class abstract
  public
    /// <summary>Titel, Reihenfolge und Inhalt nach den Einstellungen (bei jedem Sync der Steuerung).</summary>
    procedure Refresh; virtual; abstract;
    /// <summary>Alle anhalten (Beenden der IDE oder Entladen).</summary>
    procedure Stop; virtual; abstract;
    /// <summary>Nach den Frames: alle Quellen freigeben.</summary>
    procedure Release; virtual; abstract;
    /// <summary>Karte „Neu in Atlas“ (#756); nil = ohne.</summary>
    function News: IAtlasWhatsNewSource; virtual; abstract;
    /// <summary>Die Karte gibt es und sie zeigt etwas.</summary>
    function NewsActive: Boolean; virtual; abstract;
    /// <summary>Nach einem Update steht die Karte oben in der ersten Spalte.</summary>
    function NewsOnTop: Boolean; virtual; abstract;
    /// <summary>Neue Einträge melden; ohne Karte nichts.</summary>
    procedure AnnounceNews(const AItems: TArray<TAtlasWhatsNewItem>); virtual; abstract;
    /// <summary>Karte mit AView zeigen; ohne Karte nichts.</summary>
    procedure ShowNews(AView: TAtlasWhatsNewView); virtual; abstract;
  end;

implementation

end.

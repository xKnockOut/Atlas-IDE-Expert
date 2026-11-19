unit Atlas.IDE.Welcome.ContinueIssueLink;

// Was „Weiterarbeiten“ (#755) vom Reiter „Issues“ (#2052) kennt: anhalten,
// den mit „Zuletzt“ geschriebenen Stand unter dem aktiven Issue sichern und
// die Quelle für den Frame. Den Reiter selbst legt die Composition über
// TAtlasIdeContinueIssuesCreate an; „Weiterarbeiten“ kennt ihn nur über
// diese Sicht.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Welcome.Contract,
  Atlas.IDE.Welcome.Continue.Editor,
  Atlas.UI.Welcome.Contract;

type
  TAtlasIdeContinueIssueLink = class abstract(TInterfacedObject)
  public
    /// <summary>Danach wirkungslos; laufende Abfragen tun nichts mehr.</summary>
    procedure Stop; virtual; abstract;
    /// <summary>„Zuletzt“ hat ASnapshot für ATarget geschrieben (Schließen, Beenden): denselben Stand unter dem
    /// aktiven Issue sichern.</summary>
    procedure ProjectWritten(const ATarget: string; const ASnapshot: TAtlasContinueSnapshot); virtual; abstract;
    /// <summary>Quelle des Reiters für neue Frames.</summary>
    function Source: IAtlasContinueIssuesSource; virtual; abstract;
  end;

  /// <summary>Reiter anlegen. AMessage: Zeile in die Meldungsansicht; AChanges: Änderungsstellen von
  /// „Weiterarbeiten“ (gehört dem Aufrufer); AChanged: Bereich neu zeichnen.</summary>
  TAtlasIdeContinueIssuesCreate = reference to function(const AMessage: TProc<string>;
    AChanges: TDictionary<string, TAtlasWorkTab>; const AChanged: TProc): TAtlasIdeContinueIssueLink;

implementation

end.

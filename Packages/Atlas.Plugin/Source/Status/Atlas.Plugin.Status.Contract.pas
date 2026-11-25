unit Atlas.Plugin.Status.Contract;

// Schnittstelle des Atlas-Statusfelds (#591), ohne VCL und Open Tools API:
// Jede Funktion, die etwas in der Statusleiste zeigen will (Server, Index,
// Datei, später Fehlerzähler #509, Compilerprüfung #548 …), meldet eine Zeile
// als IAtlasStatusItem bei IAtlasStatusRegistry an und ruft Changed, wenn
// sich ihr Inhalt ändert. Das Feld in der Statusleiste und das Fenster beim
// Klick lesen nur die Registry; neue Zeilen brauchen keine Änderung an der
// Oberfläche. Die Zustandskachel der Willkommensseite (#754) liest dieselben
// Zeilen; die optionale Schnittstelle IAtlasStatusBrief liefert ihr eine
// Kurzform mit Zusatz rechts.
// Das Feld selbst (Zustand, Zusatzfelder, Plakette, Klicks) entscheidet
// TAtlasStatusFieldFlow im Kern; Statuszeilen, Panels, Zeichnen und das
// Statusfenster liegen hinter IAtlasStatusFieldSurface (in der IDE ein
// Adapter, in den Tests eine Fälschung).

interface

uses
  System.SysUtils,
  System.Types;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand einer Zeile, aufsteigend nach Schwere: Neutral (keine Aussage), Grün (in
  /// Ordnung), Gelb (Warnung, läuft noch, langsam), Rot (gestoppt, Fehler).</summary>
  TAtlasStatusState = (Neutral, Green, Yellow, Red);

  /// <summary>Was ein Linksklick in der Statuszeile auslöst: nichts von Atlas; Liste der Benachrichtigungen
  /// (Plakette); Statusfenster; Zusatzfeld.</summary>
  TAtlasStatusFieldClick = (None, Badge, Window, Extra);

  /// <summary>Mausnachricht über der Statuszeile, nach der die Schnellschalter aufgehen können.</summary>
  TAtlasStatusFieldGesture = (RightButton, DoubleClick, ContextMenu);
{$SCOPEDENUMS OFF}

  IAtlasStatusItem = interface
    ['{6B1F4C2E-3A97-4D58-9E0B-21C7A5D3F864}']
    /// <summary>Eindeutige Kennung, z. B. "atlas.server"; für statusField.hidden.</summary>
    function Id: string;
    /// <summary>Zeile im Fenster, z. B. "Server: läuft, 12 ms im Mittel, Version 1.0.0".</summary>
    function Text: string;
    /// <summary>Kurztext neben „Atlas“ (z. B. "2 Fehler"); '' = keiner.</summary>
    function Summary: string;
    function State: TAtlasStatusState;
    /// <summary>Reihenfolge im Fenster, kleiner zuerst; bei Gleichstand nach Kennung.</summary>
    function Order: Integer;
    /// <summary>True, wenn ein Klick auf die Zeile etwas tut (Execute).</summary>
    function HasAction: Boolean;
    /// <summary>Aktion bei Klick auf die Zeile; im Hauptthread.</summary>
    procedure Execute;
  end;

  /// <summary>Optionale Kurzform einer Zeile für die Zustandskachel der Willkommensseite (#754). Zustand und
  /// Aktion bleiben die der Zeile; Zeilen ohne diese Schnittstelle zeigen dort ihren Text.</summary>
  IAtlasStatusBrief = interface
    ['{9C4E2B71-0D5A-4F3E-8B26-7A1F6C93D4E5}']
    /// <summary>Kurzer Text, z. B. "Server läuft"; '' = Text der Zeile.</summary>
    function Brief: string;
    /// <summary>Zusatz rechts, z. B. "seit 19:02"; '' = keiner.</summary>
    function Detail: string;
  end;

  /// <summary>Optional: Zeile, deren Aktion und Schalter dem anmeldenden Modul gehören. Die Registry ruft Detach,
  /// sobald sie die Zeile abgibt (Remove oder Ersetzen): Wer die Zeile danach noch hält (Statusfeld, Fenster,
  /// Kachel bis zum nächsten Zeichnen), erreicht keinen Code des Moduls mehr, auch nach dessen Entladen.</summary>
  IAtlasStatusDetach = interface
    ['{781EAA1C-EC00-4A4F-BE40-F800CF6B19FD}']
    /// <summary>Registry, Aktion und Schalter vergessen; danach HasAction False, Execute und Update wirkungslos
    /// nach außen.</summary>
    procedure Detach;
  end;

  /// <summary>Zusatzfeld hinter dem Atlas-Feld (TAtlasIdeHost.SetStatusItem): Kennung, Text ('' entfernt es),
  /// Tooltip, Zustand (Neutral = ohne Punkt; sonst Punkt in der Farbe des Zustands, nur in der Atlas-Statusleiste
  /// #1155), Linksklick und Rechtsklick (nil = keiner) mit der linken Oberkante des Felds (Bildschirm).</summary>
  TAtlasStatusExtra = record
    Id: string;
    Text: string;
    Hint: string;
    State: TAtlasStatusState;
    OnClick: TProc<TPoint>;
    OnContext: TProc<TPoint>;
    /// <summary>Feld AId mit Text, Tooltip und Linksklick; Zustand neutral, ohne Rechtsklick.</summary>
    class function Make(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>): TAtlasStatusExtra; static;
  end;

  IAtlasStatusRegistry = interface
    ['{0D93E7A4-5C21-4B8F-A6E3-9F48B2C1D057}']
    /// <summary>Meldet AItem an; eine Zeile mit derselben Kennung wird ersetzt.</summary>
    procedure Add(const AItem: IAtlasStatusItem);
    procedure Remove(const AId: string);
    /// <summary>nil, wenn keine Zeile diese Kennung hat.</summary>
    function Find(const AId: string): IAtlasStatusItem;
    /// <summary>Alle Zeilen nach Order, dann Kennung.</summary>
    function Items: TArray<IAtlasStatusItem>;
    /// <summary>Eine Zeile hat sich geändert; benachrichtigt alle Beobachter. Aus jedem Thread.</summary>
    procedure Changed;
    /// <summary>Zählt jede Änderung (Add, Remove, Changed).</summary>
    function Version: Integer;
    /// <summary>Beobachter für Änderungen; läuft im Thread des Aufrufers von Changed.</summary>
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
  end;

  /// <summary>Linke Oberkante eines Felds (Bildschirm); False ohne.</summary>
  TAtlasStatusAnchorFunc = reference to function(out APoint: TPoint): Boolean;

  /// <summary>Plakette der Benachrichtigungen (#601).</summary>
  TAtlasStatusBadge = record
    /// <summary>Benachrichtigungen an: die Atlas-Statusleiste zeigt die Plakette auch mit 0.</summary>
    Shown: Boolean;
    Count: Integer;
    State: TAtlasStatusState;
    Hint: string;
    /// <summary>Linksklick auf die Plakette mit der linken Oberkante des Felds.</summary>
    OnClick: TProc<TPoint>;
  end;

  /// <summary>Zusatzfeld für die Atlas-Statusleiste (#1155): Kennung, Text, Tooltip und ob ein Klick etwas tut.
  /// </summary>
  TAtlasStatusExtraItem = record
    Id: string;
    Text: string;
    Hint: string;
    Clickable: Boolean;
    /// <summary>Zustand des Punkts; Neutral = ohne Punkt (#1777).</summary>
    State: TAtlasStatusState;
    /// <summary>Rechtsklick tut etwas (ClickExtra mit AContext).</summary>
    HasContext: Boolean;
  end;

  /// <summary>Stand des letzten Refresh: sichtbare Zeilen, Kurztext, Tooltip und Gesamtzustand.</summary>
  TAtlasStatusShown = record
    Items: TArray<IAtlasStatusItem>;
    Text: string;
    Tooltip: string;
    State: TAtlasStatusState;
  end;

  /// <summary>Ereignisse des Felds; gesetzt von der Kompositionswurzel.</summary>
  TAtlasStatusFieldEvents = record
    OnRefresh: TProc;
    OnOpenLog: TProc;
    OnRestart: TProc;
    OnContext: TProc<TPoint>;
    OnRelocatedAnchor: TAtlasStatusAnchorFunc;
  end;

  /// <summary>Was die Statuszeile jedes Editorfensters zeigt: das Atlas-Panel (Panel) mit Kurztext, Punkt und
  /// Plakette (BadgeCount 0 = keine), dahinter die Zusatzfelder als Text (Extras, in ihrer Reihenfolge).</summary>
  TAtlasStatusFieldView = record
    Panel: Boolean;
    Text: string;
    State: TAtlasStatusState;
    BadgeCount: Integer;
    BadgeState: TAtlasStatusState;
    Extras: TArray<string>;
  end;

  /// <summary>Linksklick in Zone AZone (0 = Atlas-Feld, ab 1 Zusatzfeld, -1 = keins) an AX; ABadgeLeft ist die
  /// linke Kante der Plakette, AFieldCorner und AZoneCorner die linken Oberkanten (Bildschirm) des Atlas-Felds
  /// und der Zone. Ergebnis: False, wenn der Klick nicht Atlas gilt.</summary>
  TAtlasStatusFieldClickFunc = reference to function(AZone, AX, ABadgeLeft: Integer;
    const AFieldCorner, AZoneCorner: TPoint): Boolean;
  /// <summary>Öffnet AGesture über dem Atlas-Feld (AInPanel) die Schnellschalter? AFromKeyboard: Kontextmenü von
  /// der Tastatur.</summary>
  TAtlasStatusFieldGestureFunc = reference to function(AGesture: TAtlasStatusFieldGesture;
    AInPanel, AFromKeyboard: Boolean): Boolean;
  /// <summary>Tooltip der Zone AZone (wie bei TAtlasStatusFieldClickFunc).</summary>
  TAtlasStatusFieldHintFunc = reference to function(AZone: Integer): string;

  /// <summary>Was die Oberfläche an das Feld meldet; alles im Hauptthread.</summary>
  TAtlasStatusFieldInput = record
    /// <summary>Gesammelte Aktualisierung (nach IAtlasStatusFieldSurface.RequestTick und eigenen Anlässen wie
    /// neuen Editorfenstern).</summary>
    OnTick: TProc;
    OnClick: TAtlasStatusFieldClickFunc;
    OpensToggles: TAtlasStatusFieldGestureFunc;
    HintOf: TAtlasStatusFieldHintFunc;
    /// <summary>Schnellschalter an der linken Oberkante des Atlas-Felds (nach der Mausnachricht).</summary>
    OnContext: TProc<TPoint>;
  end;

  /// <summary>Statuszeilen der Editorfenster und Statusfenster des Atlas-Felds (#591): in der IDE die Panels der
  /// TStatusBar jedes Editorfensters mit verketteten Ereignissen, in den Tests eine Fälschung. Entscheidungen
  /// trifft TAtlasStatusFieldFlow; die Oberfläche zeigt nur und meldet Benutzeraktionen über
  /// TAtlasStatusFieldInput. Bis auf RequestTick nur im Hauptthread.</summary>
  IAtlasStatusFieldSurface = interface
    ['{4E8A2D17-B3C6-4F95-8A1E-7D0C5B29E643}']
    /// <summary>AInput bekommt ab jetzt die Meldungen der Oberfläche.</summary>
    procedure Attach(const AInput: TAtlasStatusFieldInput);
    /// <summary>Alle Leisten aushängen, Statusfenster schließen; danach meldet die Oberfläche nichts mehr.</summary>
    procedure Detach;
    /// <summary>OnTick anfordern; aus jedem Thread, gesammelt.</summary>
    procedure RequestTick;
    /// <summary>Statuszeilen aller Editorfenster einhängen und nach AView beschriften.</summary>
    procedure Show(const AView: TAtlasStatusFieldView);
    /// <summary>Alle Statuszeilen aushängen: Die Statuszeile braucht nichts von Atlas.</summary>
    procedure Unhook;
    /// <summary>Linke Oberkante des Atlas-Felds im obersten Editorfenster (Bildschirm); False ohne.</summary>
    function FieldCorner(out APoint: TPoint): Boolean;
    function WindowOpen: Boolean;
    /// <summary>Statusfenster mit AItems über APoint öffnen; seine Knöpfe rufen AOnOpenLog bzw. AOnRestart.
    /// </summary>
    procedure OpenWindow(const AItems: TArray<IAtlasStatusItem>; const APoint: TPoint;
      const AOnOpenLog, AOnRestart: TProc);
    /// <summary>Statusfenster schließen; ohne nichts.</summary>
    procedure CloseWindow;
    /// <summary>Zeilen des offenen Statusfensters nachführen; ohne nichts.</summary>
    procedure WindowItems(const AItems: TArray<IAtlasStatusItem>);
  end;

implementation

{ TAtlasStatusExtra }

class function TAtlasStatusExtra.Make(const AId, AText, AHint: string;
  const AOnClick: TProc<TPoint>): TAtlasStatusExtra;
begin
  Result := Default(TAtlasStatusExtra);
  Result.Id := AId;
  Result.Text := AText;
  Result.Hint := AHint;
  Result.OnClick := AOnClick;
end;

end.

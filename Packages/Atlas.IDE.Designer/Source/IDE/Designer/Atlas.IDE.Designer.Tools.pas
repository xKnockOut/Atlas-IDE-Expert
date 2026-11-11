unit Atlas.IDE.Designer.Tools;

// Werkzeuge mit eigenem Knopf in der Designer-Leiste (#734 ff.), an einer
// Stelle für die Befehle der Leiste (TAtlasIdeDesignerCommands): Ein Klick
// auf das Symbol schaltet das Werkzeug ein und aus (gedrückt = an), der Pfeil
// öffnet sein Menü. Der Takt der Leiste lässt die Werkzeuge der Auswahl im
// Designer folgen.
// - Abstandsgriffe (#734, designer.gapHandles, TAtlasIdeGapHandles).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.GapHandles;

type
  TAtlasIdeDesignerTools = class
  private
    FGaps: TAtlasIdeGapHandles;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Klick auf das Symbol des Knopfs AId; False, wenn er nicht hierher gehört.</summary>
    function Toggle(const AId: string): Boolean;
    /// <summary>Gehört der Knopf AId mit Menü hierher?</summary>
    function HasMenu(const AId: string): Boolean;
    /// <summary>Menü des Knopfs AId an APoint (Bildschirm).</summary>
    procedure Popup(const AId: string; const APoint: TPoint);
    /// <summary>Takt der Leiste, solange sie gezeigt wird.</summary>
    procedure Tick;
    /// <summary>Alles ausblenden (Leiste aus, Designer weg).</summary>
    procedure Hide;
    procedure ApplyTheme;
  end;

implementation

{ TAtlasIdeDesignerTools }

constructor TAtlasIdeDesignerTools.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FGaps := TAtlasIdeGapHandles.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerTools.Destroy;
begin
  FGaps.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerTools.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
begin
  Result := nil;
  if TAtlasIdeGapHandles.Available(ASettings) then
  begin
    Result := Result + [FGaps.Button];
  end;
end;

function TAtlasIdeDesignerTools.Toggle(const AId: string): Boolean;
begin
  Result := SameText(AId, TAtlasIdeGapHandles.cId);
  if Result then
  begin
    FGaps.Toggle;
  end;
end;

function TAtlasIdeDesignerTools.HasMenu(const AId: string): Boolean;
begin
  Result := SameText(AId, TAtlasIdeGapHandles.cId);
end;

procedure TAtlasIdeDesignerTools.Popup(const AId: string; const APoint: TPoint);
begin
  if SameText(AId, TAtlasIdeGapHandles.cId) then
  begin
    FGaps.Popup(APoint);
  end;
end;

procedure TAtlasIdeDesignerTools.Tick;
begin
  FGaps.Tick;
end;

procedure TAtlasIdeDesignerTools.Hide;
begin
  FGaps.Hide;
end;

procedure TAtlasIdeDesignerTools.ApplyTheme;
begin
  FGaps.ApplyTheme;
end;

end.

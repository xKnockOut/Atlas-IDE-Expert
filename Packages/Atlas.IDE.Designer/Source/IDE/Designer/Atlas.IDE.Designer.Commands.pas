unit Atlas.IDE.Designer.Commands;

// Befehle der Designer-Leiste für Auswahl und Anordnen in der IDE, an einer
// Stelle für die Leiste (Atlas.IDE.Designer.Bar):
// - Menüknöpfe „Gleiche auswählen“ (#738, mit den Auswahlsätzen #739,
//   TAtlasIdeDesignerSelect) und „Anordnen“ (#730 ff.,
//   TAtlasIdeDesignerArrange); Symbol und Pfeil öffnen das Menü.
// - Tasten im Designer: Auswahlsätze und räumliche Navigation (#745,
//   TAtlasIdeDesignerNavigate), angemeldet nur, solange ein Designer gezeigt
//   wird.
// - Eigene Knöpfe der größeren Designer-Funktionen (#605 ff.,
//   TAtlasIdeDesignerTools); Klicks ohne Menü über Run.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.Select,
  Atlas.IDE.Designer.Arrange,
  Atlas.IDE.Designer.Navigate,
  Atlas.IDE.Designer.Tools;

type
  TAtlasIdeDesignerCommands = class
  public const
    cIdSelect = 'selectSimilar';
    cIdArrange = 'arrange';
  private
    FSelect: TAtlasIdeDesignerSelect;
    FArrange: TAtlasIdeDesignerArrange;
    FNavigate: TAtlasIdeDesignerNavigate;
    FTools: TAtlasIdeDesignerTools;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Menüknöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Gehört der Knopf AId hierher (Klick auf das Symbol öffnet das Menü)?</summary>
    function Handles(const AId: string): Boolean;
    /// <summary>Menü des Knopfs AId an APoint (Bildschirm).</summary>
    procedure Popup(const AId: string; const APoint: TPoint);
    /// <summary>Klick auf einen Knopf ohne Menü; False, wenn er nicht hierher gehört.</summary>
    function Run(const AId: string): Boolean;
    /// <summary>Tasten an- oder abmelden (Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
    procedure ApplyTheme;
  end;

implementation

uses
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.Strings;

{ TAtlasIdeDesignerCommands }

constructor TAtlasIdeDesignerCommands.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FSelect := TAtlasIdeDesignerSelect.Create(AOnMessage);
  FArrange := TAtlasIdeDesignerArrange.Create(AOnMessage);
  FNavigate := TAtlasIdeDesignerNavigate.Create;
  FTools := TAtlasIdeDesignerTools.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerCommands.Destroy;
begin
  FTools.Free;
  FNavigate.Free;
  FArrange.Free;
  FSelect.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerCommands.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
var
  mButton: TAtlasDesignerButton;
begin
  Result := nil;
  if ASettings.DesignerSelectSimilar or ASettings.DesignerSelectionSets then
  begin
    mButton := TAtlasDesignerButton.Create(cIdSelect, TAtlasToolbarIcon.SelectSimilar,
      TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSelectHint));
    mButton.Menu := True;
    Result := Result + [mButton];
  end;
  if TAtlasIdeDesignerArrange.Available(ASettings) then
  begin
    mButton := TAtlasDesignerButton.Create(cIdArrange, TAtlasToolbarIcon.Arrange,
      TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerArrangeHint));
    mButton.Menu := True;
    Result := Result + [mButton];
  end;
  Result := Result + FTools.Buttons(ASettings);
end;

function TAtlasIdeDesignerCommands.Handles(const AId: string): Boolean;
begin
  Result := SameText(AId, cIdSelect) or SameText(AId, cIdArrange);
end;

procedure TAtlasIdeDesignerCommands.Popup(const AId: string; const APoint: TPoint);
begin
  if SameText(AId, cIdSelect) then
  begin
    FSelect.Popup(APoint);
  end
  else if SameText(AId, cIdArrange) then
  begin
    FArrange.Popup(APoint);
  end;
end;

function TAtlasIdeDesignerCommands.Run(const AId: string): Boolean;
begin
  Result := FTools.Run(AId);
end;

procedure TAtlasIdeDesignerCommands.UpdateKeys(AWanted: Boolean);
begin
  FSelect.UpdateKeys(AWanted);
  FNavigate.UpdateKeys(AWanted);
end;

procedure TAtlasIdeDesignerCommands.ApplyTheme;
begin
  FNavigate.ApplyTheme;
  FArrange.ApplyTheme;
  FTools.ApplyTheme;
end;

end.

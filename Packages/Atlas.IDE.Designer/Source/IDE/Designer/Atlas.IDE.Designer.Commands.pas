unit Atlas.IDE.Designer.Commands;

// Befehle der Designer-Leiste für Auswahl und Anordnen in der IDE, an einer
// Stelle für die Leiste (Atlas.IDE.Designer.Bar):
// - Menüknöpfe „Gleiche auswählen“ (#738, mit den Auswahlsätzen #739,
//   TAtlasIdeDesignerSelect) und „Anordnen“ (#730 ff.,
//   TAtlasIdeDesignerArrange); Symbol und Pfeil öffnen das Menü.
// - Tasten im Designer: Auswahlsätze und räumliche Navigation (#745,
//   TAtlasIdeDesignerNavigate), angemeldet nur, solange ein Designer gezeigt
//   wird.
// - Werkzeuge mit eigenem Knopf (#734 ff., TAtlasIdeDesignerTools): Symbol
//   schaltet ein und aus, Pfeil öffnet das Menü; sie folgen dem Takt der
//   Leiste (Tick).
// - Designer-Ansichten mit eigenem Knopf ohne Menü (#605 ff.,
//   TAtlasIdeDesignerViews): Abstände messen, Größe ausprobieren, Skalierung
//   und Texte; ein Klick schaltet bzw. öffnet.
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
  Atlas.IDE.Designer.Tools,
  Atlas.IDE.Designer.Views;

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
    FViews: TAtlasIdeDesignerViews;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Menüknöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Gehört der Knopf AId hierher (Klick auf das Symbol öffnet das Menü)?</summary>
    function Handles(const AId: string): Boolean;
    /// <summary>Hat der Knopf AId ein Menü von hier (Pfeil)?</summary>
    function HasMenu(const AId: string): Boolean;
    /// <summary>Klick auf das Symbol eines Werkzeugs; False, wenn der Knopf nicht hierher gehört.</summary>
    function Execute(const AId: string): Boolean;
    /// <summary>Takt der Leiste, solange sie gezeigt wird.</summary>
    procedure Tick;
    /// <summary>Fenster der Werkzeuge ausblenden (Leiste aus).</summary>
    procedure Hide;
    /// <summary>Menü des Knopfs AId an APoint (Bildschirm).</summary>
    procedure Popup(const AId: string; const APoint: TPoint);
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
  FViews := TAtlasIdeDesignerViews.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerCommands.Destroy;
begin
  FViews.Free;
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
  Result := Result + FTools.Buttons(ASettings) + FViews.Buttons(ASettings);
end;

function TAtlasIdeDesignerCommands.Handles(const AId: string): Boolean;
begin
  Result := SameText(AId, cIdSelect) or SameText(AId, cIdArrange);
end;

function TAtlasIdeDesignerCommands.HasMenu(const AId: string): Boolean;
begin
  Result := Handles(AId) or FTools.HasMenu(AId);
end;

function TAtlasIdeDesignerCommands.Execute(const AId: string): Boolean;
begin
  Result := FTools.Toggle(AId) or FViews.Run(AId);
end;

procedure TAtlasIdeDesignerCommands.Tick;
begin
  FTools.Tick;
end;

procedure TAtlasIdeDesignerCommands.Hide;
begin
  FTools.Hide;
end;

procedure TAtlasIdeDesignerCommands.Popup(const AId: string; const APoint: TPoint);
begin
  if FTools.HasMenu(AId) then
  begin
    FTools.Popup(AId, APoint);
  end
  else if SameText(AId, cIdSelect) then
  begin
    FSelect.Popup(APoint);
  end
  else if SameText(AId, cIdArrange) then
  begin
    FArrange.Popup(APoint);
  end;
end;

procedure TAtlasIdeDesignerCommands.UpdateKeys(AWanted: Boolean);
begin
  FSelect.UpdateKeys(AWanted);
  FNavigate.UpdateKeys(AWanted);
  FArrange.UpdateKeys(AWanted);
end;

procedure TAtlasIdeDesignerCommands.ApplyTheme;
begin
  FNavigate.ApplyTheme;
  FArrange.ApplyTheme;
  FTools.ApplyTheme;
  FViews.ApplyTheme;
end;

end.

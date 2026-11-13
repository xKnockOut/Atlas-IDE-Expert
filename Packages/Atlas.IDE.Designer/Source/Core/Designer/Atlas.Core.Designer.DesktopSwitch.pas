unit Atlas.Core.Designer.DesktopSwitch;

// Eigenes Desktop-Layout im Formular-Designer (#2079), ohne VCL und Windows:
// entscheidet je Takt, ob die IDE ein anderes Layout laden soll. Das Laden
// selbst (Desktop-Auswahlfeld der IDE) gehört nicht hierher.
// - Entprellen: Erst wenn die Ansicht (Code oder Designer) Delay ms stehen
//   bleibt, zählt sie. Schnelles Hin- und Herschalten mit F12 löst nichts aus.
// - Designer: Das aktuelle Layout wird gemerkt, dann das Designer-Layout
//   geladen. Ist es schon aktiv, passiert nichts. Fehlt es, gibt es einmal je
//   Name die Meldung Missing.
// - Code: Zurück geht es nur, solange das Designer-Layout noch aktiv ist (hat
//   man im Designer selbst ein anderes gewählt, bleibt es), und zwar auf das
//   gemerkte Layout (Previous) oder das Standard-Layout der IDE (IdeDefault).
// - Während einer Debug-Sitzung (SkipWhileDebugging) und solange ein Projekt
//   lädt, wird nicht umgeschaltet; danach wird die Ansicht neu geprüft, denn
//   die IDE hat ihr Debug-Layout geladen und wieder verlassen.
// - Ausgeschaltet vergisst der Schalter alles; beim Einschalten zählt die
//   aktuelle Ansicht wie ein frischer Wechsel.

interface

type
{$SCOPEDENUMS ON}
  TAtlasDesktopView = (Unknown, Code, Designer);
  TAtlasDesktopReturn = (Previous, IdeDefault);
  TAtlasDesktopActionKind = (None, Load, Missing);
{$SCOPEDENUMS OFF}

  TAtlasDesktopSwitchOptions = record
    Enabled: Boolean;
    /// <summary>Name des Layouts für den Designer; leer = Funktion ohne Wirkung.</summary>
    DesignerLayout: string;
    ReturnTo: TAtlasDesktopReturn;
    SkipWhileDebugging: Boolean;
    /// <summary>So lange (ms) muss eine Ansicht stehen bleiben, bevor umgeschaltet wird.</summary>
    Delay: Integer;
    /// <summary>Vorgaben: aus, zurück zum vorherigen Layout, nicht beim Debuggen, 300 ms.</summary>
    class function Defaults: TAtlasDesktopSwitchOptions; static;
  end;

  /// <summary>Was die IDE gerade zeigt, je Takt erhoben.</summary>
  TAtlasDesktopState = record
    View: TAtlasDesktopView;
    /// <summary>Zeitpunkt in ms (fortlaufender Zähler).</summary>
    Ticks: UInt64;
    Debugging: Boolean;
    ProjectLoading: Boolean;
    /// <summary>Aktives Layout der IDE; leer, wenn unbekannt.</summary>
    CurrentLayout: string;
    /// <summary>Standard-Layout der IDE (Desktop und Layout › Standard); leer, wenn unbekannt.</summary>
    DefaultLayout: string;
    /// <summary>Vorhandene Layouts.</summary>
    Layouts: TArray<string>;
  end;

  TAtlasDesktopAction = record
    Kind: TAtlasDesktopActionKind;
    /// <summary>Zu ladendes bzw. fehlendes Layout.</summary>
    Layout: string;
    /// <summary>True beim Wechsel in den Designer (danach bekommt der Designer den Fokus zurück).</summary>
    ToDesigner: Boolean;
    class function Nothing: TAtlasDesktopAction; static;
  end;

  TAtlasDesktopSwitch = class
  private
    FView: TAtlasDesktopView;
    FSince: UInt64;
    FApplied: TAtlasDesktopView;
    FRemembered: string;
    FMissing: string;
    FWasEnabled: Boolean;
    function ToDesigner(const AOptions: TAtlasDesktopSwitchOptions;
      const AState: TAtlasDesktopState): TAtlasDesktopAction;
    function ToCode(const AOptions: TAtlasDesktopSwitchOptions; const AState: TAtlasDesktopState): TAtlasDesktopAction;
  public
    /// <summary>Alles vergessen (gemerktes Layout, Entprellen, gemeldetes fehlendes Layout).</summary>
    procedure Reset;
    /// <summary>Ein Takt: was jetzt zu tun ist. Load heißt, die IDE soll Layout laden.</summary>
    function Step(const AOptions: TAtlasDesktopSwitchOptions; const AState: TAtlasDesktopState): TAtlasDesktopAction;
    /// <summary>Layout, das beim Wechsel in den Designer aktiv war; leer ohne.</summary>
    property Remembered: string read FRemembered;
  end;

  TAtlasDesktopLayouts = class
  public
    /// <summary>Gibt es AName in ALayouts (ohne Groß-/Kleinschreibung)?</summary>
    class function Contains(const ALayouts: TArray<string>; const AName: string): Boolean; static;
    /// <summary>Echte Layouts aus den Einträgen des Desktop-Auswahlfelds: ohne leere und ohne „<kein>“.</summary>
    class function Usable(const AItems: TArray<string>): TArray<string>; static;
    /// <summary>Anzeigename in ALayouts zum gespeicherten Namen AStored (Registry Session\DefaultDesktopName).
    /// Die mitgelieferten Layouts stehen dort englisch (Default Layout), das Auswahlfeld zeigt sie in der Sprache
    /// der IDE (Standard-Layout); verglichen wird zuerst genau, dann ohne Leer- und Bindestriche, dann über die
    /// bekannten Übersetzungen. Leer, wenn nichts passt.</summary>
    class function DisplayName(const ALayouts: TArray<string>; const AStored: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDesktopSwitchOptions }

class function TAtlasDesktopSwitchOptions.Defaults: TAtlasDesktopSwitchOptions;
begin
  Result := Default(TAtlasDesktopSwitchOptions);
  Result.ReturnTo := TAtlasDesktopReturn.Previous;
  Result.SkipWhileDebugging := True;
  Result.Delay := 300;
end;

{ TAtlasDesktopAction }

class function TAtlasDesktopAction.Nothing: TAtlasDesktopAction;
begin
  Result := Default(TAtlasDesktopAction);
  Result.Kind := TAtlasDesktopActionKind.None;
end;

function LoadAction(const ALayout: string; AToDesigner: Boolean): TAtlasDesktopAction;
begin
  Result := TAtlasDesktopAction.Nothing;
  Result.Kind := TAtlasDesktopActionKind.Load;
  Result.Layout := ALayout;
  Result.ToDesigner := AToDesigner;
end;

{ TAtlasDesktopLayouts }

class function TAtlasDesktopLayouts.Contains(const ALayouts: TArray<string>; const AName: string): Boolean;
var
  mLayout: string;
begin
  Result := False;
  for mLayout in ALayouts do
  begin
    if SameText(mLayout, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasDesktopLayouts.Usable(const AItems: TArray<string>): TArray<string>;
var
  mItem: string;
  mCount: Integer;
begin
  SetLength(Result, Length(AItems));
  mCount := 0;
  for mItem in AItems do
  begin
    if (Trim(mItem) <> '') and not mItem.StartsWith('<') then
    begin
      Result[mCount] := mItem;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

/// <summary>Name ohne Leer- und Bindestriche, klein.</summary>
function Compact(const AName: string): string;
begin
  Result := AName.Replace(' ', '').Replace('-', '').ToLower;
end;

/// <summary>Bekannte Anzeigenamen des mitgelieferten Layouts AStored (englischer Name) in anderen Sprachen der IDE.
/// </summary>
function Translations(const AStored: string): TArray<string>;
begin
  Result := nil;
  if SameText(Compact(AStored), 'defaultlayout') then
  begin
    Result := TArray<string>.Create('Standard-Layout', 'Disposition par défaut');
  end
  else if SameText(Compact(AStored), 'startuplayout') then
  begin
    Result := TArray<string>.Create('Start-Layout', 'Disposition de démarrage');
  end
  else if SameText(Compact(AStored), 'debuglayout') then
  begin
    Result := TArray<string>.Create('Debug-Layout', 'Disposition de débogage');
  end;
end;

class function TAtlasDesktopLayouts.DisplayName(const ALayouts: TArray<string>; const AStored: string): string;
var
  mLayout: string;
  mTranslation: string;
begin
  Result := '';
  if Trim(AStored) = '' then
  begin
    Exit;
  end;
  for mLayout in ALayouts do
  begin
    if SameText(mLayout, AStored) then
    begin
      Exit(mLayout);
    end;
  end;
  for mLayout in ALayouts do
  begin
    if Compact(mLayout) = Compact(AStored) then
    begin
      Exit(mLayout);
    end;
  end;
  for mTranslation in Translations(AStored) do
  begin
    for mLayout in ALayouts do
    begin
      if Compact(mLayout) = Compact(mTranslation) then
      begin
        Exit(mLayout);
      end;
    end;
  end;
end;

{ TAtlasDesktopSwitch }

procedure TAtlasDesktopSwitch.Reset;
begin
  FView := TAtlasDesktopView.Unknown;
  FSince := 0;
  FApplied := TAtlasDesktopView.Unknown;
  FRemembered := '';
  FMissing := '';
end;

function TAtlasDesktopSwitch.ToDesigner(const AOptions: TAtlasDesktopSwitchOptions;
  const AState: TAtlasDesktopState): TAtlasDesktopAction;
begin
  Result := TAtlasDesktopAction.Nothing;
  FApplied := TAtlasDesktopView.Designer;
  if SameText(AState.CurrentLayout, AOptions.DesignerLayout) then
  begin
    Exit;
  end;
  if not TAtlasDesktopLayouts.Contains(AState.Layouts, AOptions.DesignerLayout) then
  begin
    // Einmal je Name melden, nicht bei jedem Wechsel in den Designer.
    if not SameText(FMissing, AOptions.DesignerLayout) then
    begin
      FMissing := AOptions.DesignerLayout;
      Result.Kind := TAtlasDesktopActionKind.Missing;
      Result.Layout := AOptions.DesignerLayout;
    end;
    Exit;
  end;
  FRemembered := AState.CurrentLayout;
  Result := LoadAction(AOptions.DesignerLayout, True);
end;

function TAtlasDesktopSwitch.ToCode(const AOptions: TAtlasDesktopSwitchOptions;
  const AState: TAtlasDesktopState): TAtlasDesktopAction;
var
  mTarget: string;
begin
  Result := TAtlasDesktopAction.Nothing;
  FApplied := TAtlasDesktopView.Code;
  // Nur zurück, solange das Designer-Layout aktiv ist; ein im Designer selbst gewähltes Layout bleibt.
  if not SameText(AState.CurrentLayout, AOptions.DesignerLayout) then
  begin
    FRemembered := '';
    Exit;
  end;
  if AOptions.ReturnTo = TAtlasDesktopReturn.IdeDefault then
  begin
    mTarget := AState.DefaultLayout;
  end
  else
  begin
    mTarget := FRemembered;
  end;
  FRemembered := '';
  if (mTarget = '') or SameText(mTarget, AOptions.DesignerLayout) or
    not TAtlasDesktopLayouts.Contains(AState.Layouts, mTarget) then
  begin
    Exit;
  end;
  Result := LoadAction(mTarget, False);
end;

function TAtlasDesktopSwitch.Step(const AOptions: TAtlasDesktopSwitchOptions;
  const AState: TAtlasDesktopState): TAtlasDesktopAction;
begin
  Result := TAtlasDesktopAction.Nothing;
  if not AOptions.Enabled or (AOptions.DesignerLayout = '') then
  begin
    if FWasEnabled then
    begin
      Reset;
    end;
    FWasEnabled := False;
    Exit;
  end;
  FWasEnabled := True;
  if AState.View <> FView then
  begin
    FView := AState.View;
    FSince := AState.Ticks;
    Exit;
  end;
  if (FView = TAtlasDesktopView.Unknown) or (FView = FApplied) or (AState.Ticks < FSince) or
    (AState.Ticks - FSince < UInt64(AOptions.Delay)) then
  begin
    Exit;
  end;
  if (AState.Debugging and AOptions.SkipWhileDebugging) or AState.ProjectLoading then
  begin
    // Die IDE wechselt beim Debuggen selbst; danach die Ansicht neu prüfen.
    FApplied := TAtlasDesktopView.Unknown;
    Exit;
  end;
  if FView = TAtlasDesktopView.Designer then
  begin
    Result := ToDesigner(AOptions, AState);
  end
  else
  begin
    Result := ToCode(AOptions, AState);
  end;
end;

end.

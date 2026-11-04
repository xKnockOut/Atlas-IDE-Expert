unit Atlas.Core.Debug.Unavailable;

// Erklärung „kein Zugriff auf Wert“ beim Debuggen (#840), ohne VCL und Open
// Tools API:
//   - Erkennen: Fehlertext des Debuggers gegen die bekannten Texte der IDE
//     (KnownTexts, deutsch und englisch; Teiltexte ohne Groß-/Kleinschreibung,
//     „*“ steht für beliebig viel). Die Liste wird hier gepflegt; eigene
//     Ergänzungen liest die IDE-Schicht aus
//     %LOCALAPPDATA%\Atlas\debug-unavailable.txt (eine je Zeile, „#“ leitet
//     einen Kommentar ein).
//   - Tatsachen: Startkonfiguration (Name, Debug-Informationen, lokale
//     Symbole, Optimierung, Debug-DCUs, beim Start festgehalten), ob der Halt
//     in Bibliothekscode liegt, und die Antwort von atlas/debugUnavailable
//     (Schalter D, L, O mit Herkunft, Routine, Lebensdauer, Korrekturen).
//     Stammt ein Schalter aus der .dproj oder der Vorgabe, gilt der Wert der
//     Startkonfiguration: Der Server kennt nur die aktive Konfiguration.
//   - Ursache in fester Reihenfolge, die erste zutreffende gewinnt:
//       1. Startkonfiguration ohne Debug-Informationen (Release),
//       2. $D- bzw. $L- an der Stelle,
//       3. $O+ (Variable vermutlich in einem Register; mit Hinweis, wenn sie
//          am Halt noch nicht oder nicht mehr gebraucht wird),
//       4. Lebensdauer überschritten oder noch nicht begonnen (vermutlich),
//       5. Routine ist inline,
//       6. Bibliotheksrahmen (RTL, VCL) ohne Debug-DCUs.
//     Ohne Treffer „Ursache unbekannt“ mit den geprüften Punkten.
//   - Korrekturen je Ursache: mit Debug neu starten, {$OPTIMIZATION OFF/ON}
//     um die Routine, {$O-} am Unit-Anfang, Debug-DCUs einschalten, zur
//     Direktive springen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  {$SCOPEDENUMS ON}
  TAtlasUnavailableCause = (Unknown, ReleaseBuild, NoDebugInfo, NoLocalSymbols, Optimization, Lifetime,
    InlineRoutine, LibraryFrame);
  /// <summary>Geprüfte Punkte in der Reihenfolge der Ursachen.</summary>
  TAtlasUnavailableCheck = (Configuration, Symbols, Optimization, Lifetime, InlineRoutine, LibraryFrame);
  TAtlasUnavailableFix = (RestartWithDebug, RoutineOptimization, UnitOptimization, DebugDcus, ShowDirective);
  TAtlasValueLifetime = (Unknown, Unused, Before, Within, After);
  TAtlasSwitchSource = (Default, Project, Directive, Include);
  {$SCOPEDENUMS OFF}

  TAtlasUnavailableChecks = TArray<TAtlasUnavailableCheck>;
  TAtlasUnavailableFixes = TArray<TAtlasUnavailableFix>;

  /// <summary>Schalter D, L oder O an der Stelle laut Server.</summary>
  TAtlasUnavailableSwitch = record
    Known: Boolean;
    /// <summary>„+“ oder „-“.</summary>
    Value: string;
    Source: TAtlasSwitchSource;
    /// <summary>Eigenschaft der .dproj bzw. Direktive („{$O+}“).</summary>
    OriginText: string;
    FileName: string;
    /// <summary>Zeile der Direktive, 0-basiert; -1 ohne.</summary>
    Line: Integer;
    /// <summary>Datei und Zeile einer Direktive bekannt.</summary>
    function IsDirective: Boolean;
  end;

  /// <summary>Beim Start der Debug-Sitzung festgehaltene Konfiguration; Werte wie in der .dproj.</summary>
  TAtlasUnavailableLaunch = record
    Known: Boolean;
    Configuration: string;
    /// <summary>DCC_DebugInformation, DCC_LocalDebugSymbols, DCC_Optimize, DCC_DebugDCUs; '' = Vorgabe.</summary>
    DebugInfo: string;
    LocalSymbols: string;
    Optimization: string;
    DebugDcus: string;
  end;

  TAtlasUnavailableFacts = record
    Launch: TAtlasUnavailableLaunch;
    /// <summary>Halt in einer Datei außerhalb des eigenen Codes (RTL, VCL, Komponenten).</summary>
    LibraryFrame: Boolean;
    /// <summary>Antwort des Servers gelesen.</summary>
    Server: Boolean;
    DebugInfo: TAtlasUnavailableSwitch;
    LocalSymbols: TAtlasUnavailableSwitch;
    Optimization: TAtlasUnavailableSwitch;
    RoutineName: string;
    RoutineInline: Boolean;
    /// <summary>Lokale Variable, Parameter, Result, Inline- oder Schleifenvariable.</summary>
    Local: Boolean;
    Parameter: Boolean;
    /// <summary>Erste und letzte Verwendung, 0-basiert; -1 ohne.</summary>
    FirstUse: Integer;
    LastUse: Integer;
    Lifetime: TAtlasValueLifetime;
    RoutineEdit: TLspWorkspaceEdit;
    UnitEdit: TLspWorkspaceEdit;
    /// <summary>Ohne Server: nur die Tatsachen des Plugins.</summary>
    class function Create(const ALaunch: TAtlasUnavailableLaunch; ALibraryFrame: Boolean): TAtlasUnavailableFacts;
      static;
    /// <summary>Antwort von atlas/debugUnavailable übernehmen; null oder Unlesbares lässt Server False.</summary>
    procedure ReadServer(const AValue: TJSONValue);
  end;

  TAtlasUnavailableExplanation = record
    Cause: TAtlasUnavailableCause;
    /// <summary>Schalter, der die Ursache trägt (D, L oder O); Known False ohne.</summary>
    Switch: TAtlasUnavailableSwitch;
    /// <summary>Konfiguration des Starts (Ursache ReleaseBuild).</summary>
    Configuration: string;
    /// <summary>Bei Optimization und Lifetime: Lage des Halts zur Verwendung der Variablen.</summary>
    Lifetime: TAtlasValueLifetime;
    RoutineName: string;
    /// <summary>Geprüfte Punkte bis zur Ursache (bei Unknown alle).</summary>
    Checked: TAtlasUnavailableChecks;
    Fixes: TAtlasUnavailableFixes;
    function HasFix(AFix: TAtlasUnavailableFix): Boolean;
  end;

  TAtlasDebugUnavailable = record
  public const
    /// <summary>Bekannte Fehlertexte der IDE (Win32-Debugger und LLDB, deutsch und englisch). Hier pflegen.
    /// </summary>
    KnownTexts: array[0..18] of string = (
      'inaccessible value',
      'inaccessible here due to optimization',
      'not accessible here due to optimization',
      'eliminated by linker',
      'optimized out',
      'variable not available',
      'value not available',
      'undeclared identifier',
      'no debug info',
      'kein zugriff',
      'nicht zugreifbar',
      'nicht zugänglich',
      'unzugänglich',
      'wegen der optimierung nicht',
      'aufgrund der optimierung nicht',
      'vom linker entfernt',
      'wegoptimiert',
      'wert nicht verfügbar',
      'undeklarierter bezeichner');
    UserFileName = 'debug-unavailable.txt';
    LifetimeNames: array[TAtlasValueLifetime] of string = ('unknown', 'unused', 'before', 'within', 'after');
  public
    /// <summary>Passt AText zu einem Muster („*“ = beliebig viel, ohne Groß-/Kleinschreibung)?</summary>
    class function MatchesPattern(const AText, APattern: string): Boolean; static;
    /// <summary>Ist AText ein bekannter Text für „kein Zugriff“ (KnownTexts oder AExtra)?</summary>
    class function IsUnavailable(const AText: string; const AExtra: TArray<string>): Boolean; static;
    /// <summary>Muster aus der Datei der Ergänzungen: eine je Zeile, ohne Leerzeilen und „#“-Kommentare.
    /// </summary>
    class function ParsePatterns(const AText: string): TArray<string>; static;
    /// <summary>Erster Bezeichner des Ausdrucks („Self.FList.Count“ → „Self“, „Kunden[I].Name“ → „Kunden“).
    /// </summary>
    class function RootName(const AExpression: string): string; static;
    /// <summary>Wert einer Projektoption als Schalter: '' = ADefault; false, 0 und „-“ = aus.</summary>
    class function OptionOn(const AValue: string; ADefault: Boolean): Boolean; static;
    /// <summary>Ursache, geprüfte Punkte und Korrekturen in der Reihenfolge oben.</summary>
    class function Explain(const AFacts: TAtlasUnavailableFacts): TAtlasUnavailableExplanation; static;
    /// <summary>Vorschau einer Textkorrektur: je Einfügung „Zeile n: Text“ (1-basiert).</summary>
    class function PreviewLines(const AEdit: TLspWorkspaceEdit): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils;

const
  SwitchSources: array[TAtlasSwitchSource] of string = ('default', 'project', 'directive', 'include');

function SourceOf(const AText: string): TAtlasSwitchSource;
var
  Source: TAtlasSwitchSource;
begin
  Result := TAtlasSwitchSource.Default;
  for Source := Low(TAtlasSwitchSource) to High(TAtlasSwitchSource) do
  begin
    if SwitchSources[Source] = AText then
    begin
      Result := Source;
    end;
  end;
end;

function LifetimeOf(const AText: string): TAtlasValueLifetime;
var
  Lifetime: TAtlasValueLifetime;
begin
  Result := TAtlasValueLifetime.Unknown;
  for Lifetime := Low(TAtlasValueLifetime) to High(TAtlasValueLifetime) do
  begin
    if TAtlasDebugUnavailable.LifetimeNames[Lifetime] = AText then
    begin
      Result := Lifetime;
    end;
  end;
end;

function SwitchOf(AEntry: TJSONObject): TAtlasUnavailableSwitch;
var
  Origin: TJSONObject;
begin
  Result := Default(TAtlasUnavailableSwitch);
  Result.Line := -1;
  Result.Known := True;
  Result.Value := AEntry.GetValue<string>('value', '');
  if AEntry.TryGetValue<TJSONObject>('origin', Origin) then
  begin
    Result.Source := SourceOf(Origin.GetValue<string>('kind', ''));
    Result.OriginText := Origin.GetValue<string>('text', '');
    Result.FileName := Origin.GetValue<string>('file', '');
    Result.Line := Origin.GetValue<Integer>('line', -1);
  end;
end;

function IsIdentifierChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

type
  /// <summary>Prüft die Ursachen der Reihe nach; jede Stufe meldet True, wenn sie die Ursache gefunden hat.</summary>
  TUnavailableExplainer = record
  private
    FFacts: TAtlasUnavailableFacts;
    FNoSwitch: TAtlasUnavailableSwitch;
    /// <summary>Wirksamer Stand eines Schalters: Direktive aus dem Server, sonst die Startkonfiguration, sonst
    /// der Server.</summary>
    function IsOn(const ASwitch: TAtlasUnavailableSwitch; const ALaunchValue: string; ADefault: Boolean): Boolean;
    procedure Check(ACheck: TAtlasUnavailableCheck);
    procedure Fix(AFix: TAtlasUnavailableFix);
    procedure OptimizationFixes;
    procedure Found(ACause: TAtlasUnavailableCause; const ASwitch: TAtlasUnavailableSwitch);
    /// <summary>Ursache an einem Schalter: Direktive zeigen oder mit Debug-Informationen neu starten.</summary>
    procedure FoundSwitch(ACause: TAtlasUnavailableCause; const ASwitch: TAtlasUnavailableSwitch);
    function ReleaseBuild: Boolean;
    function Symbols: Boolean;
    function Optimization: Boolean;
    function Lifetime: Boolean;
    function InlineRoutine: Boolean;
    function LibraryFrame: Boolean;
  public
    Explanation: TAtlasUnavailableExplanation;
    class function Create(const AFacts: TAtlasUnavailableFacts): TUnavailableExplainer; static;
    procedure Run;
  end;

class function TUnavailableExplainer.Create(const AFacts: TAtlasUnavailableFacts): TUnavailableExplainer;
begin
  Result.FFacts := AFacts;
  Result.FNoSwitch := Default(TAtlasUnavailableSwitch);
  Result.FNoSwitch.Line := -1;
  Result.Explanation := Default(TAtlasUnavailableExplanation);
  Result.Explanation.RoutineName := AFacts.RoutineName;
  Result.Explanation.Configuration := AFacts.Launch.Configuration;
  Result.Explanation.Switch := Result.FNoSwitch;
end;

function TUnavailableExplainer.IsOn(const ASwitch: TAtlasUnavailableSwitch; const ALaunchValue: string;
  ADefault: Boolean): Boolean;
begin
  if ASwitch.Known and ((ASwitch.Source = TAtlasSwitchSource.Directive) or
    (ASwitch.Source = TAtlasSwitchSource.Include)) then
  begin
    Result := ASwitch.Value <> '-';
  end
  else if FFacts.Launch.Known then
  begin
    Result := TAtlasDebugUnavailable.OptionOn(ALaunchValue, ADefault);
  end
  else if ASwitch.Known then
  begin
    Result := ASwitch.Value <> '-';
  end
  else
  begin
    Result := ADefault;
  end;
end;

procedure TUnavailableExplainer.Check(ACheck: TAtlasUnavailableCheck);
begin
  Explanation.Checked := Explanation.Checked + [ACheck];
end;

procedure TUnavailableExplainer.Fix(AFix: TAtlasUnavailableFix);
begin
  if not Explanation.HasFix(AFix) then
  begin
    Explanation.Fixes := Explanation.Fixes + [AFix];
  end;
end;

procedure TUnavailableExplainer.OptimizationFixes;
begin
  if not FFacts.RoutineEdit.IsEmpty then
  begin
    Fix(TAtlasUnavailableFix.RoutineOptimization);
  end;
  if not FFacts.UnitEdit.IsEmpty then
  begin
    Fix(TAtlasUnavailableFix.UnitOptimization);
  end;
  if FFacts.Optimization.IsDirective then
  begin
    Fix(TAtlasUnavailableFix.ShowDirective);
  end;
end;

procedure TUnavailableExplainer.Found(ACause: TAtlasUnavailableCause; const ASwitch: TAtlasUnavailableSwitch);
begin
  Explanation.Cause := ACause;
  Explanation.Switch := ASwitch;
end;

procedure TUnavailableExplainer.FoundSwitch(ACause: TAtlasUnavailableCause; const ASwitch: TAtlasUnavailableSwitch);
begin
  Found(ACause, ASwitch);
  if ASwitch.IsDirective then
  begin
    Fix(TAtlasUnavailableFix.ShowDirective);
  end
  else
  begin
    Fix(TAtlasUnavailableFix.RestartWithDebug);
  end;
end;

function TUnavailableExplainer.ReleaseBuild: Boolean;
begin
  // 1. Start ohne Debug-Informationen (Release).
  Check(TAtlasUnavailableCheck.Configuration);
  Result := FFacts.Launch.Known and not TAtlasDebugUnavailable.OptionOn(FFacts.Launch.DebugInfo, True);
  if Result then
  begin
    Found(TAtlasUnavailableCause.ReleaseBuild, FNoSwitch);
    Fix(TAtlasUnavailableFix.RestartWithDebug);
  end;
end;

function TUnavailableExplainer.Symbols: Boolean;
begin
  // 2. $D- oder $L- an der Stelle; lokale Symbole zählen nur für lokale Namen.
  Check(TAtlasUnavailableCheck.Symbols);
  Result := True;
  if not IsOn(FFacts.DebugInfo, FFacts.Launch.DebugInfo, True) then
  begin
    FoundSwitch(TAtlasUnavailableCause.NoDebugInfo, FFacts.DebugInfo);
  end
  else if (FFacts.Local or not FFacts.Server) and not IsOn(FFacts.LocalSymbols, FFacts.Launch.LocalSymbols,
    True) then
  begin
    FoundSwitch(TAtlasUnavailableCause.NoLocalSymbols, FFacts.LocalSymbols);
  end
  else
  begin
    Result := False;
  end;
end;

function TUnavailableExplainer.Optimization: Boolean;
begin
  // 3. Optimierung: nur lokale Namen liegen in Registern (ohne Server unbekannt, dann zählt es).
  Check(TAtlasUnavailableCheck.Optimization);
  Result := (FFacts.Local or not FFacts.Server) and IsOn(FFacts.Optimization, FFacts.Launch.Optimization, True);
  if Result then
  begin
    Found(TAtlasUnavailableCause.Optimization, FFacts.Optimization);
    if FFacts.Lifetime in [TAtlasValueLifetime.Unused, TAtlasValueLifetime.Before, TAtlasValueLifetime.After] then
    begin
      Explanation.Lifetime := FFacts.Lifetime;
    end;
    OptimizationFixes;
  end;
end;

function TUnavailableExplainer.Lifetime: Boolean;
begin
  // 4. Lebensdauer: am Halt noch nicht oder nicht mehr gebraucht (Näherung des Servers).
  Check(TAtlasUnavailableCheck.Lifetime);
  Result := FFacts.Local and (FFacts.Lifetime in [TAtlasValueLifetime.Unused, TAtlasValueLifetime.Before,
    TAtlasValueLifetime.After]);
  if Result then
  begin
    Found(TAtlasUnavailableCause.Lifetime, FNoSwitch);
    Explanation.Lifetime := FFacts.Lifetime;
  end;
end;

function TUnavailableExplainer.InlineRoutine: Boolean;
begin
  // 5. inline-Routine.
  Check(TAtlasUnavailableCheck.InlineRoutine);
  Result := FFacts.RoutineInline;
  if Result then
  begin
    Found(TAtlasUnavailableCause.InlineRoutine, FNoSwitch);
  end;
end;

function TUnavailableExplainer.LibraryFrame: Boolean;
begin
  // 6. Bibliotheksrahmen ohne Debug-DCUs.
  Check(TAtlasUnavailableCheck.LibraryFrame);
  Result := FFacts.LibraryFrame and not TAtlasDebugUnavailable.OptionOn(FFacts.Launch.DebugDcus, False);
  if Result then
  begin
    Found(TAtlasUnavailableCause.LibraryFrame, FNoSwitch);
    Fix(TAtlasUnavailableFix.DebugDcus);
  end;
end;

procedure TUnavailableExplainer.Run;
var
  mDone: Boolean;
begin
  mDone := ReleaseBuild;
  if not mDone then
  begin
    mDone := Symbols;
  end;
  if not mDone then
  begin
    mDone := Optimization;
  end;
  if not mDone then
  begin
    mDone := Lifetime;
  end;
  if not mDone then
  begin
    mDone := InlineRoutine;
  end;
  if not mDone then
  begin
    LibraryFrame;
  end;
end;

{ TAtlasUnavailableSwitch }

function TAtlasUnavailableSwitch.IsDirective: Boolean;
begin
  Result := Known and (FileName <> '') and (Line >= 0) and
    ((Source = TAtlasSwitchSource.Directive) or (Source = TAtlasSwitchSource.Include));
end;

{ TAtlasUnavailableFacts }

class function TAtlasUnavailableFacts.Create(const ALaunch: TAtlasUnavailableLaunch;
  ALibraryFrame: Boolean): TAtlasUnavailableFacts;
begin
  Result := Default(TAtlasUnavailableFacts);
  Result.Launch := ALaunch;
  Result.LibraryFrame := ALibraryFrame;
  Result.FirstUse := -1;
  Result.LastUse := -1;
  Result.DebugInfo.Line := -1;
  Result.LocalSymbols.Line := -1;
  Result.Optimization.Line := -1;
end;

procedure ReadSwitches(var AFacts: TAtlasUnavailableFacts; ARoot: TJSONObject);
var
  mSwitches: TJSONArray;
  mItem: TJSONValue;
  mName: string;
begin
  if not ARoot.TryGetValue<TJSONArray>('switches', mSwitches) then
  begin
    Exit;
  end;
  for mItem in mSwitches do
  begin
    if mItem is TJSONObject then
    begin
      mName := TJSONObject(mItem).GetValue<string>('name', '');
      if mName = 'D' then
      begin
        AFacts.DebugInfo := SwitchOf(TJSONObject(mItem));
      end
      else if mName = 'L' then
      begin
        AFacts.LocalSymbols := SwitchOf(TJSONObject(mItem));
      end
      else if mName = 'O' then
      begin
        AFacts.Optimization := SwitchOf(TJSONObject(mItem));
      end;
    end;
  end;
end;

procedure ReadFixes(var AFacts: TAtlasUnavailableFacts; ARoot: TJSONObject);
var
  mFixes, mEdit: TJSONObject;
begin
  if not ARoot.TryGetValue<TJSONObject>('fixes', mFixes) then
  begin
    Exit;
  end;
  if mFixes.TryGetValue<TJSONObject>('routineOptimization', mEdit) then
  begin
    AFacts.RoutineEdit := TLspWorkspaceEdit.FromJson(mEdit);
  end;
  if mFixes.TryGetValue<TJSONObject>('unitOptimization', mEdit) then
  begin
    AFacts.UnitEdit := TLspWorkspaceEdit.FromJson(mEdit);
  end;
end;

procedure TAtlasUnavailableFacts.ReadServer(const AValue: TJSONValue);
var
  Root, Routine, Variable: TJSONObject;
begin
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Root := TJSONObject(AValue);
  Server := True;
  ReadSwitches(Self, Root);
  if Root.TryGetValue<TJSONObject>('routine', Routine) then
  begin
    RoutineName := Routine.GetValue<string>('name', '');
    RoutineInline := Routine.GetValue<Boolean>('inline', False);
  end;
  if Root.TryGetValue<TJSONObject>('variable', Variable) then
  begin
    Local := Variable.GetValue<Boolean>('local', False);
    Parameter := Variable.GetValue<Boolean>('parameter', False);
    FirstUse := Variable.GetValue<Integer>('firstUse', -1);
    LastUse := Variable.GetValue<Integer>('lastUse', -1);
    Lifetime := LifetimeOf(Variable.GetValue<string>('lifetime', ''));
  end;
  ReadFixes(Self, Root);
end;

{ TAtlasUnavailableExplanation }

function TAtlasUnavailableExplanation.HasFix(AFix: TAtlasUnavailableFix): Boolean;
var
  Fix: TAtlasUnavailableFix;
begin
  Result := False;
  for Fix in Fixes do
  begin
    if Fix = AFix then
    begin
      Exit(True);
    end;
  end;
end;

{ TAtlasDebugUnavailable }

class function TAtlasDebugUnavailable.MatchesPattern(const AText, APattern: string): Boolean;
var
  Text: string;
  Part: string;
  From, Found: Integer;
begin
  Result := False;
  if Trim(APattern) = '' then
  begin
    Exit;
  end;
  Text := AnsiLowerCase(AText);
  From := 1;
  for Part in AnsiLowerCase(Trim(APattern)).Split(['*']) do
  begin
    if Part = '' then
    begin
      Continue;
    end;
    Found := PosEx(Part, Text, From);
    if Found = 0 then
    begin
      Exit;
    end;
    From := Found + Length(Part);
  end;
  Result := True;
end;

class function TAtlasDebugUnavailable.IsUnavailable(const AText: string; const AExtra: TArray<string>): Boolean;
var
  Pattern: string;
begin
  Result := False;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  for Pattern in KnownTexts do
  begin
    if MatchesPattern(AText, Pattern) then
    begin
      Exit(True);
    end;
  end;
  for Pattern in AExtra do
  begin
    if MatchesPattern(AText, Pattern) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasDebugUnavailable.ParsePatterns(const AText: string): TArray<string>;
var
  Line, Pattern: string;
  Comment: Integer;
begin
  Result := nil;
  for Line in AText.Split([#13#10, #10, #13]) do
  begin
    Pattern := Line;
    Comment := Pos('#', Pattern);
    if Comment > 0 then
    begin
      Pattern := Copy(Pattern, 1, Comment - 1);
    end;
    Pattern := Trim(Pattern);
    if Pattern <> '' then
    begin
      Result := Result + [Pattern];
    end;
  end;
end;

class function TAtlasDebugUnavailable.RootName(const AExpression: string): string;
var
  Start, Stop: Integer;
begin
  Start := 1;
  while (Start <= Length(AExpression)) and not IsIdentifierChar(AExpression[Start]) do
  begin
    Inc(Start);
  end;
  Stop := Start;
  while (Stop <= Length(AExpression)) and IsIdentifierChar(AExpression[Stop]) do
  begin
    Inc(Stop);
  end;
  Result := Copy(AExpression, Start, Stop - Start);
end;

class function TAtlasDebugUnavailable.OptionOn(const AValue: string; ADefault: Boolean): Boolean;
var
  Value: string;
begin
  Value := Trim(AValue);
  if Value = '' then
  begin
    Result := ADefault;
  end
  else
  begin
    Result := not (SameText(Value, 'false') or (Value = '0') or (Value = '-') or SameText(Value, 'off'));
  end;
end;

class function TAtlasDebugUnavailable.Explain(const AFacts: TAtlasUnavailableFacts): TAtlasUnavailableExplanation;
var
  Explainer: TUnavailableExplainer;
begin
  Explainer := TUnavailableExplainer.Create(AFacts);
  Explainer.Run;
  Result := Explainer.Explanation;
end;

class function TAtlasDebugUnavailable.PreviewLines(const AEdit: TLspWorkspaceEdit): TArray<string>;
var
  FileEdits: TLspFileEdits;
  Edit: TLspTextEdit;
  Text: string;
begin
  Result := nil;
  for FileEdits in AEdit.Files do
  begin
    for Edit in FileEdits.Edits do
    begin
      Text := Trim(StringReplace(StringReplace(Edit.NewText, #13#10, ' ', [rfReplaceAll]), #10, ' ',
        [rfReplaceAll]));
      Result := Result + [Format('%d: %s', [Edit.StartPos.Line + 1, Text])];
    end;
  end;
end;

end.

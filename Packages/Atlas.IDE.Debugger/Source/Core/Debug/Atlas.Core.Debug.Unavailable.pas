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
    if SwitchSources[Source] = AText then
      Result := Source;
end;

function LifetimeOf(const AText: string): TAtlasValueLifetime;
var
  Lifetime: TAtlasValueLifetime;
begin
  Result := TAtlasValueLifetime.Unknown;
  for Lifetime := Low(TAtlasValueLifetime) to High(TAtlasValueLifetime) do
    if TAtlasDebugUnavailable.LifetimeNames[Lifetime] = AText then
      Result := Lifetime;
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

procedure TAtlasUnavailableFacts.ReadServer(const AValue: TJSONValue);
var
  Root, Routine, Variable, Fixes, Entry, Edit: TJSONObject;
  Switches: TJSONArray;
  Item: TJSONValue;
  Name: string;
begin
  if not (AValue is TJSONObject) then
    Exit;
  Root := TJSONObject(AValue);
  Server := True;
  if Root.TryGetValue<TJSONArray>('switches', Switches) then
    for Item in Switches do
      if Item is TJSONObject then
      begin
        Entry := TJSONObject(Item);
        Name := Entry.GetValue<string>('name', '');
        if Name = 'D' then
          DebugInfo := SwitchOf(Entry)
        else if Name = 'L' then
          LocalSymbols := SwitchOf(Entry)
        else if Name = 'O' then
          Optimization := SwitchOf(Entry);
      end;
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
  if Root.TryGetValue<TJSONObject>('fixes', Fixes) then
  begin
    if Fixes.TryGetValue<TJSONObject>('routineOptimization', Edit) then
      RoutineEdit := TLspWorkspaceEdit.FromJson(Edit);
    if Fixes.TryGetValue<TJSONObject>('unitOptimization', Edit) then
      UnitEdit := TLspWorkspaceEdit.FromJson(Edit);
  end;
end;

{ TAtlasUnavailableExplanation }

function TAtlasUnavailableExplanation.HasFix(AFix: TAtlasUnavailableFix): Boolean;
var
  Fix: TAtlasUnavailableFix;
begin
  Result := False;
  for Fix in Fixes do
    if Fix = AFix then
      Exit(True);
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
    Exit;
  Text := AnsiLowerCase(AText);
  From := 1;
  for Part in AnsiLowerCase(Trim(APattern)).Split(['*']) do
  begin
    if Part = '' then
      Continue;
    Found := PosEx(Part, Text, From);
    if Found = 0 then
      Exit;
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
    Exit;
  for Pattern in KnownTexts do
    if MatchesPattern(AText, Pattern) then
      Exit(True);
  for Pattern in AExtra do
    if MatchesPattern(AText, Pattern) then
      Exit(True);
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
      Pattern := Copy(Pattern, 1, Comment - 1);
    Pattern := Trim(Pattern);
    if Pattern <> '' then
      Result := Result + [Pattern];
  end;
end;

class function TAtlasDebugUnavailable.RootName(const AExpression: string): string;
var
  Start, Stop: Integer;
begin
  Start := 1;
  while (Start <= Length(AExpression)) and not IsIdentifierChar(AExpression[Start]) do
    Inc(Start);
  Stop := Start;
  while (Stop <= Length(AExpression)) and IsIdentifierChar(AExpression[Stop]) do
    Inc(Stop);
  Result := Copy(AExpression, Start, Stop - Start);
end;

class function TAtlasDebugUnavailable.OptionOn(const AValue: string; ADefault: Boolean): Boolean;
var
  Value: string;
begin
  Value := Trim(AValue);
  if Value = '' then
    Result := ADefault
  else
    Result := not (SameText(Value, 'false') or (Value = '0') or (Value = '-') or SameText(Value, 'off'));
end;

class function TAtlasDebugUnavailable.Explain(const AFacts: TAtlasUnavailableFacts): TAtlasUnavailableExplanation;
var
  Explanation: TAtlasUnavailableExplanation;

  // Wirksamer Stand eines Schalters: Direktive aus dem Server, sonst die Startkonfiguration, sonst der Server.
  function IsOn(const ASwitch: TAtlasUnavailableSwitch; const ALaunchValue: string; ADefault: Boolean): Boolean;
  begin
    if ASwitch.Known and ((ASwitch.Source = TAtlasSwitchSource.Directive) or
      (ASwitch.Source = TAtlasSwitchSource.Include)) then
      Result := ASwitch.Value <> '-'
    else if AFacts.Launch.Known then
      Result := OptionOn(ALaunchValue, ADefault)
    else if ASwitch.Known then
      Result := ASwitch.Value <> '-'
    else
      Result := ADefault;
  end;

  procedure Check(ACheck: TAtlasUnavailableCheck);
  begin
    Explanation.Checked := Explanation.Checked + [ACheck];
  end;

  procedure Fix(AFix: TAtlasUnavailableFix);
  begin
    if not Explanation.HasFix(AFix) then
      Explanation.Fixes := Explanation.Fixes + [AFix];
  end;

  procedure OptimizationFixes;
  begin
    if not AFacts.RoutineEdit.IsEmpty then
      Fix(TAtlasUnavailableFix.RoutineOptimization);
    if not AFacts.UnitEdit.IsEmpty then
      Fix(TAtlasUnavailableFix.UnitOptimization);
    if AFacts.Optimization.IsDirective then
      Fix(TAtlasUnavailableFix.ShowDirective);
  end;

  procedure Found(ACause: TAtlasUnavailableCause; const ASwitch: TAtlasUnavailableSwitch);
  begin
    Explanation.Cause := ACause;
    Explanation.Switch := ASwitch;
  end;

var
  NoSwitch: TAtlasUnavailableSwitch;
begin
  Explanation := Default(TAtlasUnavailableExplanation);
  Explanation.RoutineName := AFacts.RoutineName;
  Explanation.Configuration := AFacts.Launch.Configuration;
  NoSwitch := Default(TAtlasUnavailableSwitch);
  NoSwitch.Line := -1;
  Explanation.Switch := NoSwitch;
  // 1. Start ohne Debug-Informationen (Release).
  Check(TAtlasUnavailableCheck.Configuration);
  if AFacts.Launch.Known and not OptionOn(AFacts.Launch.DebugInfo, True) then
  begin
    Found(TAtlasUnavailableCause.ReleaseBuild, NoSwitch);
    Fix(TAtlasUnavailableFix.RestartWithDebug);
    Exit(Explanation);
  end;
  // 2. $D- oder $L- an der Stelle; lokale Symbole zählen nur für lokale Namen.
  Check(TAtlasUnavailableCheck.Symbols);
  if not IsOn(AFacts.DebugInfo, AFacts.Launch.DebugInfo, True) then
  begin
    Found(TAtlasUnavailableCause.NoDebugInfo, AFacts.DebugInfo);
    if AFacts.DebugInfo.IsDirective then
      Fix(TAtlasUnavailableFix.ShowDirective)
    else
      Fix(TAtlasUnavailableFix.RestartWithDebug);
    Exit(Explanation);
  end;
  if (AFacts.Local or not AFacts.Server) and not IsOn(AFacts.LocalSymbols, AFacts.Launch.LocalSymbols, True) then
  begin
    Found(TAtlasUnavailableCause.NoLocalSymbols, AFacts.LocalSymbols);
    if AFacts.LocalSymbols.IsDirective then
      Fix(TAtlasUnavailableFix.ShowDirective)
    else
      Fix(TAtlasUnavailableFix.RestartWithDebug);
    Exit(Explanation);
  end;
  // 3. Optimierung: nur lokale Namen liegen in Registern (ohne Server unbekannt, dann zählt es).
  Check(TAtlasUnavailableCheck.Optimization);
  if (AFacts.Local or not AFacts.Server) and IsOn(AFacts.Optimization, AFacts.Launch.Optimization, True) then
  begin
    Found(TAtlasUnavailableCause.Optimization, AFacts.Optimization);
    if AFacts.Lifetime in [TAtlasValueLifetime.Unused, TAtlasValueLifetime.Before, TAtlasValueLifetime.After] then
      Explanation.Lifetime := AFacts.Lifetime;
    OptimizationFixes;
    Exit(Explanation);
  end;
  // 4. Lebensdauer: am Halt noch nicht oder nicht mehr gebraucht (Näherung des Servers).
  Check(TAtlasUnavailableCheck.Lifetime);
  if AFacts.Local and (AFacts.Lifetime in [TAtlasValueLifetime.Unused, TAtlasValueLifetime.Before,
    TAtlasValueLifetime.After]) then
  begin
    Found(TAtlasUnavailableCause.Lifetime, NoSwitch);
    Explanation.Lifetime := AFacts.Lifetime;
    Exit(Explanation);
  end;
  // 5. inline-Routine.
  Check(TAtlasUnavailableCheck.InlineRoutine);
  if AFacts.RoutineInline then
  begin
    Found(TAtlasUnavailableCause.InlineRoutine, NoSwitch);
    Exit(Explanation);
  end;
  // 6. Bibliotheksrahmen ohne Debug-DCUs.
  Check(TAtlasUnavailableCheck.LibraryFrame);
  if AFacts.LibraryFrame and not OptionOn(AFacts.Launch.DebugDcus, False) then
  begin
    Found(TAtlasUnavailableCause.LibraryFrame, NoSwitch);
    Fix(TAtlasUnavailableFix.DebugDcus);
    Exit(Explanation);
  end;
  Result := Explanation;
end;

class function TAtlasDebugUnavailable.PreviewLines(const AEdit: TLspWorkspaceEdit): TArray<string>;
var
  FileEdits: TLspFileEdits;
  Edit: TLspTextEdit;
  Text: string;
begin
  Result := nil;
  for FileEdits in AEdit.Files do
    for Edit in FileEdits.Edits do
    begin
      Text := Trim(StringReplace(StringReplace(Edit.NewText, #13#10, ' ', [rfReplaceAll]), #10, ' ',
        [rfReplaceAll]));
      Result := Result + [Format('%d: %s', [Edit.StartPos.Line + 1, Text])];
    end;
end;

end.

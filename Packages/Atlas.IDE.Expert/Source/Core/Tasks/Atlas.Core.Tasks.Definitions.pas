unit Atlas.Core.Tasks.Definitions;

// Projektaufgaben (#900), Teil ohne VCL und Open Tools API: der Abschnitt
// "tasks" aus atlas.json.
// - Eine Aufgabe hat name, command, args, cwd, env (Objekt Name → Wert),
//   group (check, build, test, other; Vorgabe other), matcher (Name eines
//   eingebauten Musters oder Objekt mit regex, severityMap und severity), key
//   („Ctrl+Alt+1“, auch Strg/Umschalt), timeoutSec (Vorgabe 600, 0 = ohne
//   Zeitlimit) und beforeBuild (off, warn, block; überschreibt
//   tasks.beforeBuild für diese Aufgabe).
// - Projekt und global: Merge nimmt erst die Aufgaben des Projekts, dann die
//   globalen, deren Name (Groß-/Kleinschreibung egal) im Projekt nicht
//   vorkommt. Doppelte Namen innerhalb einer Datei: die erste gilt.
// - Ungültige Einträge (ohne name oder command, falscher Typ) fallen weg; der
//   Grund steht in Issues (die genaue Prüfung der Datei macht der Server).
// - Variablen in command, args, cwd und env: ${projectDir}, ${groupDir},
//   ${file}, ${fileDir}, ${config}, ${platform}, ${BDS}; unbekannte bleiben
//   stehen. Ohne cwd läuft die Aufgabe im Projektordner.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasTaskGroup = (Check, Build, Test, Other);
  /// <summary>tasks.beforeBuild bzw. beforeBuild einer Aufgabe.</summary>
  TAtlasTaskBeforeBuild = (Off, Warn, Block);
  /// <summary>Eingebaute Muster für Fundstellen; None = keine Auswertung, Custom = eigener regulärer Ausdruck.
  /// </summary>
  TAtlasTaskMatcherKind = (None, Dcc, Pwsh, MsBuild, Generic, Custom);
  TAtlasTaskSeverity = (Error, Warning, Info);
{$SCOPEDENUMS OFF}

  /// <summary>Muster einer Aufgabe; bei Custom mit regulärem Ausdruck und Zuordnung eigener Wörter.</summary>
  TAtlasTaskMatcher = record
    Kind: TAtlasTaskMatcherKind;
    /// <summary>Custom: Ausdruck mit den benannten Gruppen file, line, column, severity, code, message.</summary>
    Regex: string;
    /// <summary>Custom: Wörter aus severityMap (klein) und ihre Schwere, gleich lang.</summary>
    SeverityWords: TArray<string>;
    SeverityValues: TArray<TAtlasTaskSeverity>;
    /// <summary>Schwere ohne erkennbares Wort (severity, Vorgabe error).</summary>
    DefaultSeverity: TAtlasTaskSeverity;
    class function Create(AKind: TAtlasTaskMatcherKind): TAtlasTaskMatcher; static;
  end;

  TAtlasTaskDefinition = record
    Name: string;
    Command: string;
    Args: TArray<string>;
    /// <summary>Arbeitsordner; '' = Projektordner.</summary>
    Cwd: string;
    EnvNames: TArray<string>;
    EnvValues: TArray<string>;
    Group: TAtlasTaskGroup;
    Matcher: TAtlasTaskMatcher;
    /// <summary>Taste wie geschrieben und als TShortCut (0 = keine oder unlesbar).</summary>
    KeyText: string;
    Key: Word;
    /// <summary>Sekunden bis zum Abbruch; 0 = ohne Zeitlimit.</summary>
    TimeoutSec: Integer;
    /// <summary>beforeBuild der Aufgabe; nur mit HasBeforeBuild.</summary>
    HasBeforeBuild: Boolean;
    BeforeBuild: TAtlasTaskBeforeBuild;
    /// <summary>Aus der globalen Datei (%APPDATA%\Atlas\settings.json).</summary>
    Global: Boolean;
    /// <summary>Verhalten vor dem Build: eigenes beforeBuild, sonst AGlobal für Gruppe check, sonst Off.</summary>
    function BeforeBuildFor(AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskBeforeBuild;
    /// <summary>Befehlszeile zum Anzeigen: Programm und Argumente mit Leerzeichen.</summary>
    function CommandLine: string;
  end;

  TAtlasTaskDefinitions = TArray<TAtlasTaskDefinition>;

  /// <summary>Werte der Variablen ${…}.</summary>
  TAtlasTaskVariables = record
    ProjectDir: string;
    GroupDir: string;
    FileName: string;
    Config: string;
    Platform: string;
    Bds: string;
    /// <summary>Text mit eingesetzten Variablen; unbekannte bleiben stehen.</summary>
    function Expand(const AText: string): string;
  end;

  TAtlasTasks = class
  public const
    DefaultTimeoutSec = 600;
    MaxTimeoutSec = 86400;
    GroupNames: array[TAtlasTaskGroup] of string = ('check', 'build', 'test', 'other');
    BeforeBuildNames: array[TAtlasTaskBeforeBuild] of string = ('off', 'warn', 'block');
    MatcherNames: array[TAtlasTaskMatcherKind] of string = ('', 'dcc', 'pwsh', 'msbuild', 'generic', '');
    SeverityNames: array[TAtlasTaskSeverity] of string = ('error', 'warning', 'info');
  public
    /// <summary>Aufgaben aus dem Wurzelobjekt einer atlas.json bzw. settings.json; AIssues nennt verworfene
    /// Einträge.</summary>
    class function Parse(ARoot: TJSONObject; AGlobal: Boolean; var AIssues: TArray<string>): TAtlasTaskDefinitions;
      overload; static;
    /// <summary>Wie Parse aus dem Text der Datei (Kommentare erlaubt); leer bei ungültigem Text.</summary>
    class function Parse(const AText: string; AGlobal: Boolean; var AIssues: TArray<string>): TAtlasTaskDefinitions;
      overload; static;
    /// <summary>Projekt vor global: globale Aufgaben nur, wenn ihr Name im Projekt fehlt.</summary>
    class function Merge(const AProject, AGlobal: TAtlasTaskDefinitions): TAtlasTaskDefinitions; static;
    /// <summary>Index der Aufgabe AName (Groß-/Kleinschreibung egal); -1 ohne.</summary>
    class function IndexOf(const ATasks: TAtlasTaskDefinitions; const AName: string): Integer; static;
    /// <summary>Aufgaben der Gruppe AGroup in ihrer Reihenfolge.</summary>
    class function OfGroup(const ATasks: TAtlasTaskDefinitions; AGroup: TAtlasTaskGroup): TAtlasTaskDefinitions;
      static;
    /// <summary>Aufgaben, die vor dem Build laufen (BeforeBuildFor &lt;&gt; Off).</summary>
    class function BeforeBuild(const ATasks: TAtlasTaskDefinitions;
      AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskDefinitions; static;
    /// <summary>AText als Gruppe; False bei unbekanntem Namen.</summary>
    class function TryGroup(const AText: string; out AGroup: TAtlasTaskGroup): Boolean; static;
    /// <summary>"off", "warn", "block" (Groß-/Kleinschreibung egal); False sonst.</summary>
    class function TryBeforeBuild(const AText: string; out AValue: TAtlasTaskBeforeBuild): Boolean; static;
    /// <summary>tasks.beforeBuild: bekannter Wert klein, sonst "off".</summary>
    class function NormalizedBeforeBuild(const AText: string): string; static;
    class function TrySeverity(const AText: string; out ASeverity: TAtlasTaskSeverity): Boolean; static;
    /// <summary>„Ctrl+Alt+1“, „Strg+Umschalt+F5“ als TShortCut; 0, wenn nicht lesbar.</summary>
    class function ParseKey(const AText: string): Word; static;
    /// <summary>Variablen auf die Aufgabe angewendet: command, args, cwd (leer = ProjectDir) und env.</summary>
    class function Expand(const ATask: TAtlasTaskDefinition; const AVariables: TAtlasTaskVariables):
      TAtlasTaskDefinition; static;
  end;

implementation

uses
  Atlas.Core.Settings.JsonText;

{ TAtlasTaskMatcher }

class function TAtlasTaskMatcher.Create(AKind: TAtlasTaskMatcherKind): TAtlasTaskMatcher;
begin
  Result := Default(TAtlasTaskMatcher);
  Result.Kind := AKind;
  Result.DefaultSeverity := TAtlasTaskSeverity.Error;
end;

{ TAtlasTaskDefinition }

function TAtlasTaskDefinition.BeforeBuildFor(AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskBeforeBuild;
begin
  if HasBeforeBuild then
    Result := BeforeBuild
  else if Group = TAtlasTaskGroup.Check then
    Result := AGlobal
  else
    Result := TAtlasTaskBeforeBuild.Off;
end;

function TAtlasTaskDefinition.CommandLine: string;
var
  Arg: string;
begin
  Result := Command;
  for Arg in Args do
    if Pos(' ', Arg) > 0 then
      Result := Result + ' "' + Arg + '"'
    else
      Result := Result + ' ' + Arg;
end;

{ TAtlasTaskVariables }

function TAtlasTaskVariables.Expand(const AText: string): string;
begin
  Result := AText;
  if Pos('${', Result) = 0 then
    Exit;
  Result := StringReplace(Result, '${projectDir}', ProjectDir, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${groupDir}', GroupDir, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${fileDir}', ExtractFileDir(FileName), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${file}', FileName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${config}', Config, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${platform}', Platform, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '${BDS}', Bds, [rfReplaceAll, rfIgnoreCase]);
end;

{ TAtlasTasks }

class function TAtlasTasks.TryGroup(const AText: string; out AGroup: TAtlasTaskGroup): Boolean;
var
  Group: TAtlasTaskGroup;
begin
  for Group := Low(TAtlasTaskGroup) to High(TAtlasTaskGroup) do
    if SameText(Trim(AText), GroupNames[Group]) then
    begin
      AGroup := Group;
      Exit(True);
    end;
  AGroup := TAtlasTaskGroup.Other;
  Result := False;
end;

class function TAtlasTasks.TryBeforeBuild(const AText: string; out AValue: TAtlasTaskBeforeBuild): Boolean;
var
  Value: TAtlasTaskBeforeBuild;
begin
  for Value := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
    if SameText(Trim(AText), BeforeBuildNames[Value]) then
    begin
      AValue := Value;
      Exit(True);
    end;
  AValue := TAtlasTaskBeforeBuild.Off;
  Result := False;
end;

class function TAtlasTasks.NormalizedBeforeBuild(const AText: string): string;
var
  Value: TAtlasTaskBeforeBuild;
begin
  TryBeforeBuild(AText, Value);
  Result := BeforeBuildNames[Value];
end;

class function TAtlasTasks.TrySeverity(const AText: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  Severity: TAtlasTaskSeverity;
begin
  for Severity := Low(TAtlasTaskSeverity) to High(TAtlasTaskSeverity) do
    if SameText(Trim(AText), SeverityNames[Severity]) then
    begin
      ASeverity := Severity;
      Exit(True);
    end;
  // Übliche andere Schreibweisen.
  Result := True;
  if SameText(Trim(AText), 'information') or SameText(Trim(AText), 'hint') then
    ASeverity := TAtlasTaskSeverity.Info
  else
  begin
    ASeverity := TAtlasTaskSeverity.Error;
    Result := False;
  end;
end;

class function TAtlasTasks.ParseKey(const AText: string): Word;
const
  ShiftBit = $2000;
  CtrlBit = $4000;
  AltBit = $8000;
var
  Parts: TArray<string>;
  Part, Name: string;
  Index, Number: Integer;
  Modifiers, Key: Word;
begin
  Result := 0;
  Parts := Trim(AText).Split(['+']);
  if Length(Parts) = 0 then
    Exit;
  Modifiers := 0;
  for Index := 0 to High(Parts) - 1 do
  begin
    Part := Trim(Parts[Index]);
    if SameText(Part, 'Ctrl') or SameText(Part, 'Strg') or SameText(Part, 'Control') then
      Modifiers := Modifiers or CtrlBit
    else if SameText(Part, 'Shift') or SameText(Part, 'Umschalt') then
      Modifiers := Modifiers or ShiftBit
    else if SameText(Part, 'Alt') then
      Modifiers := Modifiers or AltBit
    else
      Exit;
  end;
  Name := UpperCase(Trim(Parts[High(Parts)]));
  Key := 0;
  if (Length(Name) = 1) and CharInSet(Name[1], ['A'..'Z', '0'..'9']) then
    Key := Ord(Name[1])
  else if (Length(Name) >= 2) and (Name[1] = 'F') and TryStrToInt(Copy(Name, 2, MaxInt), Number) and
    (Number >= 1) and (Number <= 24) then
    Key := $6F + Number;
  // Eine Taste ohne Strg oder Alt würde das Tippen stören (nur Funktionstasten dürfen allein stehen).
  if (Key = 0) or ((Modifiers and (CtrlBit or AltBit) = 0) and (Key < $70)) then
    Exit;
  Result := Modifiers or Key;
end;

function StringOf(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
var
  Value: TJSONValue;
begin
  AValue := '';
  Value := AObject.GetValue(AName);
  Result := Value is TJSONString;
  if Result then
    AValue := TJSONString(Value).Value;
end;

function ParseMatcher(AValue: TJSONValue; const AName: string; var AIssues: TArray<string>): TAtlasTaskMatcher;
var
  Kind: TAtlasTaskMatcherKind;
  Item: TJSONObject;
  Map: TJSONValue;
  Pair: TJSONPair;
  Text: string;
  Severity: TAtlasTaskSeverity;
begin
  Result := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.None);
  if AValue = nil then
    Exit;
  if AValue is TJSONString then
  begin
    for Kind := TAtlasTaskMatcherKind.Dcc to TAtlasTaskMatcherKind.Generic do
      if SameText(Trim(AValue.Value), TAtlasTasks.MatcherNames[Kind]) then
        Exit(TAtlasTaskMatcher.Create(Kind));
    if (Trim(AValue.Value) <> '') and not SameText(Trim(AValue.Value), 'none') then
      AIssues := AIssues + [Format('%s: unbekanntes Muster "%s", Ausgabe ohne Befunde', [AName, AValue.Value])];
    Exit;
  end;
  if not (AValue is TJSONObject) then
  begin
    AIssues := AIssues + [Format('%s: matcher muss Name oder Objekt sein', [AName])];
    Exit;
  end;
  Item := TJSONObject(AValue);
  if not StringOf(Item, 'regex', Text) or (Text = '') then
  begin
    AIssues := AIssues + [Format('%s: matcher ohne regex', [AName])];
    Exit;
  end;
  Result := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  Result.Regex := Text;
  if StringOf(Item, 'severity', Text) and TAtlasTasks.TrySeverity(Text, Severity) then
    Result.DefaultSeverity := Severity;
  Map := Item.GetValue('severityMap');
  if Map is TJSONObject then
    for Pair in TJSONObject(Map) do
      if (Pair.JsonValue is TJSONString) and TAtlasTasks.TrySeverity(Pair.JsonValue.Value, Severity) then
      begin
        Result.SeverityWords := Result.SeverityWords + [AnsiLowerCase(Pair.JsonString.Value)];
        Result.SeverityValues := Result.SeverityValues + [Severity];
      end
      else
        AIssues := AIssues + [Format('%s: severityMap "%s" ist weder error, warning noch info',
          [AName, Pair.JsonString.Value])];
end;

function ParseTask(AItem: TJSONObject; AIndex: Integer; AGlobal: Boolean; out ATask: TAtlasTaskDefinition;
  var AIssues: TArray<string>): Boolean;
var
  Value, Element: TJSONValue;
  Pair: TJSONPair;
  Text, Where: string;
  Number: Integer;
begin
  ATask := Default(TAtlasTaskDefinition);
  ATask.Group := TAtlasTaskGroup.Other;
  ATask.TimeoutSec := TAtlasTasks.DefaultTimeoutSec;
  ATask.Global := AGlobal;
  Where := Format('tasks[%d]', [AIndex]);
  if not StringOf(AItem, 'name', ATask.Name) or (Trim(ATask.Name) = '') then
  begin
    AIssues := AIssues + [Format('%s: ohne name', [Where])];
    Exit(False);
  end;
  ATask.Name := Trim(ATask.Name);
  Where := ATask.Name;
  if not StringOf(AItem, 'command', ATask.Command) or (Trim(ATask.Command) = '') then
  begin
    AIssues := AIssues + [Format('%s: ohne command', [Where])];
    Exit(False);
  end;
  ATask.Command := Trim(ATask.Command);
  Value := AItem.GetValue('args');
  if Value is TJSONArray then
  begin
    for Element in TJSONArray(Value) do
      if Element is TJSONString then
        ATask.Args := ATask.Args + [Element.Value]
      else if Element is TJSONNumber then
        ATask.Args := ATask.Args + [Element.ToString]
      else
        AIssues := AIssues + [Format('%s: args enthält einen Wert, der kein Text ist', [Where])];
  end
  else if Value <> nil then
    AIssues := AIssues + [Format('%s: args muss eine Liste sein', [Where])];
  StringOf(AItem, 'cwd', ATask.Cwd);
  Value := AItem.GetValue('env');
  if Value is TJSONObject then
    for Pair in TJSONObject(Value) do
      if Pair.JsonValue is TJSONString then
      begin
        ATask.EnvNames := ATask.EnvNames + [Pair.JsonString.Value];
        ATask.EnvValues := ATask.EnvValues + [Pair.JsonValue.Value];
      end;
  if StringOf(AItem, 'group', Text) and not TAtlasTasks.TryGroup(Text, ATask.Group) then
    AIssues := AIssues + [Format('%s: unbekannte group "%s", gilt als other', [Where, Text])];
  ATask.Matcher := ParseMatcher(AItem.GetValue('matcher'), Where, AIssues);
  if StringOf(AItem, 'key', ATask.KeyText) and (Trim(ATask.KeyText) <> '') then
  begin
    ATask.Key := TAtlasTasks.ParseKey(ATask.KeyText);
    if ATask.Key = 0 then
      AIssues := AIssues + [Format('%s: Taste "%s" nicht lesbar', [Where, ATask.KeyText])];
  end;
  Value := AItem.GetValue('timeoutSec');
  if (Value is TJSONNumber) and TryStrToInt(Value.ToString, Number) and (Number >= 0) then
  begin
    if Number > TAtlasTasks.MaxTimeoutSec then
      Number := TAtlasTasks.MaxTimeoutSec;
    ATask.TimeoutSec := Number;
  end
  else if Value <> nil then
    AIssues := AIssues + [Format('%s: timeoutSec muss eine ganze Zahl ab 0 sein', [Where])];
  if StringOf(AItem, 'beforeBuild', Text) then
  begin
    ATask.HasBeforeBuild := TAtlasTasks.TryBeforeBuild(Text, ATask.BeforeBuild);
    if not ATask.HasBeforeBuild then
      AIssues := AIssues + [Format('%s: beforeBuild "%s" ist weder off, warn noch block', [Where, Text])];
  end;
  Result := True;
end;

class function TAtlasTasks.Parse(ARoot: TJSONObject; AGlobal: Boolean;
  var AIssues: TArray<string>): TAtlasTaskDefinitions;
var
  Value: TJSONValue;
  Items: TJSONArray;
  Index: Integer;
  Task: TAtlasTaskDefinition;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  Value := ARoot.GetValue('tasks');
  if Value = nil then
    Exit;
  if not (Value is TJSONArray) then
  begin
    AIssues := AIssues + ['tasks muss eine Liste sein'];
    Exit;
  end;
  Items := TJSONArray(Value);
  for Index := 0 to Items.Count - 1 do
  begin
    if not (Items.Items[Index] is TJSONObject) then
    begin
      AIssues := AIssues + [Format('tasks[%d]: kein Objekt', [Index])];
      Continue;
    end;
    if not ParseTask(TJSONObject(Items.Items[Index]), Index, AGlobal, Task, AIssues) then
      Continue;
    if IndexOf(Result, Task.Name) >= 0 then
    begin
      AIssues := AIssues + [Format('%s: Name doppelt, die erste Aufgabe gilt', [Task.Name])];
      Continue;
    end;
    Result := Result + [Task];
  end;
end;

class function TAtlasTasks.Parse(const AText: string; AGlobal: Boolean;
  var AIssues: TArray<string>): TAtlasTaskDefinitions;
var
  Root: TJSONObject;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
    Exit;
  try
    Result := Parse(Root, AGlobal, AIssues);
  finally
    Root.Free;
  end;
end;

class function TAtlasTasks.Merge(const AProject, AGlobal: TAtlasTaskDefinitions): TAtlasTaskDefinitions;
var
  Task: TAtlasTaskDefinition;
begin
  Result := Copy(AProject);
  for Task in AGlobal do
    if IndexOf(AProject, Task.Name) < 0 then
      Result := Result + [Task];
end;

class function TAtlasTasks.IndexOf(const ATasks: TAtlasTaskDefinitions; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ATasks) do
    if SameText(ATasks[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasTasks.OfGroup(const ATasks: TAtlasTaskDefinitions;
  AGroup: TAtlasTaskGroup): TAtlasTaskDefinitions;
var
  Task: TAtlasTaskDefinition;
begin
  Result := nil;
  for Task in ATasks do
    if Task.Group = AGroup then
      Result := Result + [Task];
end;

class function TAtlasTasks.BeforeBuild(const ATasks: TAtlasTaskDefinitions;
  AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskDefinitions;
var
  Task: TAtlasTaskDefinition;
begin
  Result := nil;
  for Task in ATasks do
    if Task.BeforeBuildFor(AGlobal) <> TAtlasTaskBeforeBuild.Off then
      Result := Result + [Task];
end;

/// <summary>Absoluter Pfad: Laufwerk („C:“), UNC oder mit Trenner vorn.</summary>
function IsRooted(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or ((APath <> '') and CharInSet(APath[1], ['\', '/']));
end;

class function TAtlasTasks.Expand(const ATask: TAtlasTaskDefinition;
  const AVariables: TAtlasTaskVariables): TAtlasTaskDefinition;
var
  Index: Integer;
begin
  Result := ATask;
  Result.Command := AVariables.Expand(ATask.Command);
  Result.Args := Copy(ATask.Args);
  for Index := 0 to High(Result.Args) do
    Result.Args[Index] := AVariables.Expand(Result.Args[Index]);
  Result.Cwd := Trim(AVariables.Expand(ATask.Cwd));
  if Result.Cwd = '' then
    Result.Cwd := AVariables.ProjectDir
  else if not IsRooted(Result.Cwd) and (AVariables.ProjectDir <> '') then
  begin
    // Das Plugin läuft unter Windows: immer „\“.
    if CharInSet(AVariables.ProjectDir[Length(AVariables.ProjectDir)], ['\', '/']) then
      Result.Cwd := AVariables.ProjectDir + Result.Cwd
    else
      Result.Cwd := AVariables.ProjectDir + '\' + Result.Cwd;
  end;
  Result.EnvValues := Copy(ATask.EnvValues);
  for Index := 0 to High(Result.EnvValues) do
    Result.EnvValues[Index] := AVariables.Expand(Result.EnvValues[Index]);
end;

end.

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
//   Grund steht in Issues als Art mit Stelle und Wert; den Text in der Sprache
//   der Oberfläche setzt Atlas.UI.Build.Strings (#1458). Die genaue Prüfung
//   der Datei macht der Server.
// - Variablen in command, args, cwd und env: ${projectDir}, ${groupDir},
//   ${file}, ${fileDir}, ${config}, ${platform}, ${BDS}; unbekannte bleiben
//   stehen. Ohne cwd läuft die Aufgabe im Projektordner.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
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
  /// <summary>Grund, aus dem ein Eintrag ganz oder teilweise verworfen wurde (#1458: Text erst in der UI).</summary>
  TAtlasTaskIssueKind = (UnknownMatcher, SeverityMapValue, MatcherWithoutRegex, MatcherType, ArgsValue, ArgsType,
    KeyUnreadable, TimeoutValue, UnknownGroup, BeforeBuildValue, MissingName, MissingCommand, TasksType, TaskType,
    DuplicateName);
{$SCOPEDENUMS OFF}

  /// <summary>Ein verworfener Eintrag: Where ist der Name der Aufgabe bzw. „tasks[3]“ ('' bei TasksType), Value
  /// der beanstandete Wert ('' ohne).</summary>
  TAtlasTaskIssue = record
    Kind: TAtlasTaskIssueKind;
    Where: string;
    Value: string;
    class function Create(AKind: TAtlasTaskIssueKind; const AWhere: string): TAtlasTaskIssue; overload; static;
    class function Create(AKind: TAtlasTaskIssueKind; const AWhere, AValue: string): TAtlasTaskIssue; overload;
      static;
  end;

  TAtlasTaskIssues = TArray<TAtlasTaskIssue>;

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
    cDefaultTimeoutSec = 600;
    cMaxTimeoutSec = 86400;
    cGroupNames: array[TAtlasTaskGroup] of string = ('check', 'build', 'test', 'other');
    cBeforeBuildNames: array[TAtlasTaskBeforeBuild] of string = ('off', 'warn', 'block');
    cMatcherNames: array[TAtlasTaskMatcherKind] of string = ('', 'dcc', 'pwsh', 'msbuild', 'generic', '');
    cSeverityNames: array[TAtlasTaskSeverity] of string = ('error', 'warning', 'info');
  public
    /// <summary>Aufgaben aus dem Wurzelobjekt einer atlas.json bzw. settings.json; AIssues nennt verworfene
    /// Einträge.</summary>
    class function Parse(ARoot: TJSONObject; AGlobal: Boolean; var AIssues: TAtlasTaskIssues): TAtlasTaskDefinitions;
      overload; static;
    /// <summary>Wie Parse aus dem Text der Datei (Kommentare erlaubt); leer bei ungültigem Text.</summary>
    class function Parse(const AText: string; AGlobal: Boolean; var AIssues: TAtlasTaskIssues): TAtlasTaskDefinitions;
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

{ TAtlasTaskIssue }

class function TAtlasTaskIssue.Create(AKind: TAtlasTaskIssueKind; const AWhere: string): TAtlasTaskIssue;
begin
  Result := Create(AKind, AWhere, '');
end;

class function TAtlasTaskIssue.Create(AKind: TAtlasTaskIssueKind; const AWhere, AValue: string): TAtlasTaskIssue;
begin
  Result := Default(TAtlasTaskIssue);
  Result.Kind := AKind;
  Result.Where := AWhere;
  Result.Value := AValue;
end;

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
  begin
    Result := BeforeBuild;
  end
  else if Group = TAtlasTaskGroup.Check then
  begin
    Result := AGlobal;
  end
  else
  begin
    Result := TAtlasTaskBeforeBuild.Off;
  end;
end;

function TAtlasTaskDefinition.CommandLine: string;
var
  mArg: string;
begin
  Result := Command;
  for mArg in Args do
  begin
    if Pos(' ', mArg) > 0 then
    begin
      Result := Result + ' "' + mArg + '"';
    end
    else
    begin
      Result := Result + ' ' + mArg;
    end;
  end;
end;

{ TAtlasTaskVariables }

function TAtlasTaskVariables.Expand(const AText: string): string;
begin
  Result := AText;
  if Pos('${', Result) = 0 then
  begin
    Exit;
  end;
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
  mGroup: TAtlasTaskGroup;
begin
  for mGroup := Low(TAtlasTaskGroup) to High(TAtlasTaskGroup) do
  begin
    if SameText(Trim(AText), cGroupNames[mGroup]) then
    begin
      AGroup := mGroup;
      Exit(True);
    end;
  end;
  AGroup := TAtlasTaskGroup.Other;
  Result := False;
end;

class function TAtlasTasks.TryBeforeBuild(const AText: string; out AValue: TAtlasTaskBeforeBuild): Boolean;
var
  mValue: TAtlasTaskBeforeBuild;
begin
  for mValue := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
  begin
    if SameText(Trim(AText), cBeforeBuildNames[mValue]) then
    begin
      AValue := mValue;
      Exit(True);
    end;
  end;
  AValue := TAtlasTaskBeforeBuild.Off;
  Result := False;
end;

class function TAtlasTasks.NormalizedBeforeBuild(const AText: string): string;
var
  mValue: TAtlasTaskBeforeBuild;
begin
  TryBeforeBuild(AText, mValue);
  Result := cBeforeBuildNames[mValue];
end;

class function TAtlasTasks.TrySeverity(const AText: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  mSeverity: TAtlasTaskSeverity;
begin
  for mSeverity := Low(TAtlasTaskSeverity) to High(TAtlasTaskSeverity) do
  begin
    if SameText(Trim(AText), cSeverityNames[mSeverity]) then
    begin
      ASeverity := mSeverity;
      Exit(True);
    end;
  end;
  // Übliche andere Schreibweisen.
  Result := True;
  if SameText(Trim(AText), 'information') or SameText(Trim(AText), 'hint') then
  begin
    ASeverity := TAtlasTaskSeverity.Info;
  end
  else
  begin
    ASeverity := TAtlasTaskSeverity.Error;
    Result := False;
  end;
end;

const
  cShiftBit = $2000;
  cCtrlBit = $4000;
  cAltBit = $8000;

/// <summary>Umschalttasten aller Teile außer dem letzten; False bei einem unbekannten Teil.</summary>
function KeyModifiers(const AParts: TArray<string>; out AModifiers: Word): Boolean;
var
  mIndex: Integer;
  mPart: string;
begin
  AModifiers := 0;
  for mIndex := 0 to High(AParts) - 1 do
  begin
    mPart := Trim(AParts[mIndex]);
    if SameText(mPart, 'Ctrl') or SameText(mPart, 'Strg') or SameText(mPart, 'Control') then
    begin
      AModifiers := AModifiers or cCtrlBit;
    end
    else if SameText(mPart, 'Shift') or SameText(mPart, 'Umschalt') then
    begin
      AModifiers := AModifiers or cShiftBit;
    end
    else if SameText(mPart, 'Alt') then
    begin
      AModifiers := AModifiers or cAltBit;
    end
    else
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Taste A–Z, 0–9 oder F1–F24 (Name groß); 0 bei anderen.</summary>
function KeyCode(const AName: string): Word;
var
  mNumber: Integer;
begin
  Result := 0;
  if (Length(AName) = 1) and CharInSet(AName[1], ['A'..'Z', '0'..'9']) then
  begin
    Result := Ord(AName[1]);
  end
  else if (Length(AName) >= 2) and (AName[1] = 'F') and TryStrToInt(Copy(AName, 2, MaxInt), mNumber) and
    (mNumber >= 1) and (mNumber <= 24) then
  begin
    Result := $6F + mNumber;
  end;
end;

class function TAtlasTasks.ParseKey(const AText: string): Word;
var
  mParts: TArray<string>;
  mModifiers, mKey: Word;
begin
  Result := 0;
  mParts := Trim(AText).Split(['+']);
  if (Length(mParts) = 0) or not KeyModifiers(mParts, mModifiers) then
  begin
    Exit;
  end;
  mKey := KeyCode(UpperCase(Trim(mParts[High(mParts)])));
  // Eine Taste ohne Strg oder Alt würde das Tippen stören (nur Funktionstasten dürfen allein stehen).
  if (mKey = 0) or ((mModifiers and (cCtrlBit or cAltBit) = 0) and (mKey < $70)) then
  begin
    Exit;
  end;
  Result := mModifiers or mKey;
end;

function StringOf(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
var
  mValue: TJSONValue;
begin
  AValue := '';
  mValue := AObject.GetValue(AName);
  Result := mValue is TJSONString;
  if Result then
  begin
    AValue := TJSONString(mValue).Value;
  end;
end;

/// <summary>Eingebautes Muster nach Name; unbekannte (außer leer und none) melden.</summary>
function NamedMatcher(const AText, AName: string; var AIssues: TAtlasTaskIssues): TAtlasTaskMatcher;
var
  mKind: TAtlasTaskMatcherKind;
begin
  for mKind := TAtlasTaskMatcherKind.Dcc to TAtlasTaskMatcherKind.Generic do
  begin
    if SameText(Trim(AText), TAtlasTasks.cMatcherNames[mKind]) then
    begin
      Exit(TAtlasTaskMatcher.Create(mKind));
    end;
  end;
  if (Trim(AText) <> '') and not SameText(Trim(AText), 'none') then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.UnknownMatcher, AName, AText)];
  end;
  Result := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.None);
end;

/// <summary>severityMap: eigene Wörter und ihre Schwere; ungültige Einträge melden.</summary>
procedure ReadSeverityMap(AMap: TJSONObject; const AName: string; var AMatcher: TAtlasTaskMatcher;
  var AIssues: TAtlasTaskIssues);
var
  mPair: TJSONPair;
  mSeverity: TAtlasTaskSeverity;
begin
  for mPair in AMap do
  begin
    if (mPair.JsonValue is TJSONString) and TAtlasTasks.TrySeverity(mPair.JsonValue.Value, mSeverity) then
    begin
      AMatcher.SeverityWords := AMatcher.SeverityWords + [AnsiLowerCase(mPair.JsonString.Value)];
      AMatcher.SeverityValues := AMatcher.SeverityValues + [mSeverity];
    end
    else
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.SeverityMapValue, AName,
        mPair.JsonString.Value)];
    end;
  end;
end;

/// <summary>Eigenes Muster aus { regex, severity, severityMap }; ohne regex keins.</summary>
function CustomMatcher(AItem: TJSONObject; const AName: string; var AIssues: TAtlasTaskIssues): TAtlasTaskMatcher;
var
  mMap: TJSONValue;
  mText: string;
  mSeverity: TAtlasTaskSeverity;
begin
  if not StringOf(AItem, 'regex', mText) or (mText = '') then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.MatcherWithoutRegex, AName)];
    Exit(TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.None));
  end;
  Result := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  Result.Regex := mText;
  if StringOf(AItem, 'severity', mText) and TAtlasTasks.TrySeverity(mText, mSeverity) then
  begin
    Result.DefaultSeverity := mSeverity;
  end;
  mMap := AItem.GetValue('severityMap');
  if mMap is TJSONObject then
  begin
    ReadSeverityMap(TJSONObject(mMap), AName, Result, AIssues);
  end;
end;

function ParseMatcher(AValue: TJSONValue; const AName: string; var AIssues: TAtlasTaskIssues): TAtlasTaskMatcher;
begin
  if AValue is TJSONString then
  begin
    Result := NamedMatcher(AValue.Value, AName, AIssues);
  end
  else if AValue is TJSONObject then
  begin
    Result := CustomMatcher(TJSONObject(AValue), AName, AIssues);
  end
  else
  begin
    if AValue <> nil then
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.MatcherType, AName)];
    end;
    Result := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.None);
  end;
end;

procedure ReadArgs(AItem: TJSONObject; const AWhere: string; var ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues);
var
  mValue, mElement: TJSONValue;
begin
  mValue := AItem.GetValue('args');
  if mValue is TJSONArray then
  begin
    for mElement in TJSONArray(mValue) do
    begin
      if mElement is TJSONString then
      begin
        ATask.Args := ATask.Args + [mElement.Value];
      end
      else if mElement is TJSONNumber then
      begin
        ATask.Args := ATask.Args + [mElement.ToString];
      end
      else
      begin
        AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.ArgsValue, AWhere)];
      end;
    end;
  end
  else if mValue <> nil then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.ArgsType, AWhere)];
  end;
end;

procedure ReadEnv(AItem: TJSONObject; var ATask: TAtlasTaskDefinition);
var
  mValue: TJSONValue;
  mPair: TJSONPair;
begin
  mValue := AItem.GetValue('env');
  if not (mValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(mValue) do
  begin
    if mPair.JsonValue is TJSONString then
    begin
      ATask.EnvNames := ATask.EnvNames + [mPair.JsonString.Value];
      ATask.EnvValues := ATask.EnvValues + [mPair.JsonValue.Value];
    end;
  end;
end;

procedure ReadKey(AItem: TJSONObject; const AWhere: string; var ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues);
begin
  if StringOf(AItem, 'key', ATask.KeyText) and (Trim(ATask.KeyText) <> '') then
  begin
    ATask.Key := TAtlasTasks.ParseKey(ATask.KeyText);
    if ATask.Key = 0 then
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.KeyUnreadable, AWhere, ATask.KeyText)];
    end;
  end;
end;

procedure ReadTimeout(AItem: TJSONObject; const AWhere: string; var ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues);
var
  mValue: TJSONValue;
  mNumber: Integer;
begin
  mValue := AItem.GetValue('timeoutSec');
  if (mValue is TJSONNumber) and TryStrToInt(mValue.ToString, mNumber) and (mNumber >= 0) then
  begin
    if mNumber > TAtlasTasks.cMaxTimeoutSec then
    begin
      mNumber := TAtlasTasks.cMaxTimeoutSec;
    end;
    ATask.TimeoutSec := mNumber;
  end
  else if mValue <> nil then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.TimeoutValue, AWhere)];
  end;
end;

procedure ReadGroup(AItem: TJSONObject; const AWhere: string; var ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues);
var
  mText: string;
begin
  if StringOf(AItem, 'group', mText) and not TAtlasTasks.TryGroup(mText, ATask.Group) then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.UnknownGroup, AWhere, mText)];
  end;
end;

procedure ReadBeforeBuild(AItem: TJSONObject; const AWhere: string; var ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues);
var
  mText: string;
begin
  if StringOf(AItem, 'beforeBuild', mText) then
  begin
    ATask.HasBeforeBuild := TAtlasTasks.TryBeforeBuild(mText, ATask.BeforeBuild);
    if not ATask.HasBeforeBuild then
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.BeforeBuildValue, AWhere, mText)];
    end;
  end;
end;

function ParseTask(AItem: TJSONObject; AIndex: Integer; AGlobal: Boolean; out ATask: TAtlasTaskDefinition;
  var AIssues: TAtlasTaskIssues): Boolean;
var
  mWhere: string;
begin
  ATask := Default(TAtlasTaskDefinition);
  ATask.Group := TAtlasTaskGroup.Other;
  ATask.TimeoutSec := TAtlasTasks.cDefaultTimeoutSec;
  ATask.Global := AGlobal;
  if not StringOf(AItem, 'name', ATask.Name) or (Trim(ATask.Name) = '') then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.MissingName, Format('tasks[%d]', [AIndex]))];
    Exit(False);
  end;
  ATask.Name := Trim(ATask.Name);
  mWhere := ATask.Name;
  if not StringOf(AItem, 'command', ATask.Command) or (Trim(ATask.Command) = '') then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.MissingCommand, mWhere)];
    Exit(False);
  end;
  ATask.Command := Trim(ATask.Command);
  ReadArgs(AItem, mWhere, ATask, AIssues);
  StringOf(AItem, 'cwd', ATask.Cwd);
  ReadEnv(AItem, ATask);
  ReadGroup(AItem, mWhere, ATask, AIssues);
  ATask.Matcher := ParseMatcher(AItem.GetValue('matcher'), mWhere, AIssues);
  ReadKey(AItem, mWhere, ATask, AIssues);
  ReadTimeout(AItem, mWhere, ATask, AIssues);
  ReadBeforeBuild(AItem, mWhere, ATask, AIssues);
  Result := True;
end;

class function TAtlasTasks.Parse(ARoot: TJSONObject; AGlobal: Boolean;
  var AIssues: TAtlasTaskIssues): TAtlasTaskDefinitions;
var
  mValue: TJSONValue;
  mItems: TJSONArray;
  mIndex: Integer;
  mTask: TAtlasTaskDefinition;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  mValue := ARoot.GetValue('tasks');
  if mValue = nil then
  begin
    Exit;
  end;
  if not (mValue is TJSONArray) then
  begin
    AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.TasksType, '')];
    Exit;
  end;
  mItems := TJSONArray(mValue);
  for mIndex := 0 to mItems.Count - 1 do
  begin
    if not (mItems.Items[mIndex] is TJSONObject) then
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.TaskType, Format('tasks[%d]', [mIndex]))];
      Continue;
    end;
    if not ParseTask(TJSONObject(mItems.Items[mIndex]), mIndex, AGlobal, mTask, AIssues) then
    begin
      Continue;
    end;
    if IndexOf(Result, mTask.Name) >= 0 then
    begin
      AIssues := AIssues + [TAtlasTaskIssue.Create(TAtlasTaskIssueKind.DuplicateName, mTask.Name)];
      Continue;
    end;
    Result := Result + [mTask];
  end;
end;

class function TAtlasTasks.Parse(const AText: string; AGlobal: Boolean;
  var AIssues: TAtlasTaskIssues): TAtlasTaskDefinitions;
var
  mRoot: TJSONObject;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    Result := Parse(mRoot, AGlobal, AIssues);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTasks.Merge(const AProject, AGlobal: TAtlasTaskDefinitions): TAtlasTaskDefinitions;
var
  mTask: TAtlasTaskDefinition;
begin
  Result := Copy(AProject);
  for mTask in AGlobal do
  begin
    if IndexOf(AProject, mTask.Name) < 0 then
    begin
      Result := Result + [mTask];
    end;
  end;
end;

class function TAtlasTasks.IndexOf(const ATasks: TAtlasTaskDefinitions; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATasks) do
  begin
    if SameText(ATasks[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTasks.OfGroup(const ATasks: TAtlasTaskDefinitions;
  AGroup: TAtlasTaskGroup): TAtlasTaskDefinitions;
var
  mTask: TAtlasTaskDefinition;
begin
  Result := nil;
  for mTask in ATasks do
  begin
    if mTask.Group = AGroup then
    begin
      Result := Result + [mTask];
    end;
  end;
end;

class function TAtlasTasks.BeforeBuild(const ATasks: TAtlasTaskDefinitions;
  AGlobal: TAtlasTaskBeforeBuild): TAtlasTaskDefinitions;
var
  mTask: TAtlasTaskDefinition;
begin
  Result := nil;
  for mTask in ATasks do
  begin
    if mTask.BeforeBuildFor(AGlobal) <> TAtlasTaskBeforeBuild.Off then
    begin
      Result := Result + [mTask];
    end;
  end;
end;

/// <summary>Absoluter Pfad: Laufwerk („C:“), UNC oder mit Trenner vorn.</summary>
function IsRooted(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or ((APath <> '') and CharInSet(APath[1], ['\', '/']));
end;

class function TAtlasTasks.Expand(const ATask: TAtlasTaskDefinition;
  const AVariables: TAtlasTaskVariables): TAtlasTaskDefinition;
var
  mIndex: Integer;
begin
  Result := ATask;
  Result.Command := AVariables.Expand(ATask.Command);
  Result.Args := Copy(ATask.Args);
  for mIndex := 0 to High(Result.Args) do
  begin
    Result.Args[mIndex] := AVariables.Expand(Result.Args[mIndex]);
  end;
  Result.Cwd := Trim(AVariables.Expand(ATask.Cwd));
  if Result.Cwd = '' then
  begin
    Result.Cwd := AVariables.ProjectDir;
  end
  else if not IsRooted(Result.Cwd) and (AVariables.ProjectDir <> '') then
  begin
    // Das Plugin läuft unter Windows: immer „\“.
    if CharInSet(AVariables.ProjectDir[Length(AVariables.ProjectDir)], ['\', '/']) then
    begin
      Result.Cwd := AVariables.ProjectDir + Result.Cwd;
    end
    else
    begin
      Result.Cwd := AVariables.ProjectDir + '\' + Result.Cwd;
    end;
  end;
  Result.EnvValues := Copy(ATask.EnvValues);
  for mIndex := 0 to High(Result.EnvValues) do
  begin
    Result.EnvValues[mIndex] := AVariables.Expand(Result.EnvValues[mIndex]);
  end;
end;

end.

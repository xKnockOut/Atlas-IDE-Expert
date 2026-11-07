unit Atlas.Core.Tasks.Matchers;

// Fundstellen in der Ausgabe von Projektaufgaben (#900), ohne VCL und Open
// Tools API. Je Zeile der Ausgabe prüft TAtlasTaskLineMatcher das Muster der
// Aufgabe:
// - dcc: „[dcc64 Error] Datei.pas(12): E2003 …“ (auch deutsch „[dcc32
//   Fehler]“, „Warnung“, „Hinweis“, „Schwerer Fehler“) und die Form der
//   Kommandozeile „Datei.pas(12) Error: E2003 …“.
// - pwsh: „Datei.pas:12: Text“, „Datei.pas:12:5: Text“, „Datei.pas(12):
//   Text“ und „Datei.pas: Text“ (ohne Zeile, wie Check-TestCoverage), auch
//   eingerückt wie in den Tools/Check-*.ps1; FEHLER, WARNUNG, HINWEIS (und
//   ERROR, WARNING, HINT, INFO) als großgeschriebenes Wort davor oder am
//   Anfang des Texts bestimmen die Schwere, sonst error.
// - msbuild: „Datei.pas(12,5): error E2003: Text [Projekt.dproj]“ und
//   „Datei : error MSB1009: Text“ (ohne Zeile).
// - generic: „Datei(Zeile[,Spalte]): Text“ und „Datei:Zeile[:Spalte]: Text“;
//   ein Wort error, warning, info, hint (auch deutsch) am Anfang des Texts
//   bestimmt die Schwere, sonst error.
// - eigen: regulärer Ausdruck mit benannten Gruppen file, line, column,
//   severity, code, message. Die Gruppen zählt Atlas selbst zu Nummern um
//   (Delphi wirft bei Namen einer nicht beteiligten Gruppe am Ende). Die
//   Gruppe severity geht erst durch severityMap (eigene Wörter, Groß-/
//   Kleinschreibung egal), dann durch error/warning/info; sonst gilt
//   severity des Musters. Ohne Gruppe message ist die ganze Zeile die Meldung.
// TAtlasTaskPaths.Resolve macht aus relativen Pfaden Dateien: erst gegen den
// Arbeitsordner, dann gegen die Projektdateien (Endung des Pfads) und den
// Suchpfad (#14); sonst bleibt der Pfad gegen den Arbeitsordner.

interface

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Core.Tasks.Definitions;

type
  TAtlasTaskFinding = record
    /// <summary>Datei wie in der Ausgabe; nach Resolve der gefundene Pfad. '' = ohne Datei (zählt nur).</summary>
    FileName: string;
    /// <summary>Zeile und Spalte ab 1; 0 = unbekannt (Befund an der Datei).</summary>
    Line: Integer;
    Column: Integer;
    Severity: TAtlasTaskSeverity;
    Code: string;
    Message: string;
    /// <summary>Index der Zeile in der Ausgabe des Laufs.</summary>
    OutputLine: Integer;
  end;

  TAtlasTaskFindings = TArray<TAtlasTaskFinding>;

  /// <summary>Prüft Zeilen der Ausgabe gegen ein Muster; einmal je Lauf anlegen (übersetzte Ausdrücke).</summary>
  TAtlasTaskLineMatcher = class
  private type
    TForm = (DccIde, DccCommandLine, PwshLine, MsBuildLine, MsBuildFile, GenericParen, GenericColon, Custom);
    TRule = record
      Form: TForm;
      Regex: TRegEx;
    end;
  private
    FMatcher: TAtlasTaskMatcher;
    FRules: TArray<TRule>;
    FError: string;
    // Nummern der benannten Gruppen des eigenen Musters; 0 = nicht vorhanden.
    FFileGroup, FLineGroup, FColumnGroup, FSeverityGroup, FCodeGroup, FMessageGroup: Integer;
    procedure AddRule(AForm: TForm; const APattern: string; AOptions: TRegExOptions);
    function Apply(const ARule: TRule; const ALine: string; out AFinding: TAtlasTaskFinding): Boolean;
    function CustomSeverity(const AText: string): TAtlasTaskSeverity;
    procedure ReadCustom(const AFound: TMatch; const ALine: string; var AFinding: TAtlasTaskFinding);
  public
    constructor Create(const AMatcher: TAtlasTaskMatcher);
    /// <summary>Fundstelle in ALine; False ohne Treffer oder ohne Muster.</summary>
    function Match(const ALine: string; out AFinding: TAtlasTaskFinding): Boolean;
    /// <summary>Fehler im eigenen Ausdruck (dann erkennt das Muster nichts); '' ohne.</summary>
    property Error: string read FError;
    /// <summary>Nummer der benannten Gruppe (?&lt;AName&gt;…) bzw. (?P&lt;AName&gt;…) in APattern; 0 ohne. Zählt
    /// wie PCRE: jede öffnende Klammer, die nicht \( ist, nicht in [...] steht und nicht mit (? beginnt (außer
    /// benannten Gruppen).</summary>
    class function GroupNumber(const APattern, AName: string): Integer; static;
    /// <summary>Schwere aus einem Wort der Ausgabe: error/fehler/fatal → Error, warning/warnung → Warning,
    /// hint/hinweis/info/information → Info; False bei anderen Wörtern.</summary>
    class function SeverityWord(const AWord: string; out ASeverity: TAtlasTaskSeverity): Boolean; static;
  end;

  TAtlasTaskFileExists = reference to function(const AFileName: string): Boolean;

  TAtlasTaskPaths = class
  public
    /// <summary>Pfad mit \ statt /, ohne .\ und mit aufgelöstem ..\.</summary>
    class function Normalize(const APath: string): string; static;
    /// <summary>Datei zu APath (aus der Ausgabe): absolut unverändert (normalisiert); relativ erst gegen ACwd,
    /// dann die Projektdatei, deren Pfad auf APath endet, dann ASearchPath; sonst gegen ACwd.</summary>
    class function Resolve(const APath, ACwd: string; const AProjectFiles, ASearchPath: TArray<string>;
      const AExists: TAtlasTaskFileExists): string; static;
  end;

implementation

const
  /// <summary>Datei mit Endung: optional Laufwerk, keine Zeichen, die in Pfaden verboten sind.</summary>
  cFilePattern = '((?:[A-Za-z]:)?[^:*?"<>|()\s][^:*?"<>|()]*?\.[A-Za-z0-9]{1,10})';

{ TAtlasTaskLineMatcher }

class function TAtlasTaskLineMatcher.SeverityWord(const AWord: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  mWord: string;
begin
  mWord := AnsiLowerCase(Trim(AWord));
  Result := True;
  // Wörter des deutschen Compilers, keine Oberfläche.
  if (mWord = 'error') or (mWord = 'fehler') or (mWord = 'fatal') or (mWord = 'schwerer fehler') then // german-ok
  begin
    ASeverity := TAtlasTaskSeverity.Error;
  end
  else if (mWord = 'warning') or (mWord = 'warnung') then
  begin
    ASeverity := TAtlasTaskSeverity.Warning;
  end
  else if (mWord = 'hint') or (mWord = 'hinweis') or (mWord = 'info') or (mWord = 'information') or
    (mWord = 'message') then
  begin
    ASeverity := TAtlasTaskSeverity.Info;
  end
  else
  begin
    ASeverity := TAtlasTaskSeverity.Error;
    Result := False;
  end;
end;

/// <summary>Name der Gruppe, die bei AIndex mit (? beginnt: (?&lt;name&gt;…), (?P&lt;name&gt;…), (?'name'…); '' bei
/// anderen Formen.</summary>
function GroupName(const APattern: string; AIndex: Integer): string;
var
  mClose: Integer;
begin
  Result := '';
  if (AIndex + 2 > Length(APattern)) or not CharInSet(APattern[AIndex + 2], ['<', 'P', '''']) then
  begin
    Exit;
  end;
  mClose := AIndex + 3;
  if APattern[AIndex + 2] = 'P' then
  begin
    Inc(mClose);
  end;
  while (mClose <= Length(APattern)) and not CharInSet(APattern[mClose], ['>', '''']) do
  begin
    Inc(mClose);
  end;
  if (APattern[AIndex + 2] = 'P') and (AIndex + 3 <= Length(APattern)) and (APattern[AIndex + 3] = '<') then
  begin
    Result := Copy(APattern, AIndex + 4, mClose - AIndex - 4);
  end
  else if APattern[AIndex + 2] <> 'P' then
  begin
    Result := Copy(APattern, AIndex + 3, mClose - AIndex - 3);
  end;
end;

/// <summary>Die Klammer bei AIndex öffnet eine zählende Gruppe; AName ist ihr Name ('' ohne). Nicht (?&lt;=…),
/// (?&lt;!…) und andere (?…-Formen.</summary>
function OpensGroup(const APattern: string; AIndex: Integer; out AName: string): Boolean;
begin
  AName := '';
  Result := True;
  if (AIndex < Length(APattern)) and (APattern[AIndex + 1] = '?') then
  begin
    AName := GroupName(APattern, AIndex);
    Result := (AName <> '') and not CharInSet(AName[1], ['=', '!']);
  end;
end;

class function TAtlasTaskLineMatcher.GroupNumber(const APattern, AName: string): Integer;
var
  mIndex, mCount: Integer;
  mInClass: Boolean;
  mName: string;
begin
  Result := 0;
  mCount := 0;
  mInClass := False;
  mIndex := 1;
  while mIndex <= Length(APattern) do
  begin
    case APattern[mIndex] of
      '\':
        Inc(mIndex);
      '[':
        mInClass := True;
      ']':
        mInClass := False;
      '(':
        if not mInClass and OpensGroup(APattern, mIndex, mName) then
        begin
          Inc(mCount);
          if (mName <> '') and SameText(mName, AName) then
          begin
            Exit(mCount);
          end;
        end;
    end;
    Inc(mIndex);
  end;
end;

constructor TAtlasTaskLineMatcher.Create(const AMatcher: TAtlasTaskMatcher);
begin
  inherited Create;
  FMatcher := AMatcher;
  case AMatcher.Kind of
    TAtlasTaskMatcherKind.Dcc:
      begin
        AddRule(TForm.DccIde, '^\s*\[\s*dcc\w*\s+(error|fehler|warning|warnung|hint|hinweis|fatal|' +
          'schwerer fehler)\s*\]\s*(.+?)\((\d+)(?:,(\d+))?\)\s*:?\s*(?:([EWHF]\d{3,4})\s+)?(.*)$', [roIgnoreCase]); // german-ok
        AddRule(TForm.DccCommandLine, '^\s*(.+?)\((\d+)(?:,(\d+))?\)\s+(error|fehler|warning|warnung|hint|' +
          'hinweis|fatal|schwerer fehler)\s*:\s*(?:([EWHF]\d{3,4})\s+)?(.*)$', [roIgnoreCase]); // german-ok
      end;
    TAtlasTaskMatcherKind.Pwsh:
      AddRule(TForm.PwshLine, '^\s*(?:Write-Error:\s*)?(?:(FEHLER|WARNUNG|HINWEIS|ERROR|WARNING|HINT|INFO)\s*:?\s+)?' +
        cFilePattern + '(?::(\d+)(?::(\d+))?|\((\d+)(?:,(\d+))?\))?\s*:\s*(.*)$', []);
    TAtlasTaskMatcherKind.MsBuild:
      begin
        AddRule(TForm.MsBuildLine, '^\s*(.+?)\((\d+)(?:,(\d+))?(?:,\d+,\d+)?\)\s*:\s*(?:\w+\s+)?' +
          '(error|warning|info|hint|message)\s*([A-Za-z]*\d+)?\s*:\s*(.*?)(?:\s+\[[^\[\]]+\])?\s*$', [roIgnoreCase]);
        AddRule(TForm.MsBuildFile, '^\s*(.+?)\s*:\s*(?:\w+\s+)?(error|warning)\s+([A-Za-z]+\d+)\s*:\s*(.*?)' +
          '(?:\s+\[[^\[\]]+\])?\s*$', [roIgnoreCase]);
      end;
    TAtlasTaskMatcherKind.Generic:
      begin
        AddRule(TForm.GenericParen, '^\s*(.+?)\((\d+)(?:,(\d+))?\)\s*:?\s*(.+)$', []);
        AddRule(TForm.GenericColon, '^\s*' + cFilePattern + ':(\d+)(?::(\d+))?:\s*(.+)$', []);
      end;
    TAtlasTaskMatcherKind.Custom:
      begin
        try
          AddRule(TForm.Custom, AMatcher.Regex, []);
          // Übersetzen erzwingen: Ein Fehler soll hier auffallen, nicht bei der ersten Zeile.
          FRules[0].Regex.IsMatch('');
        except
          on E: Exception do
          begin
            FRules := nil;
            FError := E.Message;
          end;
        end;
        FFileGroup := GroupNumber(AMatcher.Regex, 'file');
        FLineGroup := GroupNumber(AMatcher.Regex, 'line');
        FColumnGroup := GroupNumber(AMatcher.Regex, 'column');
        FSeverityGroup := GroupNumber(AMatcher.Regex, 'severity');
        FCodeGroup := GroupNumber(AMatcher.Regex, 'code');
        FMessageGroup := GroupNumber(AMatcher.Regex, 'message');
      end;
    TAtlasTaskMatcherKind.None: ;
  end;
end;

procedure TAtlasTaskLineMatcher.AddRule(AForm: TForm; const APattern: string; AOptions: TRegExOptions);
var
  mRule: TRule;
begin
  mRule.Form := AForm;
  mRule.Regex := TRegEx.Create(APattern, AOptions);
  FRules := FRules + [mRule];
end;

function TAtlasTaskLineMatcher.CustomSeverity(const AText: string): TAtlasTaskSeverity;
var
  mIndex: Integer;
  mWord: string;
begin
  mWord := AnsiLowerCase(Trim(AText));
  for mIndex := 0 to High(FMatcher.SeverityWords) do
  begin
    if FMatcher.SeverityWords[mIndex] = mWord then
    begin
      Exit(FMatcher.SeverityValues[mIndex]);
    end;
  end;
  if (mWord = '') or not SeverityWord(mWord, Result) then
  begin
    Result := FMatcher.DefaultSeverity;
  end;
end;

/// <summary>Wert der Gruppe ANumber; '' ohne Gruppe oder wenn sie nicht beteiligt war.</summary>
function GroupText(const AMatch: TMatch; ANumber: Integer): string;
begin
  Result := '';
  if (ANumber <= 0) or (ANumber >= AMatch.Groups.Count) then
  begin
    Exit;
  end;
  if AMatch.Groups[ANumber].Success then
  begin
    Result := AMatch.Groups[ANumber].Value;
  end;
end;

/// <summary>Wort am Anfang von AMessage, das die Schwere nennt („error: …“, „Warnung …“); entfernt es.</summary>
function LeadingSeverity(var AMessage: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(AMessage, '^(error|fehler|fatal|warning|warnung|hint|hinweis|info)\b\s*:?\s*',
    [roIgnoreCase]);
  Result := mMatch.Success and TAtlasTaskLineMatcher.SeverityWord(mMatch.Groups[1].Value, ASeverity);
  if Result then
  begin
    AMessage := Copy(AMessage, mMatch.Length + 1, MaxInt);
  end;
end;

/// <summary>Großgeschriebenes Wort FEHLER, WARNUNG, HINWEIS (ERROR, WARNING, HINT, INFO) am Anfang.</summary>
function UpperSeverity(var AMessage: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  mMatch: TMatch;
begin
  mMatch := TRegEx.Match(AMessage, '^(FEHLER|WARNUNG|HINWEIS|ERROR|WARNING|HINT|INFO)\b\s*:?\s*', []);
  Result := mMatch.Success and TAtlasTaskLineMatcher.SeverityWord(mMatch.Groups[1].Value, ASeverity);
  if Result then
  begin
    AMessage := Copy(AMessage, mMatch.Length + 1, MaxInt);
  end;
end;

// Datei(Zeile,Spalte) Schwere Code Meldung: dcc auf der Kommandozeile und MSBuild.
procedure ReadFileFirst(const AFound: TMatch; var AFinding: TAtlasTaskFinding);
begin
  AFinding.FileName := Trim(GroupText(AFound, 1));
  AFinding.Line := StrToIntDef(GroupText(AFound, 2), 0);
  AFinding.Column := StrToIntDef(GroupText(AFound, 3), 0);
  TAtlasTaskLineMatcher.SeverityWord(GroupText(AFound, 4), AFinding.Severity);
  AFinding.Code := GroupText(AFound, 5);
  AFinding.Message := Trim(GroupText(AFound, 6));
end;

// [dcc Schwere] Datei(Zeile,Spalte) Code Meldung: Meldungen der IDE.
procedure ReadDccIde(const AFound: TMatch; var AFinding: TAtlasTaskFinding);
begin
  TAtlasTaskLineMatcher.SeverityWord(GroupText(AFound, 1), AFinding.Severity);
  AFinding.FileName := Trim(GroupText(AFound, 2));
  AFinding.Line := StrToIntDef(GroupText(AFound, 3), 0);
  AFinding.Column := StrToIntDef(GroupText(AFound, 4), 0);
  AFinding.Code := GroupText(AFound, 5);
  AFinding.Message := Trim(GroupText(AFound, 6));
end;

/// <summary>Wert der ersten beteiligten Gruppe von AFirst und ASecond.</summary>
function EitherGroup(const AFound: TMatch; AFirst, ASecond: Integer): string;
begin
  Result := GroupText(AFound, AFirst);
  if Result = '' then
  begin
    Result := GroupText(AFound, ASecond);
  end;
end;

procedure ReadPwsh(const AFound: TMatch; const ALine: string; var AFinding: TAtlasTaskFinding);
var
  mSeverity: TAtlasTaskSeverity;
begin
  AFinding.FileName := Trim(GroupText(AFound, 2));
  AFinding.Line := StrToIntDef(EitherGroup(AFound, 3, 5), 0);
  AFinding.Column := StrToIntDef(EitherGroup(AFound, 4, 6), 0);
  AFinding.Message := Trim(GroupText(AFound, 7));
  if GroupText(AFound, 1) <> '' then
  begin
    TAtlasTaskLineMatcher.SeverityWord(GroupText(AFound, 1), AFinding.Severity);
  end
  else if UpperSeverity(AFinding.Message, mSeverity) then
  begin
    AFinding.Severity := mSeverity;
  end
  else if TRegEx.IsMatch(ALine, '^\s*Write-Error:', []) then
  begin
    AFinding.Severity := TAtlasTaskSeverity.Error;
  end;
end;

procedure ReadMsBuildFile(const AFound: TMatch; var AFinding: TAtlasTaskFinding);
begin
  AFinding.FileName := Trim(GroupText(AFound, 1));
  TAtlasTaskLineMatcher.SeverityWord(GroupText(AFound, 2), AFinding.Severity);
  AFinding.Code := GroupText(AFound, 3);
  AFinding.Message := Trim(GroupText(AFound, 4));
  // „MSBUILD : error …“ und andere Werkzeugnamen sind keine Dateien.
  if Pos('.', ExtractFileName(AFinding.FileName)) = 0 then
  begin
    AFinding.FileName := '';
  end;
end;

procedure ReadGeneric(const AFound: TMatch; var AFinding: TAtlasTaskFinding);
var
  mSeverity: TAtlasTaskSeverity;
  mCode: TMatch;
begin
  AFinding.FileName := Trim(GroupText(AFound, 1));
  AFinding.Line := StrToIntDef(GroupText(AFound, 2), 0);
  AFinding.Column := StrToIntDef(GroupText(AFound, 3), 0);
  AFinding.Message := Trim(GroupText(AFound, 4));
  if LeadingSeverity(AFinding.Message, mSeverity) then
  begin
    AFinding.Severity := mSeverity;
  end;
  // „error E2003: …“: Code hinter dem Wort.
  mCode := TRegEx.Match(AFinding.Message, '^([A-Za-z]{1,4}\d{2,5})\s*:\s*', []);
  if mCode.Success then
  begin
    AFinding.Code := mCode.Groups[1].Value;
    AFinding.Message := Copy(AFinding.Message, mCode.Length + 1, MaxInt);
  end;
end;

procedure TAtlasTaskLineMatcher.ReadCustom(const AFound: TMatch; const ALine: string;
  var AFinding: TAtlasTaskFinding);
begin
  AFinding.FileName := Trim(GroupText(AFound, FFileGroup));
  AFinding.Line := StrToIntDef(GroupText(AFound, FLineGroup), 0);
  AFinding.Column := StrToIntDef(GroupText(AFound, FColumnGroup), 0);
  AFinding.Severity := CustomSeverity(GroupText(AFound, FSeverityGroup));
  AFinding.Code := Trim(GroupText(AFound, FCodeGroup));
  if FMessageGroup > 0 then
  begin
    AFinding.Message := Trim(GroupText(AFound, FMessageGroup));
  end
  else
  begin
    AFinding.Message := Trim(ALine);
  end;
end;

function TAtlasTaskLineMatcher.Apply(const ARule: TRule; const ALine: string; out AFinding: TAtlasTaskFinding): Boolean;
var
  mFound: TMatch;
begin
  AFinding := Default(TAtlasTaskFinding);
  AFinding.Severity := TAtlasTaskSeverity.Error;
  mFound := ARule.Regex.Match(ALine);
  Result := mFound.Success;
  if not Result then
  begin
    Exit;
  end;
  case ARule.Form of
    TForm.DccIde:
      ReadDccIde(mFound, AFinding);
    TForm.DccCommandLine, TForm.MsBuildLine:
      ReadFileFirst(mFound, AFinding);
    TForm.PwshLine:
      ReadPwsh(mFound, ALine, AFinding);
    TForm.MsBuildFile:
      ReadMsBuildFile(mFound, AFinding);
    TForm.GenericParen, TForm.GenericColon:
      ReadGeneric(mFound, AFinding);
    TForm.Custom:
      ReadCustom(mFound, ALine, AFinding);
  end;
  if AFinding.Line < 0 then
  begin
    AFinding.Line := 0;
  end;
  if AFinding.Column < 0 then
  begin
    AFinding.Column := 0;
  end;
end;

function TAtlasTaskLineMatcher.Match(const ALine: string; out AFinding: TAtlasTaskFinding): Boolean;
var
  mRule: TRule;
begin
  AFinding := Default(TAtlasTaskFinding);
  for mRule in FRules do
  begin
    if Apply(mRule, ALine, AFinding) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTaskPaths }

class function TAtlasTaskPaths.Normalize(const APath: string): string;
var
  mParts, mKept: TArray<string>;
  mPart, mPrefix: string;
begin
  Result := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
  if Result = '' then
  begin
    Exit;
  end;
  mPrefix := '';
  if Copy(Result, 1, 2) = '\\' then
  begin
    mPrefix := '\\';
    Result := Copy(Result, 3, MaxInt);
  end
  else if (Result <> '') and (Result[1] = '\') then
  begin
    mPrefix := '\';
    Result := Copy(Result, 2, MaxInt);
  end;
  mParts := Result.Split(['\']);
  mKept := nil;
  for mPart in mParts do
  begin
    if (mPart = '') or (mPart = '.') then
    begin
      Continue;
    end;
    if (mPart = '..') and (Length(mKept) > 0) and (mKept[High(mKept)] <> '..') then
    begin
      // Nicht über das Laufwerk hinaus.
      if not ((Length(mKept) = 1) and (Length(mKept[0]) = 2) and (mKept[0][2] = ':')) then
      begin
        SetLength(mKept, Length(mKept) - 1);
      end;
      Continue;
    end;
    mKept := mKept + [mPart];
  end;
  Result := mPrefix + string.Join('\', mKept);
end;

function IsAbsolute(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or (Copy(APath, 1, 2) = '\\');
end;

function Combine(const AFolder, APath: string): string;
begin
  if AFolder = '' then
  begin
    Result := APath;
  end
  else
  begin
    Result := StringReplace(AFolder, '/', '\', [rfReplaceAll]);
    if Result[Length(Result)] <> '\' then
    begin
      Result := Result + '\';
    end;
    Result := Result + APath;
  end;
end;

/// <summary>Projektdatei, deren Pfad ACandidate ist oder auf \ARelative endet.</summary>
function ProjectMatch(const AProjectFiles: TArray<string>; const ACandidate, ARelative: string;
  out AFile: string): Boolean;
var
  mProjectFile, mNormal: string;
begin
  AFile := '';
  for mProjectFile in AProjectFiles do
  begin
    mNormal := TAtlasTaskPaths.Normalize(mProjectFile);
    if SameText(mNormal, ACandidate) or
      SameText(Copy(mNormal, Length(mNormal) - Length(ARelative), MaxInt), '\' + ARelative) then
    begin
      AFile := mNormal;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erste vorhandene Datei ARelative in einem Ordner von ASearchPath.</summary>
function SearchPathMatch(const ASearchPath: TArray<string>; const ARelative: string;
  const AExists: TAtlasTaskFileExists; out AFile: string): Boolean;
var
  mFolder: string;
begin
  AFile := '';
  for mFolder in ASearchPath do
  begin
    if Trim(mFolder) <> '' then
    begin
      AFile := TAtlasTaskPaths.Normalize(Combine(Trim(mFolder), ARelative));
      if AExists(AFile) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TAtlasTaskPaths.Resolve(const APath, ACwd: string; const AProjectFiles, ASearchPath: TArray<string>;
  const AExists: TAtlasTaskFileExists): string;
var
  mRelative, mCandidate: string;
begin
  mRelative := Normalize(APath);
  if (mRelative = '') or IsAbsolute(mRelative) then
  begin
    Exit(mRelative);
  end;
  mCandidate := Normalize(Combine(ACwd, mRelative));
  if Assigned(AExists) and AExists(mCandidate) then
  begin
    Exit(mCandidate);
  end;
  // Projektdateien: gleicher Name mit passendem Ende des Pfads.
  if not ProjectMatch(AProjectFiles, mCandidate, mRelative, Result) and
    not (Assigned(AExists) and SearchPathMatch(ASearchPath, mRelative, AExists, Result)) then
  begin
    Result := mCandidate;
  end;
end;

end.

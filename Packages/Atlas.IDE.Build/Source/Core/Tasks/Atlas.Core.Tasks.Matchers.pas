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
  FilePattern = '((?:[A-Za-z]:)?[^:*?"<>|()\s][^:*?"<>|()]*?\.[A-Za-z0-9]{1,10})';

{ TAtlasTaskLineMatcher }

class function TAtlasTaskLineMatcher.SeverityWord(const AWord: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  Word: string;
begin
  Word := AnsiLowerCase(Trim(AWord));
  Result := True;
  if (Word = 'error') or (Word = 'fehler') or (Word = 'fatal') or (Word = 'schwerer fehler') then
  begin
    ASeverity := TAtlasTaskSeverity.Error;
  end
  else if (Word = 'warning') or (Word = 'warnung') then
  begin
    ASeverity := TAtlasTaskSeverity.Warning;
  end
  else if (Word = 'hint') or (Word = 'hinweis') or (Word = 'info') or (Word = 'information') or
    (Word = 'message') then
  begin
    ASeverity := TAtlasTaskSeverity.Info;
  end
  else
  begin
    ASeverity := TAtlasTaskSeverity.Error;
    Result := False;
  end;
end;

class function TAtlasTaskLineMatcher.GroupNumber(const APattern, AName: string): Integer;
var
  Index, Count, Close: Integer;
  InClass: Boolean;
  Name: string;
begin
  Result := 0;
  Count := 0;
  InClass := False;
  Index := 1;
  while Index <= Length(APattern) do
  begin
    case APattern[Index] of
      '\':
        Inc(Index);
      '[':
        InClass := True;
      ']':
        InClass := False;
      '(':
        if not InClass then
        begin
          if (Index < Length(APattern)) and (APattern[Index + 1] = '?') then
          begin
            Name := '';
            // (?<name>…), (?P<name>…), (?'name'…); nicht (?<=…) und (?<!…).
            if (Index + 2 <= Length(APattern)) and CharInSet(APattern[Index + 2], ['<', 'P', '''']) then
            begin
              Close := Index + 3;
              if APattern[Index + 2] = 'P' then
              begin
                Inc(Close);
              end;
              while (Close <= Length(APattern)) and not CharInSet(APattern[Close], ['>', '''']) do
              begin
                Inc(Close);
              end;
              if (APattern[Index + 2] = 'P') and (Index + 3 <= Length(APattern)) and (APattern[Index + 3] = '<') then
              begin
                Name := Copy(APattern, Index + 4, Close - Index - 4);
              end
              else if APattern[Index + 2] <> 'P' then
              begin
                Name := Copy(APattern, Index + 3, Close - Index - 3);
              end;
              if (Name <> '') and not CharInSet(Name[1], ['=', '!']) then
              begin
                Inc(Count);
                if SameText(Name, AName) then
                begin
                  Exit(Count);
                end;
              end;
            end;
          end
          else
          begin
            Inc(Count);
          end;
        end;
    end;
    Inc(Index);
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
          'schwerer fehler)\s*\]\s*(.+?)\((\d+)(?:,(\d+))?\)\s*:?\s*(?:([EWHF]\d{3,4})\s+)?(.*)$', [roIgnoreCase]);
        AddRule(TForm.DccCommandLine, '^\s*(.+?)\((\d+)(?:,(\d+))?\)\s+(error|fehler|warning|warnung|hint|' +
          'hinweis|fatal|schwerer fehler)\s*:\s*(?:([EWHF]\d{3,4})\s+)?(.*)$', [roIgnoreCase]);
      end;
    TAtlasTaskMatcherKind.Pwsh:
      AddRule(TForm.PwshLine, '^\s*(?:Write-Error:\s*)?(?:(FEHLER|WARNUNG|HINWEIS|ERROR|WARNING|HINT|INFO)\s*:?\s+)?' +
        FilePattern + '(?::(\d+)(?::(\d+))?|\((\d+)(?:,(\d+))?\))?\s*:\s*(.*)$', []);
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
        AddRule(TForm.GenericColon, '^\s*' + FilePattern + ':(\d+)(?::(\d+))?:\s*(.+)$', []);
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
  Rule: TRule;
begin
  Rule.Form := AForm;
  Rule.Regex := TRegEx.Create(APattern, AOptions);
  FRules := FRules + [Rule];
end;

function TAtlasTaskLineMatcher.CustomSeverity(const AText: string): TAtlasTaskSeverity;
var
  Index: Integer;
  Word: string;
begin
  Word := AnsiLowerCase(Trim(AText));
  for Index := 0 to High(FMatcher.SeverityWords) do
  begin
    if FMatcher.SeverityWords[Index] = Word then
    begin
      Exit(FMatcher.SeverityValues[Index]);
    end;
  end;
  if (Word = '') or not SeverityWord(Word, Result) then
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
  Match: TMatch;
begin
  Match := TRegEx.Match(AMessage, '^(error|fehler|fatal|warning|warnung|hint|hinweis|info)\b\s*:?\s*',
    [roIgnoreCase]);
  Result := Match.Success and TAtlasTaskLineMatcher.SeverityWord(Match.Groups[1].Value, ASeverity);
  if Result then
  begin
    AMessage := Copy(AMessage, Match.Length + 1, MaxInt);
  end;
end;

/// <summary>Großgeschriebenes Wort FEHLER, WARNUNG, HINWEIS (ERROR, WARNING, HINT, INFO) am Anfang.</summary>
function UpperSeverity(var AMessage: string; out ASeverity: TAtlasTaskSeverity): Boolean;
var
  Match: TMatch;
begin
  Match := TRegEx.Match(AMessage, '^(FEHLER|WARNUNG|HINWEIS|ERROR|WARNING|HINT|INFO)\b\s*:?\s*', []);
  Result := Match.Success and TAtlasTaskLineMatcher.SeverityWord(Match.Groups[1].Value, ASeverity);
  if Result then
  begin
    AMessage := Copy(AMessage, Match.Length + 1, MaxInt);
  end;
end;

function TAtlasTaskLineMatcher.Apply(const ARule: TRule; const ALine: string; out AFinding: TAtlasTaskFinding): Boolean;
var
  Found: TMatch;
  Severity: TAtlasTaskSeverity;
  Text: string;
begin
  AFinding := Default(TAtlasTaskFinding);
  AFinding.Severity := TAtlasTaskSeverity.Error;
  Found := ARule.Regex.Match(ALine);
  Result := Found.Success;
  if not Result then
  begin
    Exit;
  end;
  case ARule.Form of
    TForm.DccIde:
      begin
        SeverityWord(GroupText(Found, 1), AFinding.Severity);
        AFinding.FileName := Trim(GroupText(Found, 2));
        AFinding.Line := StrToIntDef(GroupText(Found, 3), 0);
        AFinding.Column := StrToIntDef(GroupText(Found, 4), 0);
        AFinding.Code := GroupText(Found, 5);
        AFinding.Message := Trim(GroupText(Found, 6));
      end;
    TForm.DccCommandLine:
      begin
        AFinding.FileName := Trim(GroupText(Found, 1));
        AFinding.Line := StrToIntDef(GroupText(Found, 2), 0);
        AFinding.Column := StrToIntDef(GroupText(Found, 3), 0);
        SeverityWord(GroupText(Found, 4), AFinding.Severity);
        AFinding.Code := GroupText(Found, 5);
        AFinding.Message := Trim(GroupText(Found, 6));
      end;
    TForm.PwshLine:
      begin
        AFinding.FileName := Trim(GroupText(Found, 2));
        Text := GroupText(Found, 3);
        if Text = '' then
        begin
          Text := GroupText(Found, 5);
        end;
        AFinding.Line := StrToIntDef(Text, 0);
        Text := GroupText(Found, 4);
        if Text = '' then
        begin
          Text := GroupText(Found, 6);
        end;
        AFinding.Column := StrToIntDef(Text, 0);
        AFinding.Message := Trim(GroupText(Found, 7));
        if GroupText(Found, 1) <> '' then
        begin
          SeverityWord(GroupText(Found, 1), AFinding.Severity);
        end
        else if UpperSeverity(AFinding.Message, Severity) then
        begin
          AFinding.Severity := Severity;
        end
        else if TRegEx.IsMatch(ALine, '^\s*Write-Error:', []) then
        begin
          AFinding.Severity := TAtlasTaskSeverity.Error;
        end;
      end;
    TForm.MsBuildLine:
      begin
        AFinding.FileName := Trim(GroupText(Found, 1));
        AFinding.Line := StrToIntDef(GroupText(Found, 2), 0);
        AFinding.Column := StrToIntDef(GroupText(Found, 3), 0);
        SeverityWord(GroupText(Found, 4), AFinding.Severity);
        AFinding.Code := GroupText(Found, 5);
        AFinding.Message := Trim(GroupText(Found, 6));
      end;
    TForm.MsBuildFile:
      begin
        AFinding.FileName := Trim(GroupText(Found, 1));
        SeverityWord(GroupText(Found, 2), AFinding.Severity);
        AFinding.Code := GroupText(Found, 3);
        AFinding.Message := Trim(GroupText(Found, 4));
        // „MSBUILD : error …“ und andere Werkzeugnamen sind keine Dateien.
        if Pos('.', ExtractFileName(AFinding.FileName)) = 0 then
        begin
          AFinding.FileName := '';
        end;
      end;
    TForm.GenericParen, TForm.GenericColon:
      begin
        AFinding.FileName := Trim(GroupText(Found, 1));
        AFinding.Line := StrToIntDef(GroupText(Found, 2), 0);
        AFinding.Column := StrToIntDef(GroupText(Found, 3), 0);
        AFinding.Message := Trim(GroupText(Found, 4));
        if LeadingSeverity(AFinding.Message, Severity) then
        begin
          AFinding.Severity := Severity;
        end;
        // „error E2003: …“: Code hinter dem Wort.
        Found := TRegEx.Match(AFinding.Message, '^([A-Za-z]{1,4}\d{2,5})\s*:\s*', []);
        if Found.Success then
        begin
          AFinding.Code := Found.Groups[1].Value;
          AFinding.Message := Copy(AFinding.Message, Found.Length + 1, MaxInt);
        end;
      end;
    TForm.Custom:
      begin
        AFinding.FileName := Trim(GroupText(Found, FFileGroup));
        AFinding.Line := StrToIntDef(GroupText(Found, FLineGroup), 0);
        AFinding.Column := StrToIntDef(GroupText(Found, FColumnGroup), 0);
        AFinding.Severity := CustomSeverity(GroupText(Found, FSeverityGroup));
        AFinding.Code := Trim(GroupText(Found, FCodeGroup));
        if FMessageGroup > 0 then
        begin
          AFinding.Message := Trim(GroupText(Found, FMessageGroup));
        end
        else
        begin
          AFinding.Message := Trim(ALine);
        end;
      end;
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
  Rule: TRule;
begin
  AFinding := Default(TAtlasTaskFinding);
  for Rule in FRules do
  begin
    if Apply(Rule, ALine, AFinding) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasTaskPaths }

class function TAtlasTaskPaths.Normalize(const APath: string): string;
var
  Parts, Kept: TArray<string>;
  Part, Prefix: string;
begin
  Result := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
  if Result = '' then
  begin
    Exit;
  end;
  Prefix := '';
  if Copy(Result, 1, 2) = '\\' then
  begin
    Prefix := '\\';
    Result := Copy(Result, 3, MaxInt);
  end
  else if (Result <> '') and (Result[1] = '\') then
  begin
    Prefix := '\';
    Result := Copy(Result, 2, MaxInt);
  end;
  Parts := Result.Split(['\']);
  Kept := nil;
  for Part in Parts do
  begin
    if (Part = '') or (Part = '.') then
    begin
      Continue;
    end;
    if (Part = '..') and (Length(Kept) > 0) and (Kept[High(Kept)] <> '..') then
    begin
      // Nicht über das Laufwerk hinaus.
      if not ((Length(Kept) = 1) and (Length(Kept[0]) = 2) and (Kept[0][2] = ':')) then
      begin
        SetLength(Kept, Length(Kept) - 1);
      end;
      Continue;
    end;
    Kept := Kept + [Part];
  end;
  Result := Prefix + string.Join('\', Kept);
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

class function TAtlasTaskPaths.Resolve(const APath, ACwd: string; const AProjectFiles, ASearchPath: TArray<string>;
  const AExists: TAtlasTaskFileExists): string;
var
  Relative, Candidate, ProjectFile, Folder: string;
begin
  Relative := Normalize(APath);
  if (Relative = '') or IsAbsolute(Relative) then
  begin
    Exit(Relative);
  end;
  Candidate := Normalize(Combine(ACwd, Relative));
  if Assigned(AExists) and AExists(Candidate) then
  begin
    Exit(Candidate);
  end;
  // Projektdateien: gleicher Name mit passendem Ende des Pfads.
  for ProjectFile in AProjectFiles do
  begin
    if SameText(Normalize(ProjectFile), Candidate) or
      SameText(Copy(Normalize(ProjectFile), Length(Normalize(ProjectFile)) - Length(Relative), MaxInt),
      '\' + Relative) then
    begin
      Exit(Normalize(ProjectFile));
    end;
  end;
  if Assigned(AExists) then
  begin
    for Folder in ASearchPath do
    begin
      if Trim(Folder) <> '' then
      begin
        Result := Normalize(Combine(Trim(Folder), Relative));
        if AExists(Result) then
        begin
          Exit;
        end;
      end;
    end;
  end;
  Result := Candidate;
end;

end.

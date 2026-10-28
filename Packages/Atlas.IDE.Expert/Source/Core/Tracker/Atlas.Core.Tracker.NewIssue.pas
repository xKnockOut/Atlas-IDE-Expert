unit Atlas.Core.Tracker.NewIssue;

// „Issue anlegen …“ (#1268), ohne VCL und Open Tools API: Vorschlag für Titel
// und Beschreibung aus dem Editor (Auswahl, TODO unter dem Cursor, Fundstelle
// mit Unit, Zeile, Methode, Branch und Commit, Codeausschnitt) bzw. aus
// Befunden der Atlas-Prüfung, das Eintragen der Kennung in das TODO und die
// Anfragen an den Tracker.
// - TODO-Kommentare in einer Zeile: // TODO …, { TODO … } und (* TODO … *)
//   (auch FIXME, auch mit den Optionen der IDE: { TODO -oMarco -cGUI : … }).
//   WithKey macht daraus // TODO ATL-130: … bzw. { TODO -oMarco : ATL-130: … }.
//   Kommentare in Strings und Direktiven ({$ …}) zählen nicht.
// - YouTrack: Projekt-ID über GET /api/admin/projects?fields=id,shortName
//   (das Kürzel aus der Zuordnung, #1261), Felder Typ, Priorität und
//   Zuständig über /api/admin/projects/<id>/customFields, Anlegen mit
//   POST /api/issues (project.id, summary, description, customFields).
// - GitHub: POST /repos/<owner>/<repo>/issues (title, body, labels,
//   assignees); Typ und Priorität sind Labels (GET /labels), Zuständige aus
//   GET /assignees.
// - Eigener Benutzer für „mir zuweisen“ über IAtlasTrackerProvider.ProbeUrl.
// Geschrieben wird nur über IAtlasCiSend (nur mit Token, nur https, ohne
// Weiterleitungen). Die Texte der Beschreibung (Fundstelle, Zeile, …) kommen
// über TAtlasNewIssueLabels von der Oberfläche; hier steht nur der Aufbau.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Schreibweise eines TODO-Kommentars.</summary>
  TAtlasTodoStyle = (None, Slashes, Braces, Parens);
  /// <summary>Ergebnis von „Anlegen“.</summary>
  TAtlasNewIssueOutcome = (Created, NoToken, NotConfigured, Rejected, ProjectUnknown, Invalid, Unreadable,
    ServerError, Unreachable);
{$SCOPEDENUMS OFF}

  /// <summary>TODO-Kommentar in einer Zeile; Positionen ab 1 in der Zeile.</summary>
  TAtlasTodoComment = record
    Style: TAtlasTodoStyle;
    /// <summary>"TODO" bzw. "FIXME" wie geschrieben.</summary>
    Keyword: string;
    /// <summary>Text nach Marke, Optionen und Doppelpunkt, ohne Leerraum am Rand; ohne eine schon eingetragene
    /// Kennung.</summary>
    Text: string;
    /// <summary>Schon eingetragene Kennung ("ATL-130", "#12"); '' ohne.</summary>
    Key: string;
    /// <summary>Erstes Zeichen nach der Marke.</summary>
    KeywordEnd: Integer;
    /// <summary>Erstes Zeichen des Texts (bzw. der Kennung); bei leerem Text das Ende des Inhalts.</summary>
    TextStart: Integer;
    /// <summary>Die Marke hat Optionen der IDE (-o, -c, Priorität) vor einem Doppelpunkt.</summary>
    HasOptions: Boolean;
  end;

  /// <summary>Stelle im Editor, aus der der Vorschlag entsteht.</summary>
  TAtlasNewIssueContext = record
    /// <summary>Datei; in die Beschreibung kommt nur der Name ohne Pfad.</summary>
    FileName: string;
    /// <summary>Zeile des Cursors ab 1.</summary>
    Line: Integer;
    /// <summary>"TKlasse.Methode" um den Cursor; '' außerhalb.</summary>
    Method: string;
    Branch: string;
    /// <summary>Vollständiger Hash bzw. SVN-Revision; in die Beschreibung kommen 7 Zeichen.</summary>
    Commit: string;
    /// <summary>Ausgewählter Text; '' ohne Auswahl.</summary>
    Selection: string;
    /// <summary>Erste Zeile der Auswahl ab 1 (für die Fundstelle); 0 = Line.</summary>
    SelectionLine: Integer;
    /// <summary>Alle Zeilen der Datei (für ±5 Zeilen um den Cursor ohne Auswahl).</summary>
    Lines: TArray<string>;
    class function Empty: TAtlasNewIssueContext; static;
  end;

  /// <summary>Ein Befund der Atlas-Prüfung, wie er in die Beschreibung geht.</summary>
  TAtlasNewIssueFinding = record
    /// <summary>Regelkennung bzw. Meldungsnummer des Compilers.</summary>
    Rule: string;
    Message: string;
    /// <summary>"Unit1.pas:12:5".</summary>
    Location: string;
    /// <summary>Betroffene Zeile; '' wenn unbekannt.</summary>
    LineText: string;
    class function Create(const ARule, AMessage, ALocation, ALineText: string): TAtlasNewIssueFinding; static;
  end;

  /// <summary>Beschriftungen der Beschreibung in der Sprache der Oberfläche.</summary>
  TAtlasNewIssueLabels = record
    /// <summary>"Fundstelle".</summary>
    Location: string;
    /// <summary>"Zeile".</summary>
    Line: string;
    Method: string;
    Branch: string;
    Commit: string;
    /// <summary>"Befunde".</summary>
    Findings: string;
    /// <summary>Titel für mehrere Befunde mit %d (Anzahl) und %s (Unit): "%d Befunde in %s".</summary>
    FindingsTitle: string;
    /// <summary>Deutsche Beschriftungen (Tests und Rückfall).</summary>
    class function German: TAtlasNewIssueLabels; static;
  end;

  /// <summary>Auswahllisten des Trackers für Typ, Priorität und Zuständig.</summary>
  TAtlasNewIssueFields = record
    /// <summary>YouTrack: Namen der Felder im Projekt ("Type", "Typ", …); '' = gibt es nicht. GitHub: ''.</summary>
    TypeField: string;
    PriorityField: string;
    AssigneeField: string;
    Types: TArray<string>;
    Priorities: TArray<string>;
    /// <summary>Anmeldenamen.</summary>
    Assignees: TArray<string>;
    /// <summary>Eigener Anmeldename; '' unbekannt.</summary>
    Me: string;
    class function Empty: TAtlasNewIssueFields; static;
  end;

  /// <summary>Was gesendet wird, wie im Dialog bearbeitet.</summary>
  TAtlasNewIssueDraft = record
    Title: string;
    Description: string;
    /// <summary>'' = nicht setzen.</summary>
    IssueType: string;
    Priority: string;
    Assignee: string;
    /// <summary>„mir zuweisen“: Zuständig ist der angemeldete Benutzer (ersetzt Assignee).</summary>
    AssignToMe: Boolean;
    /// <summary>Feldnamen aus TAtlasNewIssueFields (YouTrack); '' = übliche Namen.</summary>
    TypeField: string;
    PriorityField: string;
    AssigneeField: string;
    class function Empty: TAtlasNewIssueDraft; static;
  end;

  TAtlasNewIssueResult = record
    Outcome: TAtlasNewIssueOutcome;
    /// <summary>"ATL-130" bzw. "#130".</summary>
    Key: string;
    Number: Integer;
    /// <summary>Seite des Issues für den Browser; '' ohne.</summary>
    Page: string;
    HttpStatus: Integer;
    /// <summary>Meldung des Trackers bei 400/422 (gekürzt); '' ohne.</summary>
    TrackerMessage: string;
    class function Create(AOutcome: TAtlasNewIssueOutcome): TAtlasNewIssueResult; static;
  end;

  TAtlasNewIssues = class
  public const
    /// <summary>Zeilen über und unter dem Cursor im Codeausschnitt ohne Auswahl.</summary>
    ContextLines = 5;
    /// <summary>Höchstens so lang wird der vorgeschlagene Titel.</summary>
    MaxTitle = 120;
    /// <summary>Höchstens so viele Zeilen hat der Codeausschnitt einer Auswahl.</summary>
    MaxCodeLines = 60;
    /// <summary>Zeitgrenze für Anlegen bzw. Listen laden insgesamt.</summary>
    TimeoutMs = 10000;
    /// <summary>Höchstens so viele Einträge je Auswahlliste.</summary>
    MaxValues = 100;
  public
    /// <summary>TODO- bzw. FIXME-Kommentar in ALine; False ohne.</summary>
    class function TodoAt(const ALine: string; out ATodo: TAtlasTodoComment): Boolean; static;
    /// <summary>ALine mit AKey im TODO: "// TODO ATL-130: Text"; unverändert ohne TODO oder mit schon
    /// eingetragener Kennung.</summary>
    class function WithKey(const ALine, AKey: string): string; static;
    /// <summary>Kommentar "// ATL-130" für eine Zeile ohne TODO.</summary>
    class function KeyComment(const AKey: string): string; static;
    /// <summary>ALine mit KeyComment am Ende (nach einem Leerzeichen); eine leere Zeile wird zum Kommentar.</summary>
    class function WithKeyComment(const ALine, AKey: string): string; static;
    /// <summary>Titel: erste nicht leere Zeile der Auswahl, sonst Text des TODO unter dem Cursor, sonst ''.</summary>
    class function TitleOf(const AContext: TAtlasNewIssueContext): string; static;
    /// <summary>Auswahl (höchstens MaxCodeLines Zeilen) bzw. ±ContextLines Zeilen um den Cursor; Einrückung, die
    /// alle Zeilen teilen, fällt weg.</summary>
    class function CodeOf(const AContext: TAtlasNewIssueContext): string; static;
    /// <summary>Fundstelle, Methode, Branch und Commit (Markdown); den Codeausschnitt setzt Compose dazu.</summary>
    class function DescriptionOf(const AContext: TAtlasNewIssueContext; const ALabels: TAtlasNewIssueLabels): string;
      static;
    /// <summary>ADescription, mit AIncludeCode und nicht leerem ACode gefolgt vom Code-Block "pascal". So bleibt
    /// der Codeausschnitt im Dialog ein eigenes Häkchen.</summary>
    class function Compose(const ADescription, ACode: string; AIncludeCode: Boolean): string; static;
    /// <summary>Code-Block "pascal"; enthält ACode selbst ```, dann mit ~~~.</summary>
    class function CodeBlock(const ACode: string): string; static;
    /// <summary>Ein Befund: "Regel: Meldung"; mehrere: ALabels.FindingsTitle mit Anzahl und Unit des ersten.
    /// </summary>
    class function TitleOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>;
      const ALabels: TAtlasNewIssueLabels): string; static;
    /// <summary>Branch und Commit aus AContext, dann die Liste der Befunde mit Regel, Meldung und Fundstelle.
    /// </summary>
    class function DescriptionOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>;
      const AContext: TAtlasNewIssueContext; const ALabels: TAtlasNewIssueLabels): string; static;
    /// <summary>Codeausschnitt zu Befunden: je Befund "// Unit1.pas:12:5" und die Zeile; '' ohne Zeilen.</summary>
    class function CodeOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>): string; static;
    /// <summary>Kürzt auf MaxTitle Zeichen mit „…“, Zeilenumbrüche zu Leerzeichen.</summary>
    class function ShortTitle(const AText: string): string; static;
    { YouTrack }
    class function YouTrackProjectsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>ID zum Kürzel AShortName (ohne Groß-/Kleinschreibung); False ohne Treffer oder bei ungültigem JSON.
    /// </summary>
    class function ParseYouTrackProject(const AText, AShortName: string; out AId: string): Boolean; static;
    class function YouTrackFieldsUrl(const ATarget: TAtlasTrackerTarget; const AProjectId: string): string; static;
    /// <summary>Typ, Priorität und Zuständig aus /customFields; False bei ungültigem JSON.</summary>
    class function ParseYouTrackFields(const AText: string; var AFields: TAtlasNewIssueFields): Boolean; static;
    class function YouTrackCreateUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function YouTrackBody(const AProjectId: string; const ADraft: TAtlasNewIssueDraft;
      const AMe: string): string; static;
    /// <summary>"idReadable" und "numberInProject" der Antwort; False ohne Kennung.</summary>
    class function ParseYouTrackCreated(const AText: string; out AKey: string; out ANumber: Integer): Boolean;
      static;
    { GitHub }
    class function GitHubCreateUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function GitHubLabelsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function GitHubAssigneesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function GitHubBody(const ADraft: TAtlasNewIssueDraft; const AMe: string): string; static;
    /// <summary>"number" der Antwort; False ohne.</summary>
    class function ParseGitHubCreated(const AText: string; out ANumber: Integer): Boolean; static;
    /// <summary>Werte AName ("name", "login") aus einer JSON-Liste von Objekten; False bei ungültigem JSON.
    /// </summary>
    class function ParseNames(const AText, AName: string; out ANames: TArray<string>): Boolean; static;
    /// <summary>"login" aus der Antwort von ProbeUrl; '' ohne.</summary>
    class function ParseLogin(const AText: string): string; static;
    { Ablauf (im Hintergrund) }
    /// <summary>Auswahllisten und eigener Benutzer; False, wenn nichts gelesen werden konnte (dann bleiben die
    /// Felder frei eintippbar).</summary>
    class function LoadFields(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport; out AFields: TAtlasNewIssueFields): Boolean; static;
    /// <summary>Legt das Issue an; ohne Transport (kein Token) oder ohne IAtlasCiSend kein Netz.</summary>
    class function CreateIssue(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget;
      const ATransport: IAtlasCiTransport; const ADraft: TAtlasNewIssueDraft): TAtlasNewIssueResult; static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Uris,
  Atlas.Text.Lines,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.QueryTest;

const
  // Übliche Namen der Felder in YouTrack, auch auf Deutsch angelegte Projekte.
  YouTrackTypeNames: array[0..1] of string = ('Type', 'Typ');
  YouTrackPriorityNames: array[0..1] of string = ('Priority', 'Priorität');
  YouTrackAssigneeNames: array[0..2] of string = ('Assignee', 'Zuständig', 'Bearbeiter');

{ TAtlasNewIssueContext }

class function TAtlasNewIssueContext.Empty: TAtlasNewIssueContext;
begin
  Result := Default(TAtlasNewIssueContext);
  Result.Lines := nil;
end;

{ TAtlasNewIssueFinding }

class function TAtlasNewIssueFinding.Create(const ARule, AMessage, ALocation,
  ALineText: string): TAtlasNewIssueFinding;
begin
  Result.Rule := ARule;
  Result.Message := AMessage;
  Result.Location := ALocation;
  Result.LineText := ALineText;
end;

{ TAtlasNewIssueLabels }

class function TAtlasNewIssueLabels.German: TAtlasNewIssueLabels;
begin
  Result.Location := 'Fundstelle';
  Result.Line := 'Zeile';
  Result.Method := 'Methode';
  Result.Branch := 'Branch';
  Result.Commit := 'Commit';
  Result.Findings := 'Befunde';
  Result.FindingsTitle := '%d Befunde in %s';
end;

{ TAtlasNewIssueFields }

class function TAtlasNewIssueFields.Empty: TAtlasNewIssueFields;
begin
  Result := Default(TAtlasNewIssueFields);
  Result.Types := nil;
  Result.Priorities := nil;
  Result.Assignees := nil;
end;

{ TAtlasNewIssueDraft }

class function TAtlasNewIssueDraft.Empty: TAtlasNewIssueDraft;
begin
  Result := Default(TAtlasNewIssueDraft);
end;

{ TAtlasNewIssueResult }

class function TAtlasNewIssueResult.Create(AOutcome: TAtlasNewIssueOutcome): TAtlasNewIssueResult;
begin
  Result := Default(TAtlasNewIssueResult);
  Result.Outcome := AOutcome;
end;

{ Hilfen }

function IsSpace(ACh: Char): Boolean;
begin
  Result := (ACh = ' ') or (ACh = #9);
end;

function IsKeyChar(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

/// <summary>Länge einer Kennung "ATL-130" bzw. "#130" ab AStart in AText; 0 ohne.</summary>
function KeyLength(const AText: string; AStart: Integer): Integer;
var
  mIndex, mDigits: Integer;
begin
  Result := 0;
  mIndex := AStart;
  if (mIndex <= Length(AText)) and (AText[mIndex] = '#') then
    Inc(mIndex)
  else
  begin
    if (mIndex > Length(AText)) or not CharInSet(AText[mIndex], ['A'..'Z']) then
      Exit;
    while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', '0'..'9', '_']) do
      Inc(mIndex);
    if (mIndex > Length(AText)) or (AText[mIndex] <> '-') then
      Exit;
    Inc(mIndex);
  end;
  mDigits := 0;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['0'..'9']) do
  begin
    Inc(mIndex);
    Inc(mDigits);
  end;
  if mDigits = 0 then
    Exit;
  // Danach Ende, Leerraum oder Doppelpunkt: "ATL-130x" ist keine Kennung.
  if (mIndex <= Length(AText)) and IsKeyChar(AText[mIndex]) then
    Exit;
  Result := mIndex - AStart;
end;

/// <summary>Inhalt eines Kommentars von AFrom bis vor ATo (ab 1) auf TODO prüfen.</summary>
function ParseBody(const ALine: string; AFrom, ATo: Integer; AStyle: TAtlasTodoStyle;
  out ATodo: TAtlasTodoComment): Boolean;
var
  mIndex, mWordEnd, mColon, mKeyLength: Integer;
  mWord: string;
begin
  Result := False;
  mIndex := AFrom;
  while (mIndex < ATo) and IsSpace(ALine[mIndex]) do
    Inc(mIndex);
  mWordEnd := mIndex;
  while (mWordEnd < ATo) and CharInSet(ALine[mWordEnd], ['A'..'Z', 'a'..'z']) do
    Inc(mWordEnd);
  mWord := Copy(ALine, mIndex, mWordEnd - mIndex);
  if not SameText(mWord, 'TODO') and not SameText(mWord, 'FIXME') then
    Exit;
  // „TODOs“ oder „TODO-Liste“ sind keine Einträge.
  if (mWordEnd < ATo) and not IsSpace(ALine[mWordEnd]) and (ALine[mWordEnd] <> ':') then
    Exit;
  ATodo := Default(TAtlasTodoComment);
  ATodo.Style := AStyle;
  ATodo.Keyword := mWord;
  ATodo.KeywordEnd := mWordEnd;
  mIndex := mWordEnd;
  while (mIndex < ATo) and IsSpace(ALine[mIndex]) do
    Inc(mIndex);
  // Optionen der IDE ({ TODO 1 -oMarco -cGUI : Text }): Text nach dem Doppelpunkt.
  if (mIndex < ATo) and (CharInSet(ALine[mIndex], ['0'..'9']) or ((ALine[mIndex] = '-') and (mIndex + 1 < ATo) and
    CharInSet(ALine[mIndex + 1], ['o', 'O', 'c', 'C']))) then
  begin
    mColon := mIndex;
    while (mColon < ATo) and (ALine[mColon] <> ':') do
      Inc(mColon);
    if mColon < ATo then
    begin
      ATodo.HasOptions := True;
      mIndex := mColon + 1;
      while (mIndex < ATo) and IsSpace(ALine[mIndex]) do
        Inc(mIndex);
    end;
  end
  else if (mIndex < ATo) and (ALine[mIndex] = ':') then
  begin
    Inc(mIndex);
    while (mIndex < ATo) and IsSpace(ALine[mIndex]) do
      Inc(mIndex);
  end;
  ATodo.TextStart := mIndex;
  ATodo.Text := Trim(Copy(ALine, mIndex, ATo - mIndex));
  mKeyLength := KeyLength(ALine, mIndex);
  if (mKeyLength > 0) and (mIndex + mKeyLength <= ATo) then
  begin
    ATodo.Key := Copy(ALine, mIndex, mKeyLength);
    mIndex := mIndex + mKeyLength;
    if (mIndex < ATo) and (ALine[mIndex] = ':') then
      Inc(mIndex);
    ATodo.Text := Trim(Copy(ALine, mIndex, ATo - mIndex));
  end;
  Result := True;
end;

{ TAtlasNewIssues }

class function TAtlasNewIssues.TodoAt(const ALine: string; out ATodo: TAtlasTodoComment): Boolean;
var
  mIndex, mClose: Integer;
  mInString: Boolean;
begin
  ATodo := Default(TAtlasTodoComment);
  Result := False;
  mInString := False;
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    if ALine[mIndex] = '''' then
      mInString := not mInString
    else if not mInString then
    begin
      if (ALine[mIndex] = '/') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '/') then
      begin
        mClose := mIndex + 2;
        // "///" (XML-Doku) zählt wie "//".
        while (mClose <= Length(ALine)) and (ALine[mClose] = '/') do
          Inc(mClose);
        Exit(ParseBody(ALine, mClose, Length(ALine) + 1, TAtlasTodoStyle.Slashes, ATodo));
      end;
      if (ALine[mIndex] = '{') then
      begin
        mClose := Pos('}', ALine, mIndex + 1);
        if mClose = 0 then
          mClose := Length(ALine) + 1;
        if ((mIndex = Length(ALine)) or (ALine[mIndex + 1] <> '$')) and
          ParseBody(ALine, mIndex + 1, mClose, TAtlasTodoStyle.Braces, ATodo) then
          Exit(True);
        mIndex := mClose;
      end
      else if (ALine[mIndex] = '(') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '*') then
      begin
        mClose := Pos('*)', ALine, mIndex + 2);
        if mClose = 0 then
          mClose := Length(ALine) + 1;
        if ((mIndex + 2 > Length(ALine)) or (ALine[mIndex + 2] <> '$')) and
          ParseBody(ALine, mIndex + 2, mClose, TAtlasTodoStyle.Parens, ATodo) then
          Exit(True);
        mIndex := mClose + 1;
      end;
    end;
    Inc(mIndex);
  end;
end;

class function TAtlasNewIssues.WithKey(const ALine, AKey: string): string;
var
  mTodo: TAtlasTodoComment;
  mKey, mInsert: string;
begin
  Result := ALine;
  mKey := Trim(AKey);
  if (mKey = '') or not TodoAt(ALine, mTodo) or (mTodo.Key <> '') then
    Exit;
  if mTodo.HasOptions then
  begin
    // { TODO -oMarco : Text } → { TODO -oMarco : ATL-130: Text }
    mInsert := mKey + ': ';
    if mTodo.Text = '' then
      mInsert := mKey + ' ';
    Result := TrimRight(Copy(ALine, 1, mTodo.TextStart - 1) + mInsert + Copy(ALine, mTodo.TextStart, MaxInt));
    Exit;
  end;
  // // TODO Text → // TODO ATL-130: Text; ohne Text // TODO ATL-130 (bei { } mit Leerzeichen davor).
  mInsert := ' ' + mKey;
  if mTodo.Text <> '' then
    mInsert := mInsert + ': '
  else if mTodo.Style <> TAtlasTodoStyle.Slashes then
    mInsert := mInsert + ' ';
  Result := Copy(ALine, 1, mTodo.KeywordEnd - 1) + mInsert + Copy(ALine, mTodo.TextStart, MaxInt);
  if mTodo.Style = TAtlasTodoStyle.Slashes then
    Result := TrimRight(Result);
end;

class function TAtlasNewIssues.KeyComment(const AKey: string): string;
begin
  Result := '// ' + Trim(AKey);
end;

class function TAtlasNewIssues.WithKeyComment(const ALine, AKey: string): string;
begin
  Result := TrimRight(ALine);
  if Trim(Result) = '' then
    Exit(ALine + KeyComment(AKey));
  Result := Result + ' ' + KeyComment(AKey);
end;

class function TAtlasNewIssues.ShortTitle(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(StringReplace(AText, #13#10, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]), #9, ' ', [rfReplaceAll]));
  if Length(Result) > MaxTitle then
    Result := TrimRight(Copy(Result, 1, MaxTitle - 1)) + '…';
end;

class function TAtlasNewIssues.TitleOf(const AContext: TAtlasNewIssueContext): string;
var
  mLine: string;
  mTodo: TAtlasTodoComment;
begin
  Result := '';
  if Trim(AContext.Selection) <> '' then
  begin
    for mLine in TTextLines.SplitLines(AContext.Selection) do
      if Trim(mLine) <> '' then
      begin
        // Steht ein TODO in der ersten Zeile, gilt dessen Text.
        if TodoAt(mLine, mTodo) and (mTodo.Text <> '') then
          Exit(ShortTitle(mTodo.Text));
        Exit(ShortTitle(mLine));
      end;
    Exit;
  end;
  if (AContext.Line >= 1) and (AContext.Line <= Length(AContext.Lines)) and
    TodoAt(AContext.Lines[AContext.Line - 1], mTodo) then
    Result := ShortTitle(mTodo.Text);
end;

/// <summary>Gemeinsame Einrückung aller nicht leeren Zeilen entfernen, leere Zeilen am Rand weglassen.</summary>
function Dedent(const ALines: TArray<string>): string;
var
  mLine: string;
  mIndent, mCount, mFirst, mLast, mIndex: Integer;
begin
  Result := '';
  mFirst := 0;
  while (mFirst <= High(ALines)) and (Trim(ALines[mFirst]) = '') do
    Inc(mFirst);
  mLast := High(ALines);
  while (mLast >= mFirst) and (Trim(ALines[mLast]) = '') do
    Dec(mLast);
  if mFirst > mLast then
    Exit;
  mIndent := MaxInt;
  for mIndex := mFirst to mLast do
  begin
    mLine := ALines[mIndex];
    if Trim(mLine) = '' then
      Continue;
    mCount := 0;
    while (mCount < Length(mLine)) and IsSpace(mLine[mCount + 1]) do
      Inc(mCount);
    if mCount < mIndent then
      mIndent := mCount;
  end;
  for mIndex := mFirst to mLast do
  begin
    if mIndex > mFirst then
      Result := Result + #10;
    Result := Result + TrimRight(Copy(ALines[mIndex], mIndent + 1, MaxInt));
  end;
end;

class function TAtlasNewIssues.CodeOf(const AContext: TAtlasNewIssueContext): string;
var
  mLines: TArray<string>;
  mFrom, mTo: Integer;
begin
  if Trim(AContext.Selection) <> '' then
  begin
    mLines := TTextLines.SplitLines(AContext.Selection);
    if Length(mLines) > MaxCodeLines then
      SetLength(mLines, MaxCodeLines);
    Exit(Dedent(mLines));
  end;
  Result := '';
  if (AContext.Line < 1) or (AContext.Line > Length(AContext.Lines)) then
    Exit;
  mFrom := AContext.Line - 1 - ContextLines;
  if mFrom < 0 then
    mFrom := 0;
  mTo := AContext.Line - 1 + ContextLines;
  if mTo > High(AContext.Lines) then
    mTo := High(AContext.Lines);
  Result := Dedent(Copy(AContext.Lines, mFrom, mTo - mFrom + 1));
end;

class function TAtlasNewIssues.CodeBlock(const ACode: string): string;
var
  mFence: string;
begin
  mFence := '```';
  if Pos('```', ACode) > 0 then
    mFence := '~~~';
  Result := mFence + 'pascal' + #10 + ACode + #10 + mFence;
end;

function ShortCommit(const ACommit: string): string;
begin
  Result := Trim(ACommit);
  // Git-Hash auf 7 Zeichen; SVN-Revisionen sind kurz.
  if Length(Result) > 12 then
    Result := Copy(Result, 1, 7);
end;

class function TAtlasNewIssues.DescriptionOf(const AContext: TAtlasNewIssueContext;
  const ALabels: TAtlasNewIssueLabels): string;
var
  mLine: Integer;
begin
  Result := '';
  mLine := AContext.Line;
  if (Trim(AContext.Selection) <> '') and (AContext.SelectionLine > 0) then
    mLine := AContext.SelectionLine;
  if AContext.FileName <> '' then
  begin
    Result := ALabels.Location + ': `' + ExtractFileName(AContext.FileName) + '`';
    if mLine > 0 then
      Result := Result + ', ' + ALabels.Line + ' ' + IntToStr(mLine);
    Result := Result + #10;
  end;
  if AContext.Method <> '' then
    Result := Result + ALabels.Method + ': `' + AContext.Method + '`' + #10;
  if AContext.Branch <> '' then
  begin
    Result := Result + ALabels.Branch + ': `' + AContext.Branch + '`';
    if AContext.Commit <> '' then
      Result := Result + ' (' + ALabels.Commit + ' `' + ShortCommit(AContext.Commit) + '`)';
    Result := Result + #10;
  end
  else if AContext.Commit <> '' then
    Result := Result + ALabels.Commit + ': `' + ShortCommit(AContext.Commit) + '`' + #10;
  Result := TrimRight(Result);
end;

class function TAtlasNewIssues.Compose(const ADescription, ACode: string; AIncludeCode: Boolean): string;
var
  mCode: string;
begin
  Result := TrimRight(StringReplace(ADescription, #13#10, #10, [rfReplaceAll]));
  mCode := StringReplace(ACode, #13#10, #10, [rfReplaceAll]);
  while (mCode <> '') and CharInSet(mCode[Length(mCode)], [#10, ' ', #9]) do
    Delete(mCode, Length(mCode), 1);
  if not AIncludeCode or (Trim(mCode) = '') then
    Exit;
  if Result <> '' then
    Result := Result + #10#10;
  Result := Result + CodeBlock(mCode);
end;

function UnitOfLocation(const ALocation: string): string;
var
  mIndex: Integer;
begin
  Result := ALocation;
  // "Unit1.pas:12:5" → "Unit1.pas"; Laufwerksbuchstaben gibt es in der Fundstelle nicht.
  mIndex := Pos(':', Result);
  if mIndex > 0 then
    Result := Copy(Result, 1, mIndex - 1);
end;

class function TAtlasNewIssues.TitleOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>;
  const ALabels: TAtlasNewIssueLabels): string;
begin
  Result := '';
  if Length(AFindings) = 0 then
    Exit;
  if Length(AFindings) = 1 then
  begin
    Result := AFindings[0].Message;
    if AFindings[0].Rule <> '' then
      Result := AFindings[0].Rule + ': ' + Result;
    Exit(ShortTitle(Result));
  end;
  Result := ShortTitle(Format(ALabels.FindingsTitle, [Length(AFindings), UnitOfLocation(AFindings[0].Location)]));
end;

class function TAtlasNewIssues.DescriptionOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>;
  const AContext: TAtlasNewIssueContext; const ALabels: TAtlasNewIssueLabels): string;
var
  mFinding: TAtlasNewIssueFinding;
  mLine, mHead: string;
begin
  Result := '';
  if Length(AFindings) = 0 then
    Exit;
  mHead := '';
  if AContext.Branch <> '' then
  begin
    mHead := ALabels.Branch + ': `' + AContext.Branch + '`';
    if AContext.Commit <> '' then
      mHead := mHead + ' (' + ALabels.Commit + ' `' + ShortCommit(AContext.Commit) + '`)';
    mHead := mHead + #10#10;
  end;
  Result := mHead + ALabels.Findings + ':' + #10;
  for mFinding in AFindings do
  begin
    mLine := '- ';
    if mFinding.Rule <> '' then
      mLine := mLine + '`' + mFinding.Rule + '` ';
    mLine := mLine + mFinding.Message;
    if mFinding.Location <> '' then
      mLine := mLine + ' – `' + mFinding.Location + '`';
    Result := Result + mLine + #10;
  end;
  Result := TrimRight(Result);
end;

class function TAtlasNewIssues.CodeOfFindings(const AFindings: TArray<TAtlasNewIssueFinding>): string;
var
  mFinding: TAtlasNewIssueFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    if Trim(mFinding.LineText) = '' then
      Continue;
    if Result <> '' then
      Result := Result + #10;
    if mFinding.Location <> '' then
      Result := Result + '// ' + mFinding.Location + #10;
    Result := Result + Trim(mFinding.LineText);
  end;
end;

{ JSON }

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  mValue := AObject.Values[AName];
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsInt;
end;

function IsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
    if SameText(AName, mName) then
      Exit(True);
end;

function AddUnique(const AItems: TArray<string>; const AValue: string): TArray<string>;
var
  mItem: string;
begin
  Result := AItems;
  if (AValue = '') or (Length(Result) >= TAtlasNewIssues.MaxValues) then
    Exit;
  for mItem in Result do
    if SameText(mItem, AValue) then
      Exit;
  Result := Result + [AValue];
end;

class function TAtlasNewIssues.ParseNames(const AText, AName: string; out ANames: TArray<string>): Boolean;
var
  mRoot, mItem: TJSONValue;
begin
  ANames := nil;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONArray;
    if not Result then
      Exit;
    for mItem in TJSONArray(mRoot) do
      if mItem is TJSONObject then
        ANames := AddUnique(ANames, TextOf(TJSONObject(mItem), AName));
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNewIssues.ParseLogin(const AText: string): string;
var
  mRoot: TJSONValue;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if mRoot is TJSONObject then
      Result := TextOf(TJSONObject(mRoot), 'login');
  finally
    mRoot.Free;
  end;
end;

{ YouTrack }

class function TAtlasNewIssues.YouTrackProjectsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
    Result := ATarget.Url + '/api/admin/projects?fields=id,shortName&$top=500';
end;

class function TAtlasNewIssues.ParseYouTrackProject(const AText, AShortName: string; out AId: string): Boolean;
var
  mRoot, mItem: TJSONValue;
begin
  AId := '';
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONArray) then
      Exit;
    for mItem in TJSONArray(mRoot) do
      if (mItem is TJSONObject) and SameText(TextOf(TJSONObject(mItem), 'shortName'), Trim(AShortName)) then
      begin
        AId := TextOf(TJSONObject(mItem), 'id');
        Exit(AId <> '');
      end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNewIssues.YouTrackFieldsUrl(const ATarget: TAtlasTrackerTarget;
  const AProjectId: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or (AProjectId = '') then
    Exit;
  Result := ATarget.Url + '/api/admin/projects/' + TTextUris.PercentEncode(AProjectId) + '/customFields?fields=' +
    TTextUris.PercentEncode('field(name),bundle(values(name,login),aggregatedUsers(login))') + '&$top=100';
end;

/// <summary>Namen bzw. Anmeldenamen aus "values" und "aggregatedUsers" eines Bündels.</summary>
function BundleValues(ABundle: TJSONObject; AUsers: Boolean): TArray<string>;
var
  mList, mItem: TJSONValue;
  mName: string;
begin
  Result := nil;
  if ABundle = nil then
    Exit;
  mList := ABundle.Values['values'];
  if mList is TJSONArray then
    for mItem in TJSONArray(mList) do
      if mItem is TJSONObject then
      begin
        mName := '';
        if AUsers then
          mName := TextOf(TJSONObject(mItem), 'login');
        if mName = '' then
          mName := TextOf(TJSONObject(mItem), 'name');
        Result := AddUnique(Result, mName);
      end;
  if not AUsers then
    Exit;
  mList := ABundle.Values['aggregatedUsers'];
  if mList is TJSONArray then
    for mItem in TJSONArray(mList) do
      if mItem is TJSONObject then
        Result := AddUnique(Result, TextOf(TJSONObject(mItem), 'login'));
end;

class function TAtlasNewIssues.ParseYouTrackFields(const AText: string; var AFields: TAtlasNewIssueFields): Boolean;
var
  mRoot, mItem, mField, mBundle: TJSONValue;
  mName: string;
begin
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mField := TJSONObject(mItem).Values['field'];
      if not (mField is TJSONObject) then
        Continue;
      mName := TextOf(TJSONObject(mField), 'name');
      mBundle := TJSONObject(mItem).Values['bundle'];
      if not (mBundle is TJSONObject) then
        mBundle := nil;
      if IsOneOf(mName, YouTrackTypeNames) and (AFields.TypeField = '') then
      begin
        AFields.TypeField := mName;
        AFields.Types := BundleValues(TJSONObject(mBundle), False);
      end
      else if IsOneOf(mName, YouTrackPriorityNames) and (AFields.PriorityField = '') then
      begin
        AFields.PriorityField := mName;
        AFields.Priorities := BundleValues(TJSONObject(mBundle), False);
      end
      else if IsOneOf(mName, YouTrackAssigneeNames) and (AFields.AssigneeField = '') then
      begin
        AFields.AssigneeField := mName;
        AFields.Assignees := BundleValues(TJSONObject(mBundle), True);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNewIssues.YouTrackCreateUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
    Result := ATarget.Url + '/api/issues?fields=idReadable,numberInProject';
end;

function FieldName(const AName, ADefault: string): string;
begin
  Result := Trim(AName);
  if Result = '' then
    Result := ADefault;
end;

function EnumField(const AName, AValue: string): TJSONObject;
var
  mValue: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('$type', 'SingleEnumIssueCustomField');
  mValue := TJSONObject.Create;
  mValue.AddPair('name', AValue);
  Result.AddPair('value', mValue);
end;

function AssigneeOf(const ADraft: TAtlasNewIssueDraft; const AMe: string): string;
begin
  Result := Trim(ADraft.Assignee);
  if ADraft.AssignToMe and (AMe <> '') then
    Result := AMe;
end;

class function TAtlasNewIssues.YouTrackBody(const AProjectId: string; const ADraft: TAtlasNewIssueDraft;
  const AMe: string): string;
var
  mRoot, mProject, mUser, mField: TJSONObject;
  mFields: TJSONArray;
  mAssignee: string;
begin
  mRoot := TJSONObject.Create;
  try
    mProject := TJSONObject.Create;
    mProject.AddPair('id', AProjectId);
    mRoot.AddPair('project', mProject);
    mRoot.AddPair('summary', Trim(ADraft.Title));
    mRoot.AddPair('description', ADraft.Description);
    mFields := TJSONArray.Create;
    mRoot.AddPair('customFields', mFields);
    if Trim(ADraft.IssueType) <> '' then
      mFields.AddElement(EnumField(FieldName(ADraft.TypeField, 'Type'), Trim(ADraft.IssueType)));
    if Trim(ADraft.Priority) <> '' then
      mFields.AddElement(EnumField(FieldName(ADraft.PriorityField, 'Priority'), Trim(ADraft.Priority)));
    mAssignee := AssigneeOf(ADraft, AMe);
    if mAssignee <> '' then
    begin
      mField := TJSONObject.Create;
      mField.AddPair('name', FieldName(ADraft.AssigneeField, 'Assignee'));
      mField.AddPair('$type', 'SingleUserIssueCustomField');
      mUser := TJSONObject.Create;
      mUser.AddPair('login', mAssignee);
      mField.AddPair('value', mUser);
      mFields.AddElement(mField);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNewIssues.ParseYouTrackCreated(const AText: string; out AKey: string;
  out ANumber: Integer): Boolean;
var
  mRoot: TJSONValue;
begin
  AKey := '';
  ANumber := 0;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if mRoot is TJSONObject then
    begin
      AKey := TextOf(TJSONObject(mRoot), 'idReadable');
      ANumber := NumberOf(TJSONObject(mRoot), 'numberInProject');
    end;
  finally
    mRoot.Free;
  end;
  Result := AKey <> '';
end;

{ GitHub }

function RepoBase(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Configured and (TAtlasGitHubApi.Base(ATarget) <> '') then
    Result := TAtlasGitHubApi.Base(ATarget) + '/repos/' + ATarget.Project;
end;

class function TAtlasNewIssues.GitHubCreateUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := RepoBase(ATarget);
  if Result <> '' then
    Result := Result + '/issues';
end;

class function TAtlasNewIssues.GitHubLabelsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := RepoBase(ATarget);
  if Result <> '' then
    Result := Result + '/labels?per_page=100';
end;

class function TAtlasNewIssues.GitHubAssigneesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := RepoBase(ATarget);
  if Result <> '' then
    Result := Result + '/assignees?per_page=100';
end;

class function TAtlasNewIssues.GitHubBody(const ADraft: TAtlasNewIssueDraft; const AMe: string): string;
var
  mRoot: TJSONObject;
  mLabels, mAssignees: TJSONArray;
  mAssignee: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('title', Trim(ADraft.Title));
    mRoot.AddPair('body', ADraft.Description);
    // Typ und Priorität sind bei GitHub Labels.
    if (Trim(ADraft.IssueType) <> '') or (Trim(ADraft.Priority) <> '') then
    begin
      mLabels := TJSONArray.Create;
      if Trim(ADraft.IssueType) <> '' then
        mLabels.Add(Trim(ADraft.IssueType));
      if (Trim(ADraft.Priority) <> '') and not SameText(Trim(ADraft.Priority), Trim(ADraft.IssueType)) then
        mLabels.Add(Trim(ADraft.Priority));
      mRoot.AddPair('labels', mLabels);
    end;
    mAssignee := AssigneeOf(ADraft, AMe);
    if mAssignee <> '' then
    begin
      mAssignees := TJSONArray.Create;
      mAssignees.Add(mAssignee);
      mRoot.AddPair('assignees', mAssignees);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNewIssues.ParseGitHubCreated(const AText: string; out ANumber: Integer): Boolean;
var
  mRoot: TJSONValue;
begin
  ANumber := 0;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if mRoot is TJSONObject then
      ANumber := NumberOf(TJSONObject(mRoot), 'number');
  finally
    mRoot.Free;
  end;
  Result := ANumber > 0;
end;

{ Ablauf }

function Remaining(const AWatch: TStopwatch): Integer;
begin
  Result := TAtlasNewIssues.TimeoutMs - Integer(AWatch.ElapsedMilliseconds);
  if Result < 1 then
    Result := 1;
end;

function IsYouTrack(const AProvider: IAtlasTrackerProvider): Boolean;
begin
  Result := SameText(AProvider.Name, TAtlasTrackerTarget.YouTrack);
end;

/// <summary>GET mit Status 200 und Text; False sonst.</summary>
function GetText(const ATransport: IAtlasCiTransport; const AUrl: string; const AWatch: TStopwatch;
  out AText: string): Boolean;
var
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  AText := '';
  Result := (AUrl <> '') and ATransport.Get(AUrl, Remaining(AWatch), mStatus, AText, mError) and (mStatus = 200);
end;

class function TAtlasNewIssues.LoadFields(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; out AFields: TAtlasNewIssueFields): Boolean;
var
  mWatch: TStopwatch;
  mText, mId: string;
  mNames: TArray<string>;
begin
  AFields := TAtlasNewIssueFields.Empty;
  Result := False;
  if (AProvider = nil) or (ATransport = nil) or not ATarget.Configured then
    Exit;
  mWatch := TStopwatch.StartNew;
  if GetText(ATransport, AProvider.ProbeUrl(ATarget), mWatch, mText) then
  begin
    AFields.Me := ParseLogin(mText);
    Result := AFields.Me <> '';
  end;
  if IsYouTrack(AProvider) then
  begin
    if (ATarget.Project <> '') and GetText(ATransport, YouTrackProjectsUrl(ATarget), mWatch, mText) and
      ParseYouTrackProject(mText, ATarget.Project, mId) and
      GetText(ATransport, YouTrackFieldsUrl(ATarget, mId), mWatch, mText) and
      ParseYouTrackFields(mText, AFields) then
      Result := True;
    Exit;
  end;
  if GetText(ATransport, GitHubLabelsUrl(ATarget), mWatch, mText) and ParseNames(mText, 'name', mNames) then
  begin
    AFields.Types := mNames;
    AFields.Priorities := mNames;
    Result := True;
  end;
  if GetText(ATransport, GitHubAssigneesUrl(ATarget), mWatch, mText) and ParseNames(mText, 'login', mNames) then
  begin
    AFields.Assignees := mNames;
    Result := True;
  end;
end;

function OutcomeOfStatus(AStatus: Integer): TAtlasNewIssueOutcome;
begin
  case AStatus of
    401, 403:
      Result := TAtlasNewIssueOutcome.Rejected;
    404:
      Result := TAtlasNewIssueOutcome.ProjectUnknown;
    400, 422:
      Result := TAtlasNewIssueOutcome.Invalid;
  else
    Result := TAtlasNewIssueOutcome.ServerError;
  end;
end;

function OutcomeOfError(AError: TAtlasCiFetchError): TAtlasNewIssueOutcome;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasNewIssueOutcome.NoToken;
    TAtlasCiFetchError.Server:
      Result := TAtlasNewIssueOutcome.ServerError;
  else
    Result := TAtlasNewIssueOutcome.Unreachable;
  end;
end;

/// <summary>AText ist gültiges JSON (sonst etwa eine Anmeldeseite).</summary>
function IsJson(const AText: string): Boolean;
var
  mRoot: TJSONValue;
begin
  mRoot := TJSONObject.ParseJSONValue(AText);
  Result := mRoot <> nil;
  mRoot.Free;
end;

/// <summary>Antwort ohne 2xx als Ergebnis.</summary>
function Failure(AStatus: Integer; const AText: string): TAtlasNewIssueResult;
begin
  Result := TAtlasNewIssueResult.Create(OutcomeOfStatus(AStatus));
  Result.HttpStatus := AStatus;
  if Result.Outcome = TAtlasNewIssueOutcome.Invalid then
    Result.TrackerMessage := TAtlasTrackerQueryTest.TrackerMessage(AText);
end;

class function TAtlasNewIssues.CreateIssue(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ADraft: TAtlasNewIssueDraft): TAtlasNewIssueResult;
var
  mSend: IAtlasCiSend;
  mWatch: TStopwatch;
  mUrl, mText, mId, mMe, mBody, mKey: string;
  mStatus, mNumber: Integer;
  mError: TAtlasCiFetchError;
begin
  if (AProvider = nil) or not ATarget.Configured or (Trim(ADraft.Title) = '') then
    Exit(TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured));
  if (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NoToken));
  mWatch := TStopwatch.StartNew;
  mId := '';
  if IsYouTrack(AProvider) then
  begin
    // YouTrack braucht die ID des Projekts, die Zuordnung kennt das Kürzel.
    if ATarget.Project = '' then
      Exit(TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.ProjectUnknown));
    if not ATransport.Get(YouTrackProjectsUrl(ATarget), Remaining(mWatch), mStatus, mText, mError) then
      Exit(TAtlasNewIssueResult.Create(OutcomeOfError(mError)));
    if mStatus <> 200 then
      Exit(Failure(mStatus, mText));
    if not ParseYouTrackProject(mText, ATarget.Project, mId) then
    begin
      Result := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.ProjectUnknown);
      if not IsJson(mText) then
        Result.Outcome := TAtlasNewIssueOutcome.Unreadable;
      Exit;
    end;
  end;
  mMe := '';
  if ADraft.AssignToMe and GetText(ATransport, AProvider.ProbeUrl(ATarget), mWatch, mText) then
    mMe := ParseLogin(mText);
  if IsYouTrack(AProvider) then
  begin
    mUrl := YouTrackCreateUrl(ATarget);
    mBody := YouTrackBody(mId, ADraft, mMe);
  end
  else
  begin
    mUrl := GitHubCreateUrl(ATarget);
    mBody := GitHubBody(ADraft, mMe);
  end;
  if mUrl = '' then
    Exit(TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured));
  if not mSend.Send('POST', mUrl, mBody, Remaining(mWatch), mStatus, mText, mError) then
    Exit(TAtlasNewIssueResult.Create(OutcomeOfError(mError)));
  if (mStatus <> 200) and (mStatus <> 201) then
    Exit(Failure(mStatus, mText));
  Result := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.Created);
  Result.HttpStatus := mStatus;
  if IsYouTrack(AProvider) then
  begin
    if ParseYouTrackCreated(mText, mKey, mNumber) then
    begin
      Result.Key := mKey;
      Result.Number := mNumber;
    end;
  end
  else if ParseGitHubCreated(mText, mNumber) then
  begin
    Result.Key := '#' + IntToStr(mNumber);
    Result.Number := mNumber;
  end;
  // Angelegt, aber die Antwort nennt keine Kennung: nichts in den Code schreiben.
  if Result.Key = '' then
  begin
    Result.Outcome := TAtlasNewIssueOutcome.Unreadable;
    Exit;
  end;
  Result.Page := AProvider.IssuePage(ATarget, Result.Key);
end;

end.
